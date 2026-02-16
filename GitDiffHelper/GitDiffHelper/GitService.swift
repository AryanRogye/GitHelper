import Foundation

enum GitService {
    nonisolated static func repoContext(repoPath: String) throws -> RepoContext {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repositoryURL).trimmed()
        let root = try runGit(["rev-parse", "--show-toplevel"], in: repositoryURL).trimmed()
        return RepoContext(branch: branch, rootPath: root)
    }

    nonisolated static func diff(
        repoPath: String,
        baseRef: String,
        headRef: String,
        pathFilter: String
    ) throws -> String {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)
        var args = ["diff", "--no-color", "--no-ext-diff", "--unified=4"]

        let base = baseRef.trimmed()
        let head = headRef.trimmed()
        let path = pathFilter.trimmed()

        if !base.isEmpty {
            try validateGitRef(base, name: "base")
        }
        if !head.isEmpty {
            try validateGitRef(head, name: "head")
        }

        if !base.isEmpty && !head.isEmpty {
            args.append(contentsOf: [base, head])
        } else if !base.isEmpty {
            args.append(base)
        } else if !head.isEmpty {
            args.append(head)
        } else if repositoryHasHeadCommit(repositoryURL) {
            // Use HEAD by default so "Working Changes" includes staged and unstaged edits.
            args.append("HEAD")
        }

        if !path.isEmpty {
            try validatePathFilter(path)
            args.append(contentsOf: ["--", path])
        }

        return try runGit(args, in: repositoryURL)
    }

    nonisolated static func workingTreeChanges(repoPath: String) throws -> [WorkingTreeChange] {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)
        let output = try runGit(
            ["status", "--porcelain=1", "-z", "--untracked-files=all"],
            in: repositoryURL
        )
        return parseWorkingTreeChanges(output)
    }

    nonisolated static func remotes(repoPath: String) throws -> [String] {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)
        let output = try runGit(["remote"], in: repositoryURL)
        return output
            .split(separator: "\n")
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty }
    }

    nonisolated static func currentBranch(repoPath: String) throws -> String {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)
        return try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repositoryURL).trimmed()
    }

    nonisolated static func upstreamForCurrentBranch(repoPath: String) -> String? {
        do {
            let repositoryURL = try resolveRepositoryURL(repoPath)
            try ensureGitRepository(repositoryURL)
            let upstream = try runGit(
                ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                in: repositoryURL
            ).trimmed()
            return upstream.isEmpty ? nil : upstream
        } catch {
            return nil
        }
    }

    nonisolated static func commitAndPush(
        repoPath: String,
        message: String,
        remote: String
    ) throws {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)

        let commitMessage = message.trimmed()
        if commitMessage.isEmpty {
            throw BridgeDiffError.gitCommandFailed("Commit message is empty.")
        }

        let pushRemote = remote.trimmed()
        if pushRemote.isEmpty {
            throw BridgeDiffError.gitCommandFailed("No remote selected for push.")
        }

        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repositoryURL).trimmed()
        if branch.isEmpty || branch == "HEAD" {
            throw BridgeDiffError.gitCommandFailed("Cannot push from detached HEAD.")
        }

        _ = try runGit(["add", "."], in: repositoryURL)
        _ = try runGit(["commit", "-m", commitMessage], in: repositoryURL)
        _ = try runGit(["push", pushRemote, branch], in: repositoryURL)
    }

    nonisolated static func branchRefs(repoPath: String) throws -> [String] {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)

        let currentBranch = (try? runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repositoryURL).trimmed()) ?? "HEAD"
        let refsRaw = try runGit(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"],
            in: repositoryURL
        )

        var refs: [String] = ["HEAD"]
        var seen = Set(refs)

        if !currentBranch.isEmpty, currentBranch != "HEAD", !seen.contains(currentBranch) {
            refs.append(currentBranch)
            seen.insert(currentBranch)
        }

        let candidates = refsRaw
            .split(separator: "\n")
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }

        for candidate in candidates where !seen.contains(candidate) {
            refs.append(candidate)
            seen.insert(candidate)
        }

        return refs
    }

    nonisolated static func commitLog(
        repoPath: String,
        branchRef: String?,
        maxCount: Int = 800
    ) throws -> [GitLogEntry] {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)

        let selectedBranch = branchRef?.trimmed() ?? ""
        if !selectedBranch.isEmpty {
            try validateGitRef(selectedBranch, name: "branch")
        }

        let baseArgs = [
            "log",
            "--date-order",
            "--no-color",
            "--decorate=short",
            "--date=unix",
            "--max-count=\(max(1, maxCount))",
            "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ct%x1f%s%x1f%D%x1f%P%x1e"
        ]

        if selectedBranch.isEmpty {
            var args = baseArgs
            args.insert("--all", at: 1)
            let output = try runGit(args, in: repositoryURL)
            return parseCommitLog(output)
        }

        if isPrimaryBranchRef(selectedBranch) {
            let output = try runGit(baseArgs + [selectedBranch], in: repositoryURL)
            return parseCommitLog(output)
        }

        let selectedAliases = canonicalBranchAliases(for: selectedBranch)
        if let baseBranch = try detectPrimaryBaseBranch(in: repositoryURL, excludingAliases: selectedAliases) {
            // Prefer branch-specific commits first.
            do {
                let rangeOutput = try runGit(baseArgs + ["\(baseBranch)..\(selectedBranch)"], in: repositoryURL)
                let rangeEntries = parseCommitLog(rangeOutput)
                if !rangeEntries.isEmpty {
                    return rangeEntries
                }
            } catch {
                // If range lookup fails, fall back to direct branch history.
            }
        }

        // If no primary base was detected (or range was empty), try commits unique
        // to this branch versus all other refs. This handles repos that do not use
        // main/master-style trunk names.
        if let uniqueOutput = try? runBranchUniqueLog(
            repositoryURL: repositoryURL,
            selectedBranch: selectedBranch,
            baseArgs: baseArgs
        ) {
            let uniqueEntries = parseCommitLog(uniqueOutput)
            if !uniqueEntries.isEmpty {
                return uniqueEntries
            }
        }

        // Fallback for branches with no unique commits (or no detectable base).
        let output = try runGit(baseArgs + [selectedBranch], in: repositoryURL)
        return parseCommitLog(output)
    }

    nonisolated private static func ensureGitRepository(_ directory: URL) throws {
        do {
            let result = try runGit(["rev-parse", "--is-inside-work-tree"], in: directory).trimmed()
            guard result == "true" else {
                throw BridgeDiffError.notGitRepository(directory.path)
            }
        } catch let BridgeDiffError.gitCommandFailed(message) {
            if message.localizedCaseInsensitiveContains("not a git repository") {
                throw BridgeDiffError.notGitRepository(directory.path)
            }
            throw BridgeDiffError.gitCommandFailed(message)
        } catch {
            throw error
        }
    }

    nonisolated private static func repositoryHasHeadCommit(_ directory: URL) -> Bool {
        do {
            _ = try runGit(["rev-parse", "--verify", "--quiet", "HEAD"], in: directory)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func validateGitRef(_ value: String, name: String) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@~^:-")
        let isValid = value.unicodeScalars.allSatisfy { allowed.contains($0) }
        if !isValid {
            throw BridgeDiffError.invalidRef(name)
        }
    }

    nonisolated private static func validatePathFilter(_ value: String) throws {
        if value.contains("\0") {
            throw BridgeDiffError.invalidPathFilter
        }
    }

    nonisolated private static func resolveRepositoryURL(_ pathValue: String) throws -> URL {
        let candidate = pathValue.trimmed().isEmpty ? "." : pathValue.trimmed()
        let expanded = NSString(string: candidate).expandingTildeInPath

        let absolutePath: String
        if expanded.hasPrefix("/") {
            absolutePath = expanded
        } else {
            let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            absolutePath = currentDirectory.appendingPathComponent(expanded).path
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory) else {
            throw BridgeDiffError.repositoryNotFound(absolutePath)
        }
        guard isDirectory.boolValue else {
            throw BridgeDiffError.repositoryNotDirectory(absolutePath)
        }

        return URL(fileURLWithPath: absolutePath, isDirectory: true)
    }

    nonisolated private static func runGit(_ args: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: outputData, as: UTF8.self)
        if process.terminationStatus != 0 {
            let message = output.trimmed().isEmpty ? "Git command failed." : output.trimmed()
            throw BridgeDiffError.gitCommandFailed(message)
        }
        return output
    }

    nonisolated private static func parseWorkingTreeChanges(_ output: String) -> [WorkingTreeChange] {
        let records = output.split(separator: "\0", omittingEmptySubsequences: true)
        guard !records.isEmpty else {
            return []
        }

        var changes: [WorkingTreeChange] = []
        changes.reserveCapacity(records.count)

        var index = 0
        while index < records.count {
            let record = String(records[index])
            guard record.count >= 4 else {
                index += 1
                continue
            }

            let statusCode = String(record.prefix(2))
            let currentPath = String(record.dropFirst(3))
            let isRenameOrCopy = statusCode.contains("R") || statusCode.contains("C")

            if isRenameOrCopy, index + 1 < records.count {
                let newPath = String(records[index + 1])
                changes.append(
                    WorkingTreeChange(
                        statusCode: statusCode,
                        path: newPath,
                        originalPath: currentPath
                    )
                )
                index += 2
                continue
            }

            changes.append(
                WorkingTreeChange(
                    statusCode: statusCode,
                    path: currentPath,
                    originalPath: nil
                )
            )
            index += 1
        }

        return changes
    }

    nonisolated private static func parseCommitLog(_ output: String) -> [GitLogEntry] {
        let recordSeparator: Character = "\u{001E}"
        let fieldSeparator: Character = "\u{001F}"

        var entries: [GitLogEntry] = []
        entries.reserveCapacity(256)

        for record in output.split(separator: recordSeparator, omittingEmptySubsequences: true) {
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count >= 7 else {
                continue
            }

            let hash = String(fields[0]).trimmed()
            guard !hash.isEmpty else {
                continue
            }

            let shortHash = String(fields[1]).trimmed()
            let authorName = String(fields[2]).trimmed()
            let authorEmail = String(fields[3]).trimmed()
            let timestampSeconds = TimeInterval(String(fields[4]).trimmed()) ?? 0
            let subject = String(fields[5]).trimmed()
            let decorations = String(fields[6]).trimmed()
            let parentHashes: [String]
            if fields.count >= 8 {
                parentHashes = String(fields[7])
                    .split(separator: " ")
                    .map { String($0).trimmed() }
                    .filter { !$0.isEmpty }
            } else {
                parentHashes = []
            }

            entries.append(
                GitLogEntry(
                    id: hash,
                    shortHash: shortHash.isEmpty ? String(hash.prefix(7)) : shortHash,
                    authorName: authorName.isEmpty ? "Unknown Author" : authorName,
                    authorEmail: authorEmail,
                    timestamp: Date(timeIntervalSince1970: timestampSeconds),
                    subject: subject.isEmpty ? "(no commit message)" : subject,
                    decorations: decorations,
                    parentHashes: parentHashes
                )
            )
        }

        return entries
    }

    nonisolated private static func detectPrimaryBaseBranch(
        in repositoryURL: URL,
        excludingAliases: Set<String>
    ) throws -> String? {
        let refsRaw = try runGit(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"],
            in: repositoryURL
        )

        let refs = Set(
            refsRaw
                .split(separator: "\n")
                .map { String($0).trimmed() }
                .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
        )

        guard !refs.isEmpty else {
            return nil
        }

        var candidates: [String] = []

        if let remoteHead = try? runGit(
            ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
            in: repositoryURL
        ).trimmed(),
           !remoteHead.isEmpty {
            candidates.append(remoteHead)
            if remoteHead.hasPrefix("origin/") {
                candidates.append(String(remoteHead.dropFirst("origin/".count)))
            }
        }

        candidates.append(contentsOf: [
            "main",
            "origin/main",
            "master",
            "origin/master",
            "trunk",
            "origin/trunk",
            "develop",
            "origin/develop",
            "dev",
            "origin/dev"
        ])

        for candidate in candidates where refs.contains(candidate) {
            let aliases = canonicalBranchAliases(for: candidate)
            if excludingAliases.isDisjoint(with: aliases) {
                return candidate
            }
        }

        return nil
    }

    nonisolated private static func canonicalBranchAliases(for ref: String) -> Set<String> {
        let value = ref.trimmed()
        guard !value.isEmpty else {
            return []
        }

        var aliases: Set<String> = [value]
        if value.hasPrefix("origin/") {
            aliases.insert(String(value.dropFirst("origin/".count)))
        } else if !value.contains("/") {
            aliases.insert("origin/\(value)")
        }
        return aliases
    }

    nonisolated private static func isPrimaryBranchRef(_ ref: String) -> Bool {
        let aliases = canonicalBranchAliases(for: ref)
        let primaryRefs: Set<String> = [
            "main",
            "origin/main",
            "master",
            "origin/master",
            "trunk",
            "origin/trunk",
            "develop",
            "origin/develop",
            "dev",
            "origin/dev"
        ]
        return !aliases.isDisjoint(with: primaryRefs)
    }

    nonisolated private static func runBranchUniqueLog(
        repositoryURL: URL,
        selectedBranch: String,
        baseArgs: [String]
    ) throws -> String {
        let selectedAliases = canonicalBranchAliases(for: selectedBranch)
        let refsRaw = try runGit(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"],
            in: repositoryURL
        )

        var otherRefs: [String] = []
        var seen = Set<String>()
        for ref in refsRaw
            .split(separator: "\n")
            .map({ String($0).trimmed() })
            .filter({ !$0.isEmpty && !$0.hasSuffix("/HEAD") })
        {
            let aliases = canonicalBranchAliases(for: ref)
            if !selectedAliases.isDisjoint(with: aliases) {
                continue
            }
            if seen.insert(ref).inserted {
                otherRefs.append(ref)
            }
        }

        guard !otherRefs.isEmpty else {
            return ""
        }

        return try runGit(baseArgs + [selectedBranch, "--not"] + otherRefs, in: repositoryURL)
    }
}

private extension String {
    nonisolated func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
