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
    @AppStorage("BridgeDiff.MenuBarCommitComposerCollapsed") private var isCommitComposerCollapsed = false
    @State private var hoveredChangeID: String?
    @State private var commitMessageDraft = ""
    @State private var isCommitEditorFocused = false
    @State private var showsPushStep = false
    @State private var availableRemotes: [String] = []
    @State private var selectedRemote = ""
    @State private var currentBranchName = ""
    @State private var detectedUpstreamRemote = ""
    @State private var isLoadingPushTargets = false
    @State private var isPushing = false
    @State private var pushTargetsError: String?

    private var repoDisplayName: String {
        let path = model.repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return "No repository selected"
        }
        return URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
    }

    private var showsCommitComposer: Bool {
        !model.repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.workingTreeChanges.isEmpty
    }

    private var canProceedToPushStep: Bool {
        !commitMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pushTargetPreview: String {
        let remote = selectedRemote.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = currentBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote.isEmpty || branch.isEmpty {
            return "Push target incomplete"
        }
        return "\(remote)/\(branch)"
    }

    private var canCommitAndPush: Bool {
        canProceedToPushStep &&
        !selectedRemote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !currentBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isLoadingPushTargets &&
        !isPushing
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

            if showsCommitComposer {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(showsPushStep ? "Push Target" : "Commit Message")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if showsPushStep && isLoadingPushTargets {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer(minLength: 0)

                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isCommitComposerCollapsed.toggle()
                            }
                        } label: {
                            Image(systemName: isCommitComposerCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .separatorColor).opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(isCommitComposerCollapsed ? "Show commit message editor" : "Hide commit message editor")
                    }

                    if !isCommitComposerCollapsed {
                        Group {
                            if showsPushStep {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(spacing: 16) {
                                        Picker("Remote", selection: $selectedRemote) {
                                            if availableRemotes.isEmpty {
                                                Text("No remotes").tag("")
                                            } else {
                                                ForEach(availableRemotes, id: \.self) { remote in
                                                    Text(remote).tag(remote)
                                                }
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 132)
                                        .disabled(availableRemotes.isEmpty)

                                        Text(currentBranchName.isEmpty ? "No current branch" : currentBranchName)
                                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
                                            )
                                    }
                                    .padding(.horizontal, 8)

                                    Text("Target: \(pushTargetPreview)")
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .padding(.horizontal, 8)

                                    if let pushTargetsError {
                                        Text(pushTargetsError)
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }

                                    HStack(spacing: 8) {
                                        Button("Back") {
                                            withAnimation(.easeInOut(duration: 0.16)) {
                                                showsPushStep = false
                                            }
                                        }
                                        .buttonStyle(.bordered)

                                        Spacer(minLength: 0)

                                        Button {
                                            Task {
                                                await commitAndPush()
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                if isPushing {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                }
                                                Text(isPushing ? "Pushing..." : "Commit & Push")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(!canCommitAndPush)
                                    }
                                    .padding(.top, 10)
                                    .padding(.horizontal, 8)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 112, alignment: .topLeading)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.22))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack(alignment: .topLeading) {
                                        if commitMessageDraft.isEmpty {
                                            Text("Type your commit message...")
                                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 9)
                                                .allowsHitTesting(false)
                                        }

                                        CommitMessageTextView(
                                            text: $commitMessageDraft,
                                            isFocused: $isCommitEditorFocused
                                        )
                                    }
                                    .frame(height: 104)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.22))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(
                                                isCommitEditorFocused
                                                ? Color.accentColor.opacity(0.85)
                                                : Color(nsColor: .separatorColor).opacity(0.55),
                                                lineWidth: isCommitEditorFocused ? 1.4 : 1
                                            )
                                    }

                                    HStack(spacing: 8) {
                                        Spacer(minLength: 0)
                                        Button("OK") {
                                            withAnimation(.easeInOut(duration: 0.16)) {
                                                showsPushStep = true
                                            }
                                            Task {
                                                await refreshPushTargets()
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(!canProceedToPushStep)
                                    }
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                Divider()
            }

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
                .frame(maxHeight: 260)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Open BridgeDiff") {
                    openMainWindow()
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .frame(width: 392)
        .padding(10)
        .task {
            await model.refreshWorkingTreeChanges()
        }
        .onChange(of: showsCommitComposer) { _, isVisible in
            if !isVisible {
                isCommitEditorFocused = false
                showsPushStep = false
                pushTargetsError = nil
                isPushing = false
            }
        }
        .onChange(of: isCommitComposerCollapsed) { _, isCollapsed in
            if isCollapsed {
                isCommitEditorFocused = false
            }
        }
        .onChange(of: model.repoPath) { _, _ in
            if showsPushStep {
                Task {
                    await refreshPushTargets()
                }
            }
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

    @MainActor
    private func refreshPushTargets() async {
        let repoPath = model.repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoPath.isEmpty else {
            availableRemotes = []
            selectedRemote = ""
            currentBranchName = ""
            detectedUpstreamRemote = ""
            pushTargetsError = nil
            return
        }

        isLoadingPushTargets = true
        defer { isLoadingPushTargets = false }
        pushTargetsError = nil

        do {
            async let remotesTask = Task.detached {
                try GitService.remotes(repoPath: repoPath)
            }.value
            async let branchTask = Task.detached {
                try GitService.currentBranch(repoPath: repoPath)
            }.value
            async let upstreamTask = Task.detached {
                GitService.upstreamForCurrentBranch(repoPath: repoPath)
            }.value

            let remotes = try await remotesTask
            let branch = (try? await branchTask) ?? ""
            let upstream = await upstreamTask

            availableRemotes = remotes
            currentBranchName = branch == "HEAD" ? "" : branch

            let (upstreamRemote, _) = parseUpstream(upstream)
            detectedUpstreamRemote = upstreamRemote ?? ""

            if selectedRemote.isEmpty || !availableRemotes.contains(selectedRemote) {
                if let upstreamRemote, availableRemotes.contains(upstreamRemote) {
                    selectedRemote = upstreamRemote
                } else {
                    selectedRemote = availableRemotes.first ?? ""
                }
            }
            if currentBranchName.isEmpty {
                pushTargetsError = "No local branch checked out. Switch to a branch before pushing."
            }
        } catch {
            availableRemotes = []
            selectedRemote = ""
            currentBranchName = ""
            detectedUpstreamRemote = ""
            pushTargetsError = "Unable to read remotes for this repository."
        }
    }

    @MainActor
    private func commitAndPush() async {
        let repoPath = model.repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = commitMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = selectedRemote.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = currentBranchName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !repoPath.isEmpty, !message.isEmpty, !remote.isEmpty, !branch.isEmpty else {
            pushTargetsError = "Commit message, remote, and current branch are required."
            return
        }

        isPushing = true
        pushTargetsError = nil
        defer { isPushing = false }

        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try GitService.commitAndPush(
                    repoPath: repoPath,
                    message: message,
                    remote: remote
                )
            }.value
            commitMessageDraft = ""
            showsPushStep = false
            await model.refreshWorkingTreeChanges()
        } catch {
            pushTargetsError = error.localizedDescription
        }
    }

    private func parseUpstream(_ upstream: String?) -> (String?, String?) {
        guard let upstream, !upstream.isEmpty else {
            return (nil, nil)
        }
        let parts = upstream.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return (nil, nil)
        }
        return (parts[0], parts[1])
    }
}

private struct CommitMessageTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }
    }
}
