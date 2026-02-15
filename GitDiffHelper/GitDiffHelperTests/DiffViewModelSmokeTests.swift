import Foundation
import XCTest
@testable import GitDiffHelper

final class DiffViewModelSmokeTests: XCTestCase {
    @MainActor
    func testInitialStateIsSane() {
        let model = DiffViewModel()
        XCTAssertEqual(model.repoPath, "")
        XCTAssertTrue(model.files.isEmpty)
        XCTAssertEqual(model.statusLine, "Step 1: Choose a repository folder.")
        XCTAssertFalse(model.hasError)
    }

    @MainActor
    func testChooseRepositoryHandlesNonGitFolder() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeDiff-NonGit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let model = DiffViewModel()
        await model.chooseRepository(path: tempURL.path)

        XCTAssertTrue(model.hasError)
        XCTAssertTrue(model.files.isEmpty)
    }

    @MainActor
    func testChooseRepositoryLoadsWorkingDiffFromGitRepo() async throws {
        try XCTSkipUnless(isGitAvailable, "git is required for this smoke test")

        let repoURL = try makeTemporaryGitRepositoryWithChange()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let model = DiffViewModel()
        await model.chooseRepository(path: repoURL.path)

        XCTAssertFalse(model.hasError)
        XCTAssertFalse(model.files.isEmpty)
        XCTAssertFalse(model.statusLine.isEmpty)
    }

    func testCommitLogBranchFilterShowsBranchSpecificCommits() throws {
        try XCTSkipUnless(isGitAvailable, "git is required for this smoke test")

        let repoURL = try makeTemporaryGitRepositoryWithFeatureBranch()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let featureEntries = try GitService.commitLog(
            repoPath: repoURL.path,
            branchRef: "feature/demo",
            maxCount: 100
        )

        XCTAssertEqual(featureEntries.count, 2)
        XCTAssertEqual(featureEntries.map(\.subject), ["Feature step 2", "Feature step 1"])

        let allEntries = try GitService.commitLog(
            repoPath: repoURL.path,
            branchRef: nil,
            maxCount: 100
        )
        XCTAssertGreaterThanOrEqual(allEntries.count, 3)
    }

    func testCommitLogBranchFilterWorksWithoutPrimaryBranchName() throws {
        try XCTSkipUnless(isGitAvailable, "git is required for this smoke test")

        let repoURL = try makeTemporaryGitRepositoryWithoutPrimaryBranchName()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let entries = try GitService.commitLog(
            repoPath: repoURL.path,
            branchRef: "feature/a1-map",
            maxCount: 100
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.subject), ["A1 step 2", "A1 step 1"])
    }

    func testWorkingDiffIncludesStagedAndUnstagedChanges() throws {
        try XCTSkipUnless(isGitAvailable, "git is required for this smoke test")

        let repoURL = try makeTemporaryGitRepositoryWithStagedAndUnstagedChanges()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let diff = try GitService.diff(
            repoPath: repoURL.path,
            baseRef: "",
            headRef: "",
            pathFilter: ""
        )

        XCTAssertTrue(diff.contains("diff --git a/Staged.swift b/Staged.swift"))
        XCTAssertTrue(diff.contains("diff --git a/Unstaged.swift b/Unstaged.swift"))
    }

    private var isGitAvailable: Bool {
        (try? runGit(["--version"], in: nil)) != nil
    }

    private func makeTemporaryGitRepositoryWithChange() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeDiff-GitSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        _ = try runGit(["init"], in: repoURL)

        let fileURL = repoURL.appendingPathComponent("Demo.swift")
        try "let value = 1\nprint(value)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        _ = try runGit(["add", "Demo.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "Initial commit"
        ], in: repoURL)

        try "let value = 2\nprint(value)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        return repoURL
    }

    private func makeTemporaryGitRepositoryWithFeatureBranch() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeDiff-GitLog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        _ = try runGit(["init"], in: repoURL)

        let defaultBranch = try runGit(["symbolic-ref", "--short", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fileURL = repoURL.appendingPathComponent("Demo.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Demo.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "Initial commit"
        ], in: repoURL)

        _ = try runGit(["checkout", "-b", "feature/demo"], in: repoURL)

        try "let value = 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Demo.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "Feature step 1"
        ], in: repoURL)

        try "let value = 3\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Demo.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "Feature step 2"
        ], in: repoURL)

        _ = try runGit(["checkout", defaultBranch], in: repoURL)

        return repoURL
    }

    private func makeTemporaryGitRepositoryWithoutPrimaryBranchName() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeDiff-GitLog-FeatureBase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        _ = try runGit(["init"], in: repoURL)
        _ = try runGit(["checkout", "-b", "feature/saving"], in: repoURL)

        let fileURL = repoURL.appendingPathComponent("Demo.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Demo.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "Base commit"
        ], in: repoURL)

        _ = try runGit(["checkout", "-b", "feature/a1-map"], in: repoURL)

        try "let value = 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Demo.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "A1 step 1"
        ], in: repoURL)

        try "let value = 3\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Demo.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "A1 step 2"
        ], in: repoURL)

        _ = try runGit(["checkout", "feature/saving"], in: repoURL)
        try "let value = 4\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Demo.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "Saving step"
        ], in: repoURL)

        return repoURL
    }

    private func makeTemporaryGitRepositoryWithStagedAndUnstagedChanges() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeDiff-GitWorking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        _ = try runGit(["init"], in: repoURL)

        let stagedFileURL = repoURL.appendingPathComponent("Staged.swift")
        let unstagedFileURL = repoURL.appendingPathComponent("Unstaged.swift")
        try "let staged = 1\n".write(to: stagedFileURL, atomically: true, encoding: .utf8)
        try "let unstaged = 1\n".write(to: unstagedFileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Staged.swift", "Unstaged.swift"], in: repoURL)
        _ = try runGit([
            "-c", "user.name=BridgeDiff",
            "-c", "user.email=tests@bridgediff.local",
            "commit", "-m", "Initial commit"
        ], in: repoURL)

        try "let staged = 2\n".write(to: stagedFileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Staged.swift"], in: repoURL)

        try "let unstaged = 2\n".write(to: unstagedFileURL, atomically: true, encoding: .utf8)

        return repoURL
    }

    @discardableResult
    private func runGit(_ args: [String], in directory: URL?) throws -> String {
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
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "DiffViewModelSmokeTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
        return output
    }
}
