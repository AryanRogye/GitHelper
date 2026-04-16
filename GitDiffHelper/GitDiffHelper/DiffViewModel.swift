import Foundation
import Combine

@MainActor
final class DiffViewModel: ObservableObject {
    nonisolated static let allBranchesFilterLabel = "All Branches"

    @Published var repoPath: String = ""
    @Published var baseRef: String = ""
    @Published var headRef: String = ""
    @Published var pathFilter: String = ""

    @Published private(set) var repoSummary: String = "No repository selected."
    @Published private(set) var statusLine: String = "Step 1: Choose a repository folder."
    @Published private(set) var hasError = false
    @Published private(set) var isLoadingDiff = false
    @Published private(set) var files: [DiffFile] = []
    @Published private(set) var availableBranchRefs: [String] = ["HEAD"]
    @Published private(set) var isLoadingLog = false
    @Published private(set) var logEntries: [GitLogEntry] = []
    @Published private(set) var logStatusLine = "Open Commit Log to view repository history."
    @Published private(set) var logHasError = false
    @Published var selectedLogBranchFilter = "All Branches"
    @Published private(set) var library: [RepoLibraryEntry] = []
    @Published var selectedLibraryRepoID: UUID?
    @Published var selectedLibrarySessionID: UUID?
    @Published private(set) var currentBranchRef = "HEAD"
    @Published private(set) var recentBranchCommits: [GitLogEntry] = []
    @Published private(set) var isLoadingRecentBranchCommits = false
    @Published private(set) var workingTreeChanges: [WorkingTreeChange] = []
    @Published private(set) var pendingRevealFilePath: String?

    private var hasPerformedInitialLoad = false
    private var securityScopedRepoURL: URL?
    private var hasSecurityScopedAccess = false
    private var pendingBookmarkData: Data?
    private let maxLibraryRepositories = 20
    private let maxSessionsPerRepository = 24
    private let libraryDefaultsKey = "BridgeDiff.RepoLibrary.v1"
    private let recentBranchCommitLimit = 60
    private var recentBranchCommitsLoadedForRef = ""

    deinit {
        if hasSecurityScopedAccess {
            securityScopedRepoURL?.stopAccessingSecurityScopedResource()
        }
    }

    func initialLoadIfNeeded() async {
        guard !hasPerformedInitialLoad else {
            return
        }
        hasPerformedInitialLoad = true
        loadLibrary()

        if let first = library.first {
            selectedLibraryRepoID = first.id
            await loadLibraryRepository(id: first.id)
            return
        }

        let currentDirectory = FileManager.default.currentDirectoryPath
        do {
            let repoContext = try await Task.detached {
                try GitService.repoContext(repoPath: currentDirectory)
            }.value
            repoPath = repoContext.rootPath
            repoSummary = "\(repoContext.branch) • \(repoContext.rootPath)"
            statusLine = "Repository detected. Click \"Working Changes\" to start."
            await loadUncommittedChanges()
        } catch {
            repoPath = ""
            repoSummary = "No repository selected."
            statusLine = "Step 1: Choose a repository folder."
            hasError = false
            availableBranchRefs = ["HEAD"]
            workingTreeChanges = []
            pendingRevealFilePath = nil
        }
    }

    func chooseRepository(path: String) async {
        pendingBookmarkData = nil
        clearSecurityScopedAccess()
        resetLogState()
        resetRecentBranchCommitState()
        pendingRevealFilePath = nil
        repoPath = path
        baseRef = ""
        headRef = ""
        pathFilter = ""
        await loadUncommittedChanges()
    }

    func chooseRepository(url: URL) async {
        pendingBookmarkData = bookmarkData(for: url)
        activateSecurityScopedAccess(for: url)
        resetLogState()
        resetRecentBranchCommitState()
        pendingRevealFilePath = nil
        repoPath = url.path
        baseRef = ""
        headRef = ""
        pathFilter = ""
        await loadUncommittedChanges()
    }

    func loadLibraryRepository(id: UUID) async {
        guard let entry = library.first(where: { $0.id == id }) else {
            return
        }
        selectedLibraryRepoID = id
        selectedLibrarySessionID = nil
        resetLogState()
        resetRecentBranchCommitState()
        prepareAccess(for: entry)

        if let latestSession = entry.sessions.first {
            apply(session: latestSession)
            selectedLibrarySessionID = latestSession.id
            await loadDiff()
        } else {
            baseRef = ""
            headRef = ""
            pathFilter = ""
            await loadUncommittedChanges()
        }
    }

    func loadLibrarySession(repoID: UUID, sessionID: UUID) async {
        guard let entry = library.first(where: { $0.id == repoID }) else {
            return
        }
        guard let session = entry.sessions.first(where: { $0.id == sessionID }) else {
            return
        }
        selectedLibraryRepoID = repoID
        selectedLibrarySessionID = sessionID
        prepareAccess(for: entry)
        apply(session: session)
        await loadDiff()
    }

