//
//  GitDiffHelperApp.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 2/14/26.
//

import SwiftUI
import AppKit

@main
struct GitDiffHelperApp: App {
    private static let mainWindowID = "mainWorkbench"
    @StateObject private var model = DiffViewModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup("BridgeDiff", id: Self.mainWindowID) {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            DiffZoomCommands()
        }

        MenuBarExtra {
            MenuBarControls(model: model, windowID: Self.mainWindowID)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.window)
    }
}

extension Notification.Name {
    static let diffZoomIn = Notification.Name("BridgeDiff.diffZoomIn")
    static let diffZoomOut = Notification.Name("BridgeDiff.diffZoomOut")
    static let diffZoomReset = Notification.Name("BridgeDiff.diffZoomReset")
}

private struct DiffZoomCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In (Diff/Tree)") {
                NotificationCenter.default.post(name: .diffZoomIn, object: nil)
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("Zoom Out (Diff/Tree)") {
                NotificationCenter.default.post(name: .diffZoomOut, object: nil)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Button("Reset Zoom (Diff/Tree)") {
                NotificationCenter.default.post(name: .diffZoomReset, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}

private struct MenuBarControls: View {
    @ObservedObject var model: DiffViewModel
    let windowID: String

    @Environment(\.openWindow) private var openWindow
    @State private var hoveredChangeID: String?
    @State private var commitMessageDraft = ""

    private var repoDisplayName: String {
        let path = model.repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return "No repository selected"
        }
        return URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BridgeDiff")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(repoDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            Text("Working Changes")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if model.repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Choose a repository in BridgeDiff.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.workingTreeChanges.isEmpty {
                Text("No modified files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.workingTreeChanges) { change in
                            Button {
                                openMainWindow()
                                Task {
                                    await model.openWorkingTreeChange(path: change.path)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(change.shortStatus)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(color(for: change.shortStatus))
                                        .frame(width: 22, alignment: .leading)
                                    Text(change.displayPath)
                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .background {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            hoveredChangeID == change.id
                                            ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
                                            : Color.clear
                                        )
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            hoveredChangeID == change.id
                                            ? Color(nsColor: .separatorColor).opacity(0.55)
                                            : Color.clear,
                                            lineWidth: 1
                                        )
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                                .animation(.easeOut(duration: 0.12), value: hoveredChangeID == change.id)
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                if isHovering {
                                    hoveredChangeID = change.id
                                } else if hoveredChangeID == change.id {
                                    hoveredChangeID = nil
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Commit Message")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    if commitMessageDraft.isEmpty {
                        Text("Type your commit message...")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $commitMessageDraft)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                }
                .frame(height: 96)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.28))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button("Open BridgeDiff") {
                    openMainWindow()
                }
                Spacer(minLength: 0)
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(width: 360)
        .padding(10)
        .task {
            await model.refreshWorkingTreeChanges()
        }
    }

    private func openMainWindow() {
        openWindow(id: windowID)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func color(for status: String) -> Color {
        switch status {
        case "A", "??":
            return .green
        case "M":
            return .orange
        case "D":
            return .red
        case "R", "C":
            return .blue
        case "U":
            return .pink
        default:
            return .secondary
        }
    }
}
