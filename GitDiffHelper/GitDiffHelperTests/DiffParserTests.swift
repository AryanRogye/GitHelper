import XCTest
@testable import GitDiffHelper

final class DiffParserTests: XCTestCase {
    func testParseEmptyDiffReturnsNoFiles() {
        XCTAssertTrue(DiffParser.parse("").isEmpty)
    }

    func testParseSimpleModificationBuildsBridgeGroup() throws {
        let diff = """
diff --git a/foo.swift b/foo.swift
index 1111111..2222222 100644
--- a/foo.swift
+++ b/foo.swift
@@ -1,3 +1,3 @@
 let a = 1
-let value = oldName
+let value = newName
 print(value)
"""

        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)

        let file = try XCTUnwrap(files.first)
        let hunk = try XCTUnwrap(file.hunks.first)
        XCTAssertEqual(file.displayPath, "foo.swift")
        XCTAssertFalse(hunk.bridges.isEmpty)
    }
}