    func removeLibraryRepository(id: UUID) {
        guard let index = library.firstIndex(where: { $0.id == id }) else {
            return
        }
        library.remove(at: index)
        persistLibrary()

        if selectedLibraryRepoID == id {
            selectedLibraryRepoID = library.first?.id
            selectedLibrarySessionID = nil
        }
    }

    func loadUncommittedChanges() async {
        baseRef = ""
        headRef = ""
        await loadDiff()
    }

    func loadLastCommit() async {
        baseRef = "HEAD~1"
        headRef = "HEAD"
        await loadDiff()
    }

    func compareAgainstBranch(_ branchRef: String) async {
        baseRef = branchRef
        headRef = "HEAD"
        await loadDiff()
    }

    func compareAgainstCommit(_ commitHash: String) async {
        baseRef = commitHash
        headRef = ""
        await loadDiff()
    }

    func compareBetweenCommits(baseHash: String, headHash: String) async {
        baseRef = baseHash
        headRef = headHash
        await loadDiff()
    }

    func refreshWorkingTreeChanges() async {
        let repoPath = self.repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoPath.isEmpty else {
            workingTreeChanges = []
            return
        }

        do {
            workingTreeChanges = try await Task.detached {
                try GitService.workingTreeChanges(repoPath: repoPath)
            }.value
        } catch {
            workingTreeChanges = []
        }
    }

    func openWorkingTreeChange(path: String) async {
        let activeRepo = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activeRepo.isEmpty else {
            return
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            return
        }

        pendingRevealFilePath = nil
        pathFilter = ""
        await loadUncommittedChanges()
        pendingRevealFilePath = normalizedPath
    }

    func clearPendingRevealFilePath() {
        pendingRevealFilePath = nil
    }

    func loadRecentBranchCommits(force: Bool = false) async {
        let repoPath = self.repoPath
        let branchRef = currentBranchRef.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recentBranchCommits = []
            recentBranchCommitsLoadedForRef = ""
            return
        }
        guard !branchRef.isEmpty else {
            recentBranchCommits = []
            recentBranchCommitsLoadedForRef = ""
            return
        }
        guard force || recentBranchCommitsLoadedForRef != branchRef || recentBranchCommits.isEmpty else {
            return
        }

        isLoadingRecentBranchCommits = true
        defer { isLoadingRecentBranchCommits = false }

