import Foundation

enum DiffParser {
    static func parse(_ text: String) -> [DiffFile] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var parser = UnifiedDiffParser()
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            parser.consume(line: line)
        }
        parser.finish()
        return parser.files
    }
}

private struct UnifiedDiffParser {
    var files: [DiffFile] = []
    private var currentFile: DiffFile?
    private var currentHunkHeader: String?
    private var currentRows: [DiffRow] = []
    private var oldLineNumber = 0
    private var newLineNumber = 0

    mutating func consume(line: Substring) {
        if line.hasPrefix("diff --git ") {
            finalizeCurrentFile()
            let displayPath = parseFilePath(fromDiffHeader: line)
            currentFile = DiffFile(displayPath: displayPath, oldPath: "", newPath: "", hunks: [])
            return
        }

        guard currentFile != nil else {
            return
        }

        if line.hasPrefix("--- ") {
            let oldPath = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            currentFile?.oldPath = oldPath
            if (currentFile?.displayPath.isEmpty ?? true) && oldPath != "/dev/null" {
                currentFile?.displayPath = oldPath.replacingOccurrences(of: "a/", with: "", options: [.anchored])
            }
            return
        }

        if line.hasPrefix("+++ ") {
            let newPath = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            currentFile?.newPath = newPath
            if newPath == "/dev/null" {
                let previousOldPath = currentFile?.oldPath ?? ""
                currentFile?.displayPath = previousOldPath.replacingOccurrences(of: "a/", with: "", options: [.anchored])
            } else {
                currentFile?.displayPath = newPath.replacingOccurrences(of: "b/", with: "", options: [.anchored])
            }
            return
        }

        if line.hasPrefix("@@ ") {
            finalizeCurrentHunk()
            guard let (oldStart, newStart) = parseHunkHeader(line) else {
                return
            }
            oldLineNumber = oldStart
            newLineNumber = newStart
            currentHunkHeader = String(line)
            currentRows = []
            return
        }

        guard currentHunkHeader != nil else {
            return
        }

        guard let marker = line.first else {
            return
        }

        let text = String(line.dropFirst())
        switch marker {
        case " ":
            currentRows.append(
                DiffRow(kind: .context, oldLineNumber: oldLineNumber, newLineNumber: newLineNumber, text: text)
            )
            oldLineNumber += 1
            newLineNumber += 1
        case "-":
            currentRows.append(
                DiffRow(kind: .delete, oldLineNumber: oldLineNumber, newLineNumber: nil, text: text)
            )
            oldLineNumber += 1
        case "+":
            currentRows.append(
                DiffRow(kind: .add, oldLineNumber: nil, newLineNumber: newLineNumber, text: text)
            )
            newLineNumber += 1
        case "\\":
            currentRows.append(
                DiffRow(kind: .meta, oldLineNumber: nil, newLineNumber: nil, text: String(line))
            )
        default:
            break
        }
    }

    mutating func finish() {
        finalizeCurrentFile()
    }

    private mutating func finalizeCurrentHunk() {
        guard let header = currentHunkHeader else {
            return
        }
        let hunk = DiffHunk(header: header, rows: currentRows, bridges: buildBridgeGroups(rows: currentRows))
        currentFile?.hunks.append(hunk)
        currentHunkHeader = nil
        currentRows = []
    }

    private mutating func finalizeCurrentFile() {
        finalizeCurrentHunk()
        guard let file = currentFile else {
            return
        }
        if !file.hunks.isEmpty {
            files.append(file)
        }
        currentFile = nil
    }

    private func parseFilePath(fromDiffHeader line: Substring) -> String {
        let components = line.split(separator: " ")
        guard components.count >= 4 else {
            return ""
        }
        let rhs = String(components[3])
        return rhs.replacingOccurrences(of: "b/", with: "", options: [.anchored])
    }

    private func parseHunkHeader(_ line: Substring) -> (Int, Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else {
            return nil
        }

        guard
            let oldStart = parseLineStart(parts[1], expectedPrefix: "-"),
            let newStart = parseLineStart(parts[2], expectedPrefix: "+")
        else {
            return nil
        }

        return (oldStart, newStart)
    }

    private func parseLineStart(_ token: Substring, expectedPrefix: Character) -> Int? {
        guard token.first == expectedPrefix else {
            return nil
        }
        let numberToken = token.dropFirst().split(separator: ",").first
        guard let numberToken else {
            return nil
        }
        return Int(numberToken)
    }

    private func buildBridgeGroups(rows: [DiffRow]) -> [BridgeGroup] {
        var groups: [BridgeGroup] = []
        var index = 0

        while index < rows.count {
            let row = rows[index]
            if row.kind == .context || row.kind == .meta {
                index += 1
                continue
            }

            var deletedRows: [Int] = []
            var addedRows: [Int] = []

            while index < rows.count {
                let current = rows[index]
                if current.kind == .context || current.kind == .meta {
                    break
                }
                if current.kind == .delete {
                    deletedRows.append(index)
                }
                if current.kind == .add {
                    addedRows.append(index)
                }
                index += 1
            }

            if !deletedRows.isEmpty && !addedRows.isEmpty {
                groups.append(BridgeGroup(deletedRows: deletedRows, addedRows: addedRows))
            }
        }

        return groups
    }
}
