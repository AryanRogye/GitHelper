import Foundation

@MainActor
final class DiffViewModel: ObservableObject {
    @Published var repoPath: String = ""
    @Published var baseRef: String = ""
    @Published var headRef: String = ""
    @Published var pathFilter: String = ""

    @Published private(set) var repoSummary: String = "No repository selected."
    @Published private(set) var statusLine: String = "Step 1: Choose a repository folder."
    @Published private(set) var hasError = false
    @Published private(set) var files: [DiffFile] = []

    private var hasPerformedInitialLoad = false

    func initialLoadIfNeeded() async {
        guard !hasPerformedInitialLoad else {
            return
        }
        hasPerformedInitialLoad = true
        let currentDirectory = FileManager.default.currentDirectoryPath
        do {
            let repoContext = try await Task.detached {
                try GitService.repoContext(repoPath: currentDirectory)
            }.value
            repoPath = repoContext.rootPath
            repoSummary = "\(repoContext.branch) • \(repoContext.rootPath)"
            statusLine = "Repository detected. Click \"Show Uncommitted Changes\" to start."
        } catch {
            repoPath = ""
            repoSummary = "No repository selected."
            statusLine = "Step 1: Choose a repository folder."
            hasError = false
        }
    }

    func chooseRepository(path: String) async {
        repoPath = path
        baseRef = ""
        headRef = ""
        pathFilter = ""
        await loadUncommittedChanges()
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

    func renderSample() {
        let parsed = DiffParser.parse(Self.sampleDiff)
        files = parsed
        hasError = false
        repoSummary = "Sample mode"
        statusLine = "Rendered sample diff."
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
            return
        }

        statusLine = "Loading diff from git..."
        hasError = false

        do {
            let repoContextTask = Task.detached {
                try GitService.repoContext(repoPath: repoPath)
            }

            let diffTask = Task.detached {
                try GitService.diff(repoPath: repoPath, baseRef: baseRef, headRef: headRef, pathFilter: pathFilter)
            }

            let repoContext = try await repoContextTask.value
            repoSummary = "\(repoContext.branch) • \(repoContext.rootPath)"
            if self.repoPath != repoContext.rootPath {
                self.repoPath = repoContext.rootPath
            }

            let diff = try await diffTask.value
            let parsed = DiffParser.parse(diff)
            files = parsed

            if parsed.isEmpty {
                statusLine = "No differences found for this comparison. Try \"Last Commit\" or clear path filter."
            } else {
                let hunkCount = parsed.reduce(0) { $0 + $1.hunks.count }
                let bridgeCount = parsed.reduce(0) { total, file in
                    total + file.hunks.reduce(0) { $0 + $1.bridges.count }
                }
                statusLine = "Rendered \(parsed.count) files, \(hunkCount) hunks, \(bridgeCount) curved bridges."
            }
        } catch {
            files = []
            hasError = true
            repoSummary = "Repository unavailable."
            statusLine = friendlyErrorMessage(error)
        }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let bridgeError = error as? BridgeDiffError {
            switch bridgeError {
            case .notGitRepository:
                return "That folder is not a Git repository. Pick the project folder that contains .git."
            case .invalidRef(let refName):
                return "The \(refName) value is invalid. Use values like HEAD, HEAD~1, or a branch name."
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

    private static let sampleDiff = """
    diff --git a/src/bridge-path.swift b/src/bridge-path.swift
    index 7b66abc..93adf81 100644
    --- a/src/bridge-path.swift
    +++ b/src/bridge-path.swift
    @@ -11,10 +11,13 @@ func buildBridge(startX: CGFloat, startY: CGFloat, endX: CGFloat, endY: CGFloat) -> Path {
    -    let span = endX - startX
    -    let curve = 0.4
    -    let c1 = startX + span * curve
    -    let c2 = endX - span * curve
    -    return Path { path in
    +    let span = max(90, endX - startX)
    +    let curve = 0.34
    +    let lift = min(26, abs(endY - startY) * 0.22)
    +    let c1 = startX + span * curve
    +    let c2 = endX - span * curve
    +    return Path { path in
             path.move(to: CGPoint(x: startX, y: startY))
    -        path.addCurve(to: CGPoint(x: endX, y: endY), control1: CGPoint(x: c1, y: startY), control2: CGPoint(x: c2, y: endY))
    +        path.addCurve(to: CGPoint(x: endX, y: endY), control1: CGPoint(x: c1, y: startY - lift), control2: CGPoint(x: c2, y: endY + lift))
         }
     }
    """
}
