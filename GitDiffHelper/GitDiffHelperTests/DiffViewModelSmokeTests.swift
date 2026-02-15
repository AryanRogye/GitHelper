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
