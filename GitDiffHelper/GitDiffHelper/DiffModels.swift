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

struct RepoLibraryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var selectedPath: String
    var rootPath: String
    var displayName: String
    var lastBranch: String
    var lastOpenedAt: Date
    var bookmarkData: Data?
    var sessions: [RepoSessionEntry]

    init(
        id: UUID = UUID(),
        selectedPath: String,
        rootPath: String,
        displayName: String,
        lastBranch: String,
        lastOpenedAt: Date = Date(),
        bookmarkData: Data? = nil,
        sessions: [RepoSessionEntry] = []
    ) {
        self.id = id
        self.selectedPath = selectedPath
        self.rootPath = rootPath
        self.displayName = displayName
        self.lastBranch = lastBranch
        self.lastOpenedAt = lastOpenedAt
        self.bookmarkData = bookmarkData
        self.sessions = sessions
    }
}

struct RepoSessionEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var timestamp: Date
    var baseRef: String
    var headRef: String
    var pathFilter: String
    var fileCount: Int
    var hunkCount: Int
    var bridgeCount: Int

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        baseRef: String,
        headRef: String,
        pathFilter: String,
        fileCount: Int,
        hunkCount: Int,
        bridgeCount: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.baseRef = baseRef
        self.headRef = headRef
        self.pathFilter = pathFilter
        self.fileCount = fileCount
        self.hunkCount = hunkCount
        self.bridgeCount = bridgeCount
    }

    var compareLabel: String {
        if baseRef.isEmpty && headRef.isEmpty {
            return "Uncommitted"
        }
        if !baseRef.isEmpty && !headRef.isEmpty {
            return "\(baseRef) -> \(headRef)"
        }
        if !baseRef.isEmpty {
            return baseRef
        }
        return headRef
    }
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
