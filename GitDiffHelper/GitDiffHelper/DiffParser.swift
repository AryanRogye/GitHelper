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


/// A state-driven parser that converts raw Unified Diff text into structured Swift objects.
private struct UnifiedDiffParser {
    // MARK: - Properties
    
    /// The final list of parsed files.
    var files: [DiffFile] = []
    
    /// Temporary storage for the file currently being processed.
    private var currentFile: DiffFile?
    
    /// The raw header string (e.g., "@@ -1,4 +1,4 @@") for the current hunk.
    private var currentHunkHeader: String?
    
    /// The collection of lines (rows) belonging to the current hunk.
    private var currentRows: [DiffRow] = []
    
    /// Trackers for line numbers to ensure each DiffRow has the correct position.
    private var oldLineNumber = 0
    private var newLineNumber = 0
    
    // MARK: - Main Parser Logic
    
    /// Processes a single line of the diff and updates the internal state.
    mutating func consume(line: Substring) {
        // 1. Detect a new file section (Git style header)
        if line.hasPrefix("diff --git ") {
            finalizeCurrentFile() // Save the previous file before starting a new one
            let displayPath = parseFilePath(fromDiffHeader: line)
            currentFile = DiffFile(
                displayPath: displayPath,
                oldPath: "",
                newPath: "",
                hunks: [],
                hidden: false,
                seen: false
            )
            return
        }
        
        // Safety: Ignore lines until we have a valid file context
        guard currentFile != nil else { return }
        
        // 2. Parse the "old file" path (---)
        if line.hasPrefix("--- ") {
            let oldPath = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            currentFile?.oldPath = oldPath
            // Fallback for displayPath if the 'diff --git' line didn't provide it
            if (currentFile?.displayPath.isEmpty ?? true) && oldPath != "/dev/null" {
                currentFile?.displayPath = oldPath.replacingOccurrences(of: "a/", with: "", options: [.anchored])
            }
            return
        }
        
        // 3. Parse the "new file" path (+++)
        if line.hasPrefix("+++ ") {
            let newPath = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            currentFile?.newPath = newPath
            // If newPath is /dev/null, it's a deletion; otherwise, it's the current name
            if newPath == "/dev/null" {
                let previousOldPath = currentFile?.oldPath ?? ""
                currentFile?.displayPath = previousOldPath.replacingOccurrences(of: "a/", with: "", options: [.anchored])
            } else {
                currentFile?.displayPath = newPath.replacingOccurrences(of: "b/", with: "", options: [.anchored])
            }
            return
        }
        
        // 4. Parse Hunk Range Headers (@@ -L,S +L,S @@)
        if line.hasPrefix("@@ ") {
            finalizeCurrentHunk() // Save previous hunk
            guard let (oldStart, newStart) = parseHunkHeader(line) else { return }
            
            // Set starting line numbers for this hunk
            oldLineNumber = oldStart
            newLineNumber = newStart
            currentHunkHeader = String(line)
            currentRows = []
            return
        }
        
        // 5. Parse Content Rows (inside a hunk)
        guard currentHunkHeader != nil, let marker = line.first else { return }
        
        let text = String(line.dropFirst())
        switch marker {
        case " ": // Context line: exists in both files
            currentRows.append(
                DiffRow(kind: .context, oldLineNumber: oldLineNumber, newLineNumber: newLineNumber, text: text)
            )
            oldLineNumber += 1
            newLineNumber += 1
        case "-": // Deletion: exists only in the old file
            currentRows.append(
                DiffRow(kind: .delete, oldLineNumber: oldLineNumber, newLineNumber: nil, text: text)
            )
            oldLineNumber += 1
        case "+": // Addition: exists only in the new file
            currentRows.append(
                DiffRow(kind: .add, oldLineNumber: nil, newLineNumber: newLineNumber, text: text)
            )
            newLineNumber += 1
        case "\\": // Meta info (e.g., "\ No newline at end of file")
            currentRows.append(
                DiffRow(kind: .meta, oldLineNumber: nil, newLineNumber: nil, text: String(line))
            )
        default:
            break
        }
    }
    
    /// Call this after the last line is consumed to ensure the final file is saved.
    mutating func finish() {
        finalizeCurrentFile()
    }
    
    // MARK: - State Finalization
    
    private mutating func finalizeCurrentHunk() {
        guard let header = currentHunkHeader else { return }
        
        let hunk = DiffHunk(
            header: header,
            rows: currentRows,
            // Group contiguous +/- lines for "side-by-side" or "bridge" UI logic
            bridges: buildBridgeGroups(rows: currentRows)
        )
        currentFile?.hunks.append(hunk)
        
        // Reset hunk state
        currentHunkHeader = nil
        currentRows = []
    }
    
    private mutating func finalizeCurrentFile() {
        finalizeCurrentHunk()
        guard let file = currentFile else { return }
        
        // Only append files that actually contain changes (hunks)
        if !file.hunks.isEmpty {
            files.append(file)
        }
        currentFile = nil
    }
    
    // MARK: - Helpers
    
    /// Extracts the file path from 'diff --git a/file.txt b/file.txt'
    private func parseFilePath(fromDiffHeader line: Substring) -> String {
        let components = line.split(separator: " ")
        guard components.count >= 4 else { return "" }
        let rhs = String(components[3]) // Take the 'b/' path
        return rhs.replacingOccurrences(of: "b/", with: "", options: [.anchored])
    }
    
    /// Extracts (Old Start, New Start) integers from the @@ header.
    private func parseHunkHeader(_ line: Substring) -> (Int, Int)? {
        let parts = line.split(separator: " ") // e.g., ["@@", "-1,4", "+1,4", "@@"]
        guard parts.count >= 3 else { return nil }
        
        guard
            let oldStart = parseLineStart(parts[1], expectedPrefix: "-"),
            let newStart = parseLineStart(parts[2], expectedPrefix: "+")
        else { return nil }
        
        return (oldStart, newStart)
    }
    
    /// Converts a range token like "-1,4" into the starting integer 1.
    private func parseLineStart(_ token: Substring, expectedPrefix: Character) -> Int? {
        guard token.first == expectedPrefix else { return nil }
        let numberToken = token.dropFirst().split(separator: ",").first
        guard let numberToken else { return nil }
        return Int(numberToken)
    }
    
    /// Identifies contiguous blocks of deletions and additions within a hunk.
    /// This is used to link a deleted line to its corresponding added line for UI highlighting.
    private func buildBridgeGroups(rows: [DiffRow]) -> [BridgeGroup] {
        var groups: [BridgeGroup] = []
        var index = 0
        
        while index < rows.count {
            let row = rows[index]
            // Skip context/meta lines as they don't form "bridges" between changes
            if row.kind == .context || row.kind == .meta {
                index += 1
                continue
            }
            
            var deletedRows: [Int] = []
            var addedRows: [Int] = []
            
            // Collect all contiguous changes until the next context line
            while index < rows.count {
                let current = rows[index]
                if current.kind == .context || current.kind == .meta { break }
                
                if current.kind == .delete { deletedRows.append(index) }
                if current.kind == .add { addedRows.append(index) }
                index += 1
            }
            
            // A "bridge" only exists if there is both a deletion and an addition in the same block
            if !deletedRows.isEmpty && !addedRows.isEmpty {
                groups.append(BridgeGroup(deletedRows: deletedRows, addedRows: addedRows))
            }
        }
        
        return groups
    }
}
