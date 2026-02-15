import Foundation

enum GitService {
    static func repoContext(repoPath: String) throws -> RepoContext {
        let repositoryURL = try resolveRepositoryURL(repoPath)
        try ensureGitRepository(repositoryURL)
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repositoryURL).trimmed()
        let root = try runGit(["rev-parse", "--show-toplevel"], in: repositoryURL).trimmed()
        return RepoContext(branch: branch, rootPath: root)
    }

    static func diff(
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
        }

        if !path.isEmpty {
            try validatePathFilter(path)
            args.append(contentsOf: ["--", path])
        }

        return try runGit(args, in: repositoryURL)
    }

    private static func ensureGitRepository(_ directory: URL) throws {
        do {
            let result = try runGit(["rev-parse", "--is-inside-work-tree"], in: directory).trimmed()
            guard result == "true" else {
                throw BridgeDiffError.notGitRepository(directory.path)
            }
        } catch {
            throw BridgeDiffError.notGitRepository(directory.path)
        }
    }

    private static func validateGitRef(_ value: String, name: String) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@~^:-")
        let isValid = value.unicodeScalars.allSatisfy { allowed.contains($0) }
        if !isValid {
            throw BridgeDiffError.invalidRef(name)
        }
    }

    private static func validatePathFilter(_ value: String) throws {
        if value.contains("\0") {
            throw BridgeDiffError.invalidPathFilter
        }
    }

    private static func resolveRepositoryURL(_ pathValue: String) throws -> URL {
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

    private static func runGit(_ args: [String], in directory: URL) throws -> String {
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
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
