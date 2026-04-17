//
//  DiffFileStickyHeader.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 4/16/26.
//

import SwiftUI

/**
 * Sticky section header for each file in the diff list.
 * Shows filename/path + active highlight state.
 */
struct DiffFileStickyHeader: View {
    let file: DiffFile
    var isActive: Bool = false
    var onToggleSeen: (Bool) -> Void
    var onToggleHidden: (Bool) -> Void
    
    var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }
    
    var fillColor: Color {
        isActive ? Color.accentColor.opacity(0.11) : Color(nsColor: .windowBackgroundColor).opacity(0.45)
    }
    
    var strokeColor: Color {
        (isActive
         ? Color.accentColor.opacity(0.42)
         : (file.seen
            ? NativeTheme.seenBorder.opacity(0.82)
            : NativeTheme.border.opacity(0.82)
           )
        )
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            FileTypeIcon(filePath: file.displayPath)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                filenameView
                if file.shouldShowFullPath {
                    filePathView
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                HStack {
                    hunkCountView
                    toggleHiddenButton
                }
                toggleSeenButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            backgroundShape
                .fill(fillColor)
        )
        .overlay(
            backgroundShape
                .stroke(
                    strokeColor,
                    lineWidth: 1
                )
        )
        .padding(.top, 2)
    }
    
    // MARK: - File Name
    private var filenameView: some View {
        Text(file.fileName)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(isActive ? Color.primary : NativeTheme.fileListPrimary)
    }
    
    // MARK: - File Path View
    private var filePathView: some View {
        Text(file.abbreviatedPath)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(NativeTheme.readableSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    
    // MARK: - Hunk Count View
    private var hunkCountView: some View {
        Text("\(file.hunks.count) hunk\(file.hunks.count == 1 ? "" : "s")")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(NativeTheme.readableSecondary)
    }
    
    private var toggleHiddenButton: some View {
        Button {
            onToggleHidden(!file.hidden)
        } label: {
            if !file.hidden {
                Image(systemName: "eye")
            } else {
                Image(systemName: "eye.slash")
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Toggle Seen Button
    private var toggleSeenButton: some View {
        Button {
            onToggleSeen(!file.seen)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: file.seen ? "checkmark.circle.fill" : "circle")
                Text(file.seen ? "Seen" : "Mark Seen")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(file.seen ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(
                        file.seen
                        ? NativeTheme.seenBorder.opacity(0.9)
                        : NativeTheme.border.opacity(0.8),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
