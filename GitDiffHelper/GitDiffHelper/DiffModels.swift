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
    var hidden: Bool
    var seen: Bool
    
    var fileName: String {
        guard !displayPath.isEmpty else {
            return "(unknown file)"
        }
        return URL(fileURLWithPath: displayPath).lastPathComponent
    }
    
    
    /**
     * Determines whether the full file path should be displayed.
     * This avoids redundant UI when the file is already at the root level.
     */
    var shouldShowFullPath: Bool {
        !displayPath.isEmpty && displayPath != fileName
    }

    var abbreviatedPath: String {
        let components = displayPath
            .components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .filter { !$0.isEmpty }
        guard components.count > 3 else {
            return displayPath
        }
        return "…/" + components.suffix(3).joined(separator: "/")
    }
}

struct WorkingTreeChange: Identifiable, Hashable {
    let statusCode: String
    let path: String
    let originalPath: String?

    var id: String {
        "\(statusCode)|\(originalPath ?? "")|\(path)"
    }

    var shortStatus: String {
        let first = statusCode.first ?? " "
        let second = statusCode.dropFirst().first ?? " "
        let primary = first != " " ? first : second
        if primary == "?" {
            return "??"
        }
        if primary == "!" {
            return "!!"
        }
        return String(primary)
    }

    var displayPath: String {
        guard let originalPath, !originalPath.isEmpty else {
            return path
        }
        return "\(originalPath) -> \(path)"
    }
}

struct GitLogEntry: Identifiable, Hashable {
    let id: String
    let shortHash: String
    let authorName: String
    let authorEmail: String
    let timestamp: Date
    let subject: String
    let decorations: String
    let parentHashes: [String]
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
    
    public var friendlyRefName: String {
        switch lastBranch {
        case "HEAD":
            return "Current Commit"
        case "HEAD~1":
            return "Previous Commit"
        default:
            return lastBranch
        }
    }

    
    /**
     * Figures out which icon and label to show based on how much work is saved:
     * - "No History": Nothing has been done yet.
     * - "Working": Changes are being made but not yet saved.
     * - "Commit": A single save point (one step back).
     * - "Branch": A jump between different versions or sets of changes.
     * - "Custom": Any other unique version state.
     */
    public var status: LibraryStatus {
        guard let latestSession = sessions.first else {
            return .init(title: "No History", color: NativeTheme.readableSecondary, symbol: "clock.badge.questionmark")
        }
        
        if latestSession.baseRef.isEmpty && latestSession.headRef.isEmpty {
            return .init(title: "Working", color: NativeTheme.readableSecondary, symbol: "square.and.pencil")
        }
        if latestSession.baseRef == "HEAD~1" && latestSession.headRef == "HEAD" {
            return .init(title: "Commit", color: NativeTheme.readableSecondary, symbol: "clock")
        }
        if latestSession.headRef == "HEAD", latestSession.baseRef != "HEAD~1", !latestSession.baseRef.isEmpty {
            return .init(title: "Branch", color: NativeTheme.readableSecondary, symbol: "arrow.triangle.branch")
        }
        return .init(title: "Custom", color: NativeTheme.readableSecondary, symbol: "slider.horizontal.3")
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
    
    var friendlyCompareLabel: String {
        if compareLabel == "Uncommitted" {
            return "Working Changes"
        }
        
        return compareLabel
            .replacingOccurrences(of: "HEAD~1", with: "Previous Commit")
            .replacingOccurrences(of: "HEAD", with: "Current Commit")
            .replacingOccurrences(of: "->", with: "→")
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
