import AppKit
import CryptoKit
import Foundation

@MainActor
final class CommitAuthorAvatarStore {
    static let shared = CommitAuthorAvatarStore()

    private let memoryCache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let cacheDirectory: URL

    private init() {
        memoryCache.countLimit = 800
        memoryCache.totalCostLimit = 24 * 1024 * 1024

        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = baseDirectory
            .appendingPathComponent("BridgeDiff", isDirectory: true)
            .appendingPathComponent("CommitAuthorAvatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheDirectory = directory
    }

    func image(authorName: String, authorEmail: String) async -> NSImage? {
        let key = cacheKey(authorName: authorName, authorEmail: authorEmail)
        if key.isEmpty {
            return nil
        }

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let diskImage = loadDiskImage(for: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        if let task = inFlight[key] {
            return await task.value
        }

        guard let avatarURL = avatarURL(authorName: authorName, authorEmail: authorEmail) else {
            return nil
        }

        let task = Task<NSImage?, Never> {
            var request = URLRequest(url: avatarURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
            request.setValue("BridgeDiff/1.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    return nil
                }
                return NSImage(data: data)
            } catch {
                return nil
            }
        }

        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            memoryCache.setObject(image, forKey: key as NSString)
            persistDiskImage(image, for: key)
        }

        return image
    }

    private func cacheKey(authorName: String, authorEmail: String) -> String {
        let normalizedEmail = authorEmail.trimmedLowercased
        if !normalizedEmail.isEmpty {
            return normalizedEmail
        }
        return authorName.trimmedLowercased
    }

    private func avatarURL(authorName: String, authorEmail: String) -> URL? {
        let normalizedEmail = authorEmail.trimmedLowercased
        if let username = githubUsername(from: normalizedEmail) {
            let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
            return URL(string: "https://github.com/\(encoded).png?size=64")
        }

        guard !normalizedEmail.isEmpty else {
            return nil
        }
        let emailDigest = Insecure.MD5.hash(data: Data(normalizedEmail.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return URL(string: "https://www.gravatar.com/avatar/\(emailDigest)?s=64&d=identicon")
    }

    private func githubUsername(from normalizedEmail: String) -> String? {
        guard normalizedEmail.hasSuffix("@users.noreply.github.com"),
              let atIndex = normalizedEmail.firstIndex(of: "@")
        else {
            return nil
        }

        let localPart = String(normalizedEmail[..<atIndex])
        guard !localPart.isEmpty else {
            return nil
        }

        let username = localPart.split(separator: "+").last.map(String.init) ?? localPart
        let matches = username.range(of: #"^[A-Za-z0-9-]{1,39}$"#, options: .regularExpression) != nil
        return matches ? username.lowercased() : nil
    }

    private func loadDiskImage(for key: String) -> NSImage? {
        let fileURL = fileURL(for: key)
        return NSImage(contentsOf: fileURL)
    }

    private func persistDiskImage(_ image: NSImage, for key: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return
        }

        try? pngData.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent(digest).appendingPathExtension("png")
    }
}

private extension String {
    var trimmedLowercased: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