        do {
            let commitLimit = recentBranchCommitLimit
            let commits = try await Task.detached {
                try GitService.commitLog(repoPath: repoPath, branchRef: branchRef, maxCount: commitLimit)
            }.value
            recentBranchCommits = commits
            recentBranchCommitsLoadedForRef = branchRef
        } catch {
            recentBranchCommits = []
            recentBranchCommitsLoadedForRef = ""
        }
    }

    func loadCommitLog(branchFilter: String? = nil) async {
        let selectedFilter = (branchFilter ?? selectedLogBranchFilter)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFilter = selectedFilter.isEmpty ? Self.allBranchesFilterLabel : selectedFilter
        selectedLogBranchFilter = normalizedFilter

        let repoPath = self.repoPath
        guard !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logEntries = []
            logHasError = true
            logStatusLine = "Choose a repository folder first."
            isLoadingLog = false
            return
        }

        isLoadingLog = true
        defer { isLoadingLog = false }
        logHasError = false
        logStatusLine = "Loading commit history..."

        do {
            let repoContextTask = Task.detached {
                try GitService.repoContext(repoPath: repoPath)
            }

            let refsTask = Task.detached {
                try GitService.branchRefs(repoPath: repoPath)
            }

            let logTask = Task.detached {
                let ref = normalizedFilter == Self.allBranchesFilterLabel ? nil : normalizedFilter
                return try GitService.commitLog(repoPath: repoPath, branchRef: ref)
            }

            let repoContext = try await repoContextTask.value
            repoSummary = "\(repoContext.branch) • \(repoContext.rootPath)"

            if let refs = try? await refsTask.value, !refs.isEmpty {
                availableBranchRefs = refs
            } else {
                availableBranchRefs = ["HEAD", repoContext.branch]
            }

            let history = try await logTask.value
            logEntries = history

            if history.isEmpty {
                logStatusLine = normalizedFilter == Self.allBranchesFilterLabel
                    ? "No commits found."
                    : "No commits found for \(normalizedFilter)."
            } else {
                if normalizedFilter == Self.allBranchesFilterLabel {
                    logStatusLine = "Loaded \(history.count) commits from all branches."
                } else {
                    logStatusLine = "Loaded \(history.count) commits for \(normalizedFilter)."
                }
            }
        } catch {
            logEntries = []
            logHasError = true
            logStatusLine = friendlyLogErrorMessage(error)
        }
    }

    func loadDiff() async {
        let repoPath = self.repoPath
        let baseRef = self.baseRef
        let headRef = self.headRef
        let pathFilter = self.pathFilter

        guard !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            files = []
            repoSummary = "No repository selected."
            hasError = true
            statusLine = "Choose a repository folder first."
            isLoadingDiff = false
            workingTreeChanges = []
            return
        }

        let workingTreeTask = Task.detached {
            try GitService.workingTreeChanges(repoPath: repoPath)
        }

        isLoadingDiff = true
        defer { isLoadingDiff = false }
        statusLine = "Loading diff from git..."
        hasError = false

        do {
            let repoContextTask = Task.detached {
                try GitService.repoContext(repoPath: repoPath)
            }

            let diffTask = Task.detached {
                try GitService.diff(repoPath: repoPath, baseRef: baseRef, headRef: headRef, pathFilter: pathFilter)
            }

            let refsTask = Task.detached {
                try GitService.branchRefs(repoPath: repoPath)
            }

            let repoContext = try await repoContextTask.value
            repoSummary = "\(repoContext.branch) • \(repoContext.rootPath)"
            if currentBranchRef != repoContext.branch {
                currentBranchRef = repoContext.branch
                recentBranchCommits = []
                recentBranchCommitsLoadedForRef = ""
            }
            if let refs = try? await refsTask.value, !refs.isEmpty {
                availableBranchRefs = refs
            } else {
                availableBranchRefs = ["HEAD", repoContext.branch]
            }

            let diff = try await diffTask.value
            statusLine = "Parsing diff..."
            let parsed = await parseDiffOffMain(diff)
            files = parsed

            recordSession(
                repoContext: repoContext,
                selectedPath: repoPath,
                comparedBaseRef: baseRef,
                comparedHeadRef: headRef,
                comparedPathFilter: pathFilter,
                parsed: parsed
            )

            if parsed.isEmpty {
                statusLine = "No differences found for this comparison. Try \"Recent Commit\" or clear the path filter."
            } else {
                let hunkCount = parsed.reduce(0) { $0 + $1.hunks.count }
                let bridgeCount = parsed.reduce(0) { total, file in
                    total + file.hunks.reduce(0) { $0 + $1.bridges.count }
                }
                statusLine = "Rendered \(parsed.count) files, \(hunkCount) hunks, \(bridgeCount) curved bridges."
            }
            workingTreeChanges = (try? await workingTreeTask.value) ?? []
        } catch {
            files = []
            hasError = true
            repoSummary = "Repository unavailable."
            statusLine = friendlyErrorMessage(error)
            availableBranchRefs = ["HEAD"]
            workingTreeChanges = (try? await workingTreeTask.value) ?? []
        }
    }

    private func parseDiffOffMain(_ diff: String) async -> [DiffFile] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let parsed = DiffParser.parse(diff)
                continuation.resume(returning: parsed)
            }
        }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let bridgeError = error as? BridgeDiffError {
            switch bridgeError {
            case .notGitRepository:
                return "That folder is not a Git repository. Pick the project folder that contains .git."
            case .invalidRef(let refName):
                return "The \(refName) value is invalid. Use a branch name or commit reference."
            case .invalidPathFilter:
                return "The path filter is invalid."
            case .repositoryNotFound:
                return "The selected folder does not exist."
            case .repositoryNotDirectory:
                return "The selected path is not a folder."
            case .gitCommandFailed(let message):
                return "Git error: \(message)"
            }
        }
        return "Error: \(error.localizedDescription)"
    }

    private func friendlyLogErrorMessage(_ error: Error) -> String {
        if let bridgeError = error as? BridgeDiffError {
            switch bridgeError {
            case .notGitRepository:
                return "That folder is not a Git repository. Pick the project folder that contains .git."
            case .invalidRef:
                return "The selected branch is invalid."
            case .invalidPathFilter:
                return "The selected filter is invalid."
            case .repositoryNotFound:
                return "The selected folder does not exist."
            case .repositoryNotDirectory:
                return "The selected path is not a folder."
            case .gitCommandFailed(let message):
                return "Git log error: \(message)"
            }
        }
        return "Error loading commit history: \(error.localizedDescription)"
    }

    private func resetLogState() {
        selectedLogBranchFilter = Self.allBranchesFilterLabel
        logEntries = []
        logHasError = false
        logStatusLine = "Open Commit Log to view repository history."
        isLoadingLog = false
    }

    private func resetRecentBranchCommitState() {
        currentBranchRef = "HEAD"
        recentBranchCommits = []
        isLoadingRecentBranchCommits = false
        recentBranchCommitsLoadedForRef = ""
    }

    private func activateSecurityScopedAccess(for url: URL) {
        clearSecurityScopedAccess()
        let granted = url.startAccessingSecurityScopedResource()
        securityScopedRepoURL = url
        hasSecurityScopedAccess = granted
    }

    private func clearSecurityScopedAccess() {
        if hasSecurityScopedAccess {
            securityScopedRepoURL?.stopAccessingSecurityScopedResource()
        }
        hasSecurityScopedAccess = false
        securityScopedRepoURL = nil
    }

    private func loadLibrary() {
        guard let data = UserDefaults.standard.data(forKey: libraryDefaultsKey) else {
            library = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([RepoLibraryEntry].self, from: data)
            library = decoded.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        } catch {
            library = []
        }
    }

    private func persistLibrary() {
        do {
            let data = try JSONEncoder().encode(library)
            UserDefaults.standard.set(data, forKey: libraryDefaultsKey)
        } catch {
            // Ignore persistence failures; app remains functional.
        }
    }

    private func recordSession(
        repoContext: RepoContext,
        selectedPath: String,
        comparedBaseRef: String,
        comparedHeadRef: String,
        comparedPathFilter: String,
        parsed: [DiffFile]
    ) {
        let fileCount = parsed.count
        let hunkCount = parsed.reduce(0) { $0 + $1.hunks.count }
        let bridgeCount = parsed.reduce(0) { total, file in
            total + file.hunks.reduce(0) { $0 + $1.bridges.count }
        }
        let session = RepoSessionEntry(
            baseRef: comparedBaseRef,
            headRef: comparedHeadRef,
            pathFilter: comparedPathFilter,
            fileCount: fileCount,
            hunkCount: hunkCount,
            bridgeCount: bridgeCount
        )

        let displayName = URL(fileURLWithPath: repoContext.rootPath).lastPathComponent
        let bookmark = pendingBookmarkData ?? {
            guard let currentURL = securityScopedRepoURL else {
                return nil
            }
            return bookmarkData(for: currentURL)
        }()
        pendingBookmarkData = nil

        if let existingIndex = library.firstIndex(where: { $0.rootPath == repoContext.rootPath }) {
            var entry = library.remove(at: existingIndex)
            entry.selectedPath = selectedPath
            entry.rootPath = repoContext.rootPath
            entry.displayName = displayName
            entry.lastBranch = repoContext.branch
            entry.lastOpenedAt = Date()
            if let bookmark {
                entry.bookmarkData = bookmark
            }
            upsert(session: session, into: &entry.sessions)
            library.insert(entry, at: 0)
            selectedLibraryRepoID = entry.id
            selectedLibrarySessionID = entry.sessions.first?.id
        } else {
            var sessions: [RepoSessionEntry] = []
            upsert(session: session, into: &sessions)
            let entry = RepoLibraryEntry(
                selectedPath: selectedPath,
                rootPath: repoContext.rootPath,
                displayName: displayName,
                lastBranch: repoContext.branch,
                bookmarkData: bookmark,
                sessions: sessions
            )
            library.insert(entry, at: 0)
            selectedLibraryRepoID = entry.id
            selectedLibrarySessionID = entry.sessions.first?.id
        }

        if library.count > maxLibraryRepositories {
            library = Array(library.prefix(maxLibraryRepositories))
        }
        persistLibrary()
    }

    private func upsert(session: RepoSessionEntry, into sessions: inout [RepoSessionEntry]) {
        if let existingIndex = sessions.firstIndex(where: {
            $0.baseRef == session.baseRef &&
            $0.headRef == session.headRef &&
            $0.pathFilter == session.pathFilter
        }) {
            sessions.remove(at: existingIndex)
        }
        sessions.insert(session, at: 0)
        if sessions.count > maxSessionsPerRepository {
            sessions = Array(sessions.prefix(maxSessionsPerRepository))
        }
    }

    private func prepareAccess(for entry: RepoLibraryEntry) {
        if let bookmarkData = entry.bookmarkData {
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                activateSecurityScopedAccess(for: resolvedURL)
                repoPath = resolvedURL.path
                if isStale {
                    pendingBookmarkData = self.bookmarkData(for: resolvedURL)
                }
                return
            } catch {
                clearSecurityScopedAccess()
            }
        }

        clearSecurityScopedAccess()
        repoPath = entry.selectedPath
    }

    private func apply(session: RepoSessionEntry) {
        baseRef = session.baseRef
        headRef = session.headRef
        pathFilter = session.pathFilter
    }

    private func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
    
    public func ensureCommitLogLoaded() async {
        guard !repoPath.isEmpty, !isLoadingLog else {
            return
        }
        if logEntries.isEmpty || logHasError {
            await loadCommitLog(branchFilter: selectedLogBranchFilter)
        }
    }
}
