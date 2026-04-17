import AppKit
import SwiftUI

/*
 Commit log rendering map:

 ContentView.commitLogArea
 +-- CommitLogRow (for each GitLogEntry)
     +-- CommitAuthorAvatarView
*/

/// One visual row in the commit log list.
/// Used in `ContentView.commitLogArea` for every `GitLogEntry`.
struct CommitLogRow: View {
    let entry: GitLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.shortHash)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NativeTheme.readableSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(NativeTheme.metaBackground)
                    )

                Text(entry.subject)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(NativeTheme.fileListPrimary)

                Spacer(minLength: 8)

                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(NativeTheme.readableSecondary)
            }

            HStack(spacing: 8) {
                CommitAuthorAvatarView(authorName: entry.authorName, authorEmail: entry.authorEmail)
                Text(entry.authorName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(NativeTheme.fileListPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !entry.decorations.isEmpty {
                    Spacer(minLength: 6)
                    Text(entry.decorations)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NativeTheme.readableSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(NativeTheme.border.opacity(0.7), lineWidth: 1)
        )
    }
}

/// Small circular author avatar used in commit log + commit tree rows.
/// Images are resolved through `CommitAuthorAvatarStore`.
struct CommitAuthorAvatarView: View {
    let authorName: String
    let authorEmail: String
    @State private var avatarImage: NSImage?

    private var imageIdentity: String {
        let trimmedEmail = authorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmedEmail.isEmpty {
            return trimmedEmail
        }
        return authorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        Group {
            if let avatarImage {
                Image(nsImage: avatarImage)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NativeTheme.readableSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NativeTheme.metaBackground)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
        )
        .task(id: imageIdentity) {
            avatarImage = await CommitAuthorAvatarStore.shared.image(
                authorName: authorName,
                authorEmail: authorEmail
            )
        }
        .accessibilityHidden(true)
    }
}
