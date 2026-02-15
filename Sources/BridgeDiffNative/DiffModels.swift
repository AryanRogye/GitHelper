import Foundation

enum DiffRowKind {
    case context
    case add
    case delete
    case meta
}

struct DiffRow: Identifiable {
    let id = UUID()
    let kind: DiffRowKind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

struct BridgeGroup: Identifiable {
    let id = UUID()
    let deletedRows: [Int]
    let addedRows: [Int]

    var weight: Int {
        max(deletedRows.count, addedRows.count)
    }
}

struct DiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let rows: [DiffRow]
    let bridges: [BridgeGroup]
}

struct DiffFile: Identifiable {
    let id = UUID()
    var displayPath: String
    var oldPath: String
    var newPath: String
    var hunks: [DiffHunk]
}

struct RepoContext {
    let branch: String
    let rootPath: String
}

enum BridgeDiffError: LocalizedError {
    case invalidRef(String)
    case invalidPathFilter
    case repositoryNotFound(String)
    case repositoryNotDirectory(String)
    case notGitRepository(String)
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRef(let name):
            return "Invalid \(name) ref."
        case .invalidPathFilter:
            return "Invalid path filter."
        case .repositoryNotFound(let path):
            return "Repository path not found: \(path)"
        case .repositoryNotDirectory(let path):
            return "Repository path is not a directory: \(path)"
        case .notGitRepository(let path):
            return "The selected folder is not a Git repository: \(path)"
        case .gitCommandFailed(let message):
            return message
        }
    }
}

extension Array {
    var middleElement: Element? {
        guard !isEmpty else {
            return nil
        }
        return self[count / 2]
    }
}
