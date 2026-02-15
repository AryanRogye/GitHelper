import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DiffViewModel
    @Namespace private var glassNamespace
    @State private var showAdvancedSheet = false
    @State private var librarySearchText = ""
    @State private var showRecentComparisons = false
    @State private var visibleFileCount = 0
    @State private var focusedHunkID: UUID?

    private static let fileRenderBatchSize = 24

    private var selectedLibraryEntry: RepoLibraryEntry? {
        guard let selectedID = model.selectedLibraryRepoID else {
            return nil
        }
        return model.library.first(where: { $0.id == selectedID })
    }

    private var displayedSessions: [RepoSessionEntry] {
        guard let entry = selectedLibraryEntry else {
            return []
        }
        return Array(entry.sessions.prefix(14))
    }

    private var filteredLibrary: [RepoLibraryEntry] {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return model.library
        }
        return model.library.filter { entry in
            entry.displayName.localizedCaseInsensitiveContains(query) ||
            entry.lastBranch.localizedCaseInsensitiveContains(query) ||
            entry.selectedPath.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            ZStack {
                LinearGradient(
                    colors: [
                        NativeTheme.sidebarTop,
                        NativeTheme.sidebarBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                List {
                    Section {
                        HStack(spacing: 12) {
                            SidebarIconButton(
                                systemImage: "folder.badge.plus",
                                helpText: "Pick a folder that contains your .git repository."
                            ) {
                                chooseRepositoryFolder()
                            }

                            SidebarIconButton(
                                systemImage: "scope",
                                helpText: "Use the folder where BridgeDiff is currently running."
                            ) {
                                Task {
                                    await model.chooseRepository(path: FileManager.default.currentDirectoryPath)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        SidebarSearchField(text: $librarySearchText)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        if filteredLibrary.isEmpty {
                            Text(model.library.isEmpty ? "No repositories saved yet." : "No repositories match your search.")
                                .foregroundStyle(NativeTheme.readableSecondary)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(filteredLibrary) { entry in
                                let status = libraryStatus(for: entry)
                                Button {
                                    Task {
                                        await model.loadLibraryRepository(id: entry.id)
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: status.symbol)
                                            .font(.system(size: 12, weight: .semibold))
                                            .frame(width: 16, alignment: .leading)
                                            .foregroundStyle(status.color)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(entry.displayName)
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundStyle(NativeTheme.fileListPrimary)
                                            HStack(spacing: 6) {
                                                Text(status.title)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(status.color)
                                                Text("• \(friendlyRefName(entry.lastBranch)) • \(entry.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))")
                                                    .font(.system(size: 11, weight: .regular))
                                                    .foregroundStyle(NativeTheme.readableSecondary)
                                            }
                                            .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .sidebarSelectableRow(isSelected: model.selectedLibraryRepoID == entry.id)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        model.removeLibraryRepository(id: entry.id)
                                    } label: {
                                        Label("Remove from Library", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        SidebarSectionHeader("Repository Library")
                    }

                    if let selectedEntry = selectedLibraryEntry {
                        Section {
                            DisclosureGroup(isExpanded: $showRecentComparisons) {
                                if displayedSessions.isEmpty {
                                    Text("No sessions yet for this repository.")
                                        .foregroundStyle(NativeTheme.readableSecondary)
                                        .padding(.top, 8)
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(displayedSessions) { session in
                                            Button {
                                                Task {
                                                    await model.loadLibrarySession(repoID: selectedEntry.id, sessionID: session.id)
                                                }
                                            } label: {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text(friendlyCompareLabel(session.compareLabel))
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundStyle(NativeTheme.fileListPrimary)
                                                    Text("\(session.fileCount) files • \(session.hunkCount) hunks • \(session.bridgeCount) bridges")
                                                        .font(.system(size: 11, weight: .regular))
                                                        .foregroundStyle(NativeTheme.readableSecondary)
                                                    Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                                                        .font(.system(size: 10, weight: .regular))
                                                        .foregroundStyle(NativeTheme.readableSecondary)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .sidebarSelectableRow(isSelected: model.selectedLibrarySessionID == session.id)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(NativeTheme.readableSecondary)
                                    Text("Recent Comparisons")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(NativeTheme.readableSecondary)
                                }
                            }
                            .tint(NativeTheme.readableSecondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [
                        NativeTheme.windowTop,
                        NativeTheme.windowBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    topGlassPanel
                    diffArea
                }
                .padding(16)
            }
            .navigationTitle("BridgeDiff")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        chooseRepositoryFolder()
                    } label: {
                        ToolbarSymbolLabel("Choose Repository", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.accentColor)
                    .help("Pick a folder that contains your .git repository")
                    .accessibilityLabel("Choose Repository")
                    .accessibilityHint("Opens a folder picker so you can select the Git repository to inspect.")
                }

                ToolbarItem(placement: .automatic) {
                    Button("Use Current Folder", systemImage: "folder") {
                        Task {
                            await model.chooseRepository(path: FileManager.default.currentDirectoryPath)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.accentColor)
                    .help("Use the folder where BridgeDiff is currently running.")
                    .accessibilityLabel("Use Current Folder")
                    .accessibilityHint("Loads the current working folder as the repository.")
                }

                ToolbarItemGroup(placement: .automatic) {
                    ControlGroup {
                        Button {
                            Task {
                                await model.loadUncommittedChanges()
                            }
                        } label: {
                            ToolbarSymbolLabel("Working Changes", systemImage: "square.and.pencil")
                        }
                        .help("Show files changed in your working folder that are not committed yet.")
                        .accessibilityLabel("Show Working Changes")
                        .accessibilityHint("Loads differences between the files you are editing and your latest saved commit.")

                        Button {
                            Task {
                                await model.loadLastCommit()
                            }
                        } label: {
                            ToolbarSymbolLabel("Recent Commit", systemImage: "clock")
                        }
                        .help("Compare the latest commit with the one right before it.")
                        .accessibilityLabel("Compare Recent Commit")
                        .accessibilityHint("Shows what changed in the most recently created commit.")

                        Menu {
                            if model.availableBranchRefs.filter({ $0 != "HEAD" }).isEmpty {
                                Text("No branches found")
                            } else {
                                ForEach(model.availableBranchRefs.filter { $0 != "HEAD" }, id: \.self) { branch in
                                    Button(branch) {
                                        Task {
                                            await model.compareAgainstBranch(branch)
                                        }
                                    }
                                }
                            }
                        } label: {
                            ToolbarSymbolLabel("Compare Branch", systemImage: "arrow.triangle.branch")
                        }
                        .help("Compare your current work with another branch.")
                        .accessibilityLabel("Compare to Branch")
                        .accessibilityHint("Opens a menu of branches so you can compare against one.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.accentColor)
                    .disabled(model.repoPath.isEmpty)

                    Button {
                        showAdvancedSheet = true
                    } label: {
                        ToolbarSymbolLabel("Custom Compare", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.accentColor)
                    .disabled(model.repoPath.isEmpty)
                    .help("Open advanced options for custom comparisons and path filters.")
                    .accessibilityLabel("Advanced Compare")
                    .accessibilityHint("Opens options to compare specific commits or branches and filter to a file or folder path.")
                }
            }
            .sheet(isPresented: $showAdvancedSheet) {
                AdvancedCompareSheet(model: model)
            }
        }
        .task {
            await model.initialLoadIfNeeded()
            resetVisibleFiles(totalFiles: model.files.count)
        }
        .onReceive(model.$files) { files in
            focusedHunkID = nil
            resetVisibleFiles(totalFiles: files.count)
        }
    }

    private var topGlassPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.repoPath.isEmpty ? "No repository selected" : model.repoPath)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(NativeTheme.topPathText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NativeTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    StatusChip(
                        title: "Repository",
                        value: model.repoSummary,
                        id: "repo-chip",
                        namespace: glassNamespace
                    )
                    StatusChip(
                        title: "Status",
                        value: model.statusLine,
                        id: "status-chip",
                        namespace: glassNamespace,
                        isError: model.hasError
                    )
                }
            }
        }
        .padding(.top, 8)
        .glassCard()
    }

    @ViewBuilder
    private var diffArea: some View {
        if model.isLoadingDiff && model.files.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView("Loading diff...")
                    .controlSize(.regular)
                Text("Parsing changes. Large diffs can take a moment.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
        } else if model.files.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No diff loaded")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Click Choose Repository, then Working Changes.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
        } else {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                        ForEach(visibleFiles) { file in
                            Section {
                                DiffFileCard(file: file, focusedHunkID: $focusedHunkID)
                            } header: {
                                DiffFileStickyHeader(
                                    file: file,
                                    isActive: file.id == activeFileID
                                )
                            }
                        }

                        if visibleFileCount < model.files.count {
                            ProgressView("Loading more files...")
                                .controlSize(.small)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    loadMoreFilesIfNeeded(totalFiles: model.files.count)
                                }
                        }
                    }
                }

                if model.isLoadingDiff {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            }
            .glassCard()
        }
    }

    private func chooseRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose Repository"
        panel.message = "Select the root folder of your Git repository."
        if !model.repoPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: model.repoPath, isDirectory: true)
        }

        if panel.runModal() == .OK, let selectedURL = panel.url {
            Task {
                await model.chooseRepository(url: selectedURL)
            }
        }
    }

    private func friendlyRefName(_ ref: String) -> String {
        switch ref {
        case "HEAD":
            return "Current Commit"
        case "HEAD~1":
            return "Previous Commit"
        default:
            return ref
        }
    }

    private func friendlyCompareLabel(_ label: String) -> String {
        if label == "Uncommitted" {
            return "Working Changes"
        }

        return label
            .replacingOccurrences(of: "HEAD~1", with: "Previous Commit")
            .replacingOccurrences(of: "HEAD", with: "Current Commit")
            .replacingOccurrences(of: "->", with: "→")
    }

    private func libraryStatus(for entry: RepoLibraryEntry) -> LibraryStatus {
        guard let latestSession = entry.sessions.first else {
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

    private var visibleFiles: ArraySlice<DiffFile> {
        let maxVisible = min(visibleFileCount, model.files.count)
        return model.files.prefix(maxVisible)
    }

    private var activeFileID: UUID? {
        if let focusedHunkID,
           let focusedFile = model.files.first(where: { file in
               file.hunks.contains(where: { $0.id == focusedHunkID })
           }) {
            return focusedFile.id
        }
        return visibleFiles.first?.id
    }

    private func resetVisibleFiles(totalFiles: Int) {
        visibleFileCount = min(totalFiles, Self.fileRenderBatchSize)
    }

    private func loadMoreFilesIfNeeded(totalFiles: Int) {
        guard visibleFileCount < totalFiles else {
            return
        }
        visibleFileCount = min(totalFiles, visibleFileCount + Self.fileRenderBatchSize)
    }
}

private struct LibraryStatus {
    let title: String
    let color: Color
    let symbol: String
}

private struct AdvancedCompareSheet: View {
    @ObservedObject var model: DiffViewModel
    @Environment(\.dismiss) private var dismiss

    private var selectableRefs: [String] {
        model.availableBranchRefs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Advanced Compare")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("Use any branch/ref combination or filter to one path.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                RefInputField(
                    label: "Base ref",
                    placeholder: "HEAD~1",
                    text: $model.baseRef,
                    refs: selectableRefs
                )
                RefInputField(
                    label: "Head ref",
                    placeholder: "HEAD",
                    text: $model.headRef,
                    refs: selectableRefs
                )
                LabeledField(label: "Path filter", placeholder: "src/ or README.md", text: $model.pathFilter)
            }
            .padding(12)
            .background(NativeTheme.field)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                Button("Run Compare") {
                    Task {
                        await model.loadDiff()
                        dismiss()
                    }
                }
                .buttonStyle(.glassProminent)

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.glass)
            }
        }
        .padding(20)
        .frame(minWidth: 470)
    }
}

private struct ToolbarSymbolLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 16, height: 16, alignment: .center)
        }
        .labelStyle(.titleAndIcon)
    }
}

private struct SidebarIconButton: View {
    let systemImage: String
    let helpText: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(NativeTheme.fileListPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHovered ? NativeTheme.sidebarIconHover : NativeTheme.sidebarIconBase)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            NativeTheme.sidebarIconBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
    }
}

private struct SidebarSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(NativeTheme.readableSecondary)
                .frame(width: 14, height: 14)

            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NativeTheme.sidebarSearchBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NativeTheme.sidebarSearchBorder, lineWidth: 1)
        )
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(NativeTheme.readableSecondary)
            .textCase(nil)
    }
}

private struct RefInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let refs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))

                Menu {
                    Button("Clear") {
                        text = ""
                    }
                    if !refs.isEmpty {
                        Divider()
                        ForEach(refs, id: \.self) { ref in
                            Button(ref) {
                                text = ref
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .help("Pick from all detected branches and refs.")
            }
        }
    }
}

private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
        }
    }
}

private struct StatusChip: View {
    let title: String
    let value: String
    let id: String
    let namespace: Namespace.ID
    var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(NativeTheme.readableSecondary)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isError ? Color.red : Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .glassEffect(.regular.interactive(), in: Capsule())
        .glassEffectID(id, in: namespace)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiffFileCard: View {
    let file: DiffFile
    @Binding var focusedHunkID: UUID?
    @State private var visibleHunkCount = 0

    private static let hunkBatchSize = 12

    var body: some View {
        VStack(spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(0..<visibleHunkUpperBound, id: \.self) { index in
                    if index > 0 {
                        Divider()
                            .background(NativeTheme.border.opacity(0.8))
                    }
                    HunkView(
                        hunk: file.hunks[index],
                        focusedHunkID: $focusedHunkID
                    )
                }

                if visibleHunkUpperBound < file.hunks.count {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .onAppear {
                            loadMoreHunksIfNeeded()
                        }
                }
            }
        }
        .onAppear {
            if visibleHunkCount == 0 {
                visibleHunkCount = min(Self.hunkBatchSize, file.hunks.count)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(NativeTheme.fileCardBackground)
    }

    private var visibleHunkUpperBound: Int {
        min(visibleHunkCount, file.hunks.count)
    }

    private func loadMoreHunksIfNeeded() {
        guard visibleHunkCount < file.hunks.count else {
            return
        }
        visibleHunkCount = min(file.hunks.count, visibleHunkCount + Self.hunkBatchSize)
    }
}

private struct DiffFileStickyHeader: View {
    let file: DiffFile
    var isActive: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            FileTypeIcon(filePath: file.displayPath)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? Color.primary : NativeTheme.fileListPrimary)
                if shouldShowFullPath {
                    Text(abbreviatedPath)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(NativeTheme.readableSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text("\(file.hunks.count) hunk\(file.hunks.count == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(NativeTheme.readableSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.11) : Color(nsColor: .windowBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isActive ? Color.accentColor.opacity(0.42) : NativeTheme.border.opacity(0.82),
                    lineWidth: 1
                )
        )
        .padding(.top, 2)
    }

    private var fileName: String {
        guard !file.displayPath.isEmpty else {
            return "(unknown file)"
        }
        return URL(fileURLWithPath: file.displayPath).lastPathComponent
    }

    private var shouldShowFullPath: Bool {
        !file.displayPath.isEmpty && file.displayPath != fileName
    }

    private var abbreviatedPath: String {
        let components = file.displayPath
            .components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .filter { !$0.isEmpty }
        guard components.count > 3 else {
            return file.displayPath
        }
        return "…/" + components.suffix(3).joined(separator: "/")
    }
}

private struct FileTypeIcon: View {
    let filePath: String

    var body: some View {
        Image(nsImage: iconImage)
            .resizable()
            .interpolation(.medium)
            .frame(width: 14, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var iconImage: NSImage {
        let ext = URL(fileURLWithPath: filePath).pathExtension
        let resolvedType = ext.isEmpty ? "txt" : ext
        let icon = NSWorkspace.shared.icon(forFileType: resolvedType)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

private struct SidebarSelectableRowModifier: ViewModifier {
    let isSelected: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(backgroundFill)
            .overlay(selectionStroke)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var backgroundFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isSelected
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                    : (isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.10) : Color.clear)
            )
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                isSelected ? Color.accentColor.opacity(0.24) : Color.clear,
                lineWidth: 1
            )
    }
}

private extension View {
    func sidebarSelectableRow(isSelected: Bool) -> some View {
        modifier(SidebarSelectableRowModifier(isSelected: isSelected))
    }
}

private enum NativeTheme {
    static let windowTop = Color(nsColor: .windowBackgroundColor)
    static let windowBottom = Color(nsColor: .underPageBackgroundColor)
    static let sidebarTop = Color(nsColor: .windowBackgroundColor)
    static let sidebarBottom = Color(nsColor: .underPageBackgroundColor).opacity(0.92)
    static let sidebarSearchBackground = Color(nsColor: .controlBackgroundColor).opacity(0.42)
    static let sidebarSearchBorder = Color(nsColor: .separatorColor).opacity(0.34)
    static let sidebarIconBase = Color(nsColor: .controlBackgroundColor).opacity(0.22)
    static let sidebarIconHover = Color(nsColor: .selectedContentBackgroundColor).opacity(0.2)
    static let sidebarIconBorder = Color(nsColor: .separatorColor).opacity(0.35)
    static let field = Color(nsColor: .textBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let topPathText = Color(nsColor: .labelColor).opacity(0.84)
    static let fileListPrimary = Color.primary.opacity(0.9)
    static let headerRow = Color(nsColor: .underPageBackgroundColor)
    static let fileCardBackground = Color(nsColor: .textBackgroundColor)
    static let contextBackground = Color(nsColor: .textBackgroundColor)
    static let lineNumber = Color(nsColor: .secondaryLabelColor)
    static let placeholderLineNumber = Color(nsColor: .secondaryLabelColor).opacity(0.48)
    static let lineNumberGutter = Color(nsColor: .underPageBackgroundColor).opacity(0.92)
    static let hunkHeaderText = Color(nsColor: .secondaryLabelColor)
    static let hunkHeaderBackground = Color(nsColor: .underPageBackgroundColor).opacity(0.7)
    static let readableSecondary = Color(nsColor: .secondaryLabelColor)
    static let metaText = Color(nsColor: .tertiaryLabelColor)
    static let metaBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.08)
    static let deleteBackground = Color(nsColor: .systemRed).opacity(0.075)
    static let deleteMarker = Color(nsColor: .systemRed).opacity(0.60)
    static let addBackground = Color(nsColor: .systemGreen).opacity(0.075)
    static let addMarker = Color(nsColor: .systemGreen).opacity(0.60)
    static let placeholderBackground = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let deletePlaceholderBackground = Color(nsColor: .systemRed).opacity(0.028)
    static let addPlaceholderBackground = Color(nsColor: .systemGreen).opacity(0.028)
    static let gutterDelete = Color(nsColor: .systemRed).opacity(0.045)
    static let gutterAdd = Color(nsColor: .systemGreen).opacity(0.045)
    static let gutterContext = Color(nsColor: .controlBackgroundColor).opacity(0.4)
    static let gutterAccent = Color.accentColor.opacity(0.2)
    static let centerGuide = Color.accentColor.opacity(0.2)
    static let sideGuides = Color(nsColor: .separatorColor).opacity(0.28)
    static let bridgeRibbon = Color.accentColor
}

private enum DiffGridStyle {
    static let rowHeight: CGFloat = 25
    static let numberGutterWidth: CGFloat = 56
    static let markerColumnWidth: CGFloat = 16
    static let gutterWidth: CGFloat = 64
    static let gridLine = NativeTheme.border
}

private enum DiffSide {
    case left
    case right
}

private struct HunkView: View {
    let hunk: DiffHunk
    @Binding var focusedHunkID: UUID?

    private static let rowChunkSize = 320
    private static let bridgeOverlayRowLimit = 1800
    private static let separatorRowLimit = 4000

    var body: some View {
        VStack(spacing: 0) {
            Text(hunk.header)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NativeTheme.hunkHeaderText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(NativeTheme.hunkHeaderBackground)

            LazyVStack(spacing: 0) {
                ForEach(rowChunks, id: \.lowerBound) { range in
                    HunkRowsChunkView(
                        rows: hunk.rows,
                        rowRange: range,
                        showsSeparators: shouldDrawRowSeparators
                    )
                }
            }
            .background(NativeTheme.fileCardBackground)
            .overlay {
                if shouldRenderBridgeOverlay {
                    BridgeOverlay(
                        bridges: hunk.bridges,
                        rowHeight: DiffGridStyle.rowHeight,
                        gutterWidth: DiffGridStyle.gutterWidth,
                        opacityScale: bridgeOpacityScale,
                        highlighted: isFocused
                    )
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isFocused ? Color.accentColor.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focusedHunkID = hunk.id
        }
    }

    private var rowChunks: [Range<Int>] {
        guard !hunk.rows.isEmpty else {
            return []
        }

        var chunks: [Range<Int>] = []
        chunks.reserveCapacity((hunk.rows.count / Self.rowChunkSize) + 1)

        var lowerBound = 0
        while lowerBound < hunk.rows.count {
            let upperBound = min(lowerBound + Self.rowChunkSize, hunk.rows.count)
            chunks.append(lowerBound..<upperBound)
            lowerBound = upperBound
        }
        return chunks
    }

    private var shouldRenderBridgeOverlay: Bool {
        !hunk.bridges.isEmpty && hunk.rows.count <= Self.bridgeOverlayRowLimit
    }

    private var shouldDrawRowSeparators: Bool {
        hunk.rows.count <= Self.separatorRowLimit
    }

    private var isFocused: Bool {
        focusedHunkID == hunk.id
    }

    private var bridgeOpacityScale: CGFloat {
        guard let focusedHunkID else {
            return 0.9
        }
        return focusedHunkID == hunk.id ? 1.15 : 0.16
    }
}

private struct HunkRowsChunkView: View {
    let rows: [DiffRow]
    let rowRange: Range<Int>
    let showsSeparators: Bool

    var body: some View {
        ForEach(rowRange, id: \.self) { rowIndex in
            DiffLineRow(row: rows[rowIndex])
                .frame(height: DiffGridStyle.rowHeight)
                .overlay(alignment: .top) {
                    if showsSeparators && rowIndex > 0 {
                        Rectangle()
                            .fill(DiffGridStyle.gridLine.opacity(0.62))
                            .frame(height: 1)
                    }
                }
        }
    }
}

private struct DiffLineRow: View {
    let row: DiffRow

    var body: some View {
        if row.kind == .meta {
            HStack(spacing: 0) {
                Text(verbatim: row.text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(NativeTheme.metaText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
            }
            .background(NativeTheme.metaBackground)
        } else {
            HStack(spacing: 0) {
                SideGridCell(side: .left, row: row)
                GutterGridCell(row: row, width: DiffGridStyle.gutterWidth)
                SideGridCell(side: .right, row: row)
            }
            .background(NativeTheme.fileCardBackground)
        }
    }
}

private struct SideGridCell: View {
    let side: DiffSide
    let row: DiffRow

    var body: some View {
        let cell = cellData(for: row, side: side)

        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                NativeTheme.lineNumberGutter
                Text(cell.lineNumber.map(String.init) ?? "")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(cell.placeholder ? NativeTheme.placeholderLineNumber : NativeTheme.lineNumber)
                    .padding(.trailing, 8)
            }
            .frame(width: DiffGridStyle.numberGutterWidth, alignment: .trailing)

            Rectangle()
                .fill(DiffGridStyle.gridLine.opacity(0.75))
                .frame(width: 1)

            Text(cell.marker)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(cell.markerColor)
                .frame(width: DiffGridStyle.markerColumnWidth, alignment: .center)

            Rectangle()
                .fill(DiffGridStyle.gridLine.opacity(0.75))
                .frame(width: 1)

            Text(verbatim: cell.text.isEmpty ? " " : cell.text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
        }
        .opacity(cell.placeholder ? 0.52 : 1.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cell.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DiffGridStyle.gridLine.opacity(0.82))
                .frame(width: 1)
        }
    }

    private func cellData(for row: DiffRow, side: DiffSide) -> (
        lineNumber: Int?,
        marker: String,
        text: String,
        background: Color,
        markerColor: Color,
        placeholder: Bool
    ) {
        switch row.kind {
        case .context:
            return (
                lineNumber: side == .left ? row.oldLineNumber : row.newLineNumber,
                marker: " ",
                text: row.text,
                background: NativeTheme.contextBackground,
                markerColor: .secondary,
                placeholder: false
            )
        case .delete:
            if side == .left {
                return (
                    lineNumber: row.oldLineNumber,
                    marker: "-",
                    text: row.text,
                    background: NativeTheme.deleteBackground,
                    markerColor: NativeTheme.deleteMarker,
                    placeholder: false
                )
            }
            return (
                lineNumber: row.oldLineNumber,
                marker: " ",
                text: " ",
                background: NativeTheme.deletePlaceholderBackground,
                markerColor: NativeTheme.placeholderLineNumber,
                placeholder: true
            )
        case .add:
            if side == .right {
                return (
                    lineNumber: row.newLineNumber,
                    marker: "+",
                    text: row.text,
                    background: NativeTheme.addBackground,
                    markerColor: NativeTheme.addMarker,
                    placeholder: false
                )
            }
            return (
                lineNumber: row.newLineNumber,
                marker: " ",
                text: " ",
                background: NativeTheme.addPlaceholderBackground,
                markerColor: NativeTheme.placeholderLineNumber,
                placeholder: true
            )
        case .meta:
            return (
                lineNumber: nil,
                marker: " ",
                text: row.text,
                background: NativeTheme.metaBackground,
                markerColor: .secondary,
                placeholder: false
            )
        }
    }
}

private struct GutterGridCell: View {
    let row: DiffRow
    let width: CGFloat

    var body: some View {
        ZStack {
            gutterBackground(for: row)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(DiffGridStyle.gridLine.opacity(0.82))
                    .frame(width: 1)
                Spacer(minLength: 0)
                Rectangle()
                    .fill(DiffGridStyle.gridLine.opacity(0.82))
                    .frame(width: 1)
            }

            Rectangle()
                .fill(NativeTheme.gutterAccent)
                .frame(width: 1)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }

    private func gutterBackground(for row: DiffRow) -> Color {
        switch row.kind {
        case .delete:
            return NativeTheme.gutterDelete
        case .add:
            return NativeTheme.gutterAdd
        case .context:
            return NativeTheme.gutterContext
        case .meta:
            return NativeTheme.metaBackground
        }
    }
}

private struct BridgeOverlay: View {
    let bridges: [BridgeGroup]
    let rowHeight: CGFloat
    let gutterWidth: CGFloat
    let opacityScale: CGFloat
    let highlighted: Bool

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard size.width > 320 else {
                    return
                }
                let guideOpacity = max(0.1, min(opacityScale * 0.85, 0.8))

                let centerX = size.width * 0.5
                let leftX = centerX - (gutterWidth * 0.38) + 7
                let rightX = centerX + (gutterWidth * 0.38) - 7

                var centerGuide = Path()
                centerGuide.move(to: CGPoint(x: centerX, y: 0))
                centerGuide.addLine(to: CGPoint(x: centerX, y: size.height))
                context.stroke(
                    centerGuide,
                    with: .color(NativeTheme.centerGuide.opacity(guideOpacity)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )

                var leftGuide = Path()
                leftGuide.move(to: CGPoint(x: leftX, y: 0))
                leftGuide.addLine(to: CGPoint(x: leftX, y: size.height))
                context.stroke(
                    leftGuide,
                    with: .color(NativeTheme.sideGuides.opacity(guideOpacity)),
                    style: StrokeStyle(lineWidth: 1)
                )

                var rightGuide = Path()
                rightGuide.move(to: CGPoint(x: rightX, y: 0))
                rightGuide.addLine(to: CGPoint(x: rightX, y: size.height))
                context.stroke(
                    rightGuide,
                    with: .color(NativeTheme.sideGuides.opacity(guideOpacity)),
                    style: StrokeStyle(lineWidth: 1)
                )

                for bridge in bridges {
                    guard
                        let deletedMin = bridge.deletedRows.min(),
                        let deletedMax = bridge.deletedRows.max(),
                        let addedMin = bridge.addedRows.min(),
                        let addedMax = bridge.addedRows.max()
                    else {
                        continue
                    }

                    let sourceTop = CGFloat(deletedMin) * rowHeight
                    let sourceBottom = CGFloat(deletedMax + 1) * rowHeight
                    let targetTop = CGFloat(addedMin) * rowHeight
                    let targetBottom = CGFloat(addedMax + 1) * rowHeight
                    let sourceMid = (sourceTop + sourceBottom) * 0.5
                    let targetMid = (targetTop + targetBottom) * 0.5

                    let verticalDistance = abs(targetMid - sourceMid)
                    let xSpan = rightX - leftX
                    let controlSpread = max(6, min(14, xSpan * 0.28 - min(7, verticalDistance * 0.03)))

                    let topDelta = targetTop - sourceTop
                    let topControl1 = CGPoint(x: leftX + controlSpread, y: sourceTop + topDelta * 0.33)
                    let topControl2 = CGPoint(x: rightX - controlSpread, y: sourceTop + topDelta * 0.67)

                    let bottomDelta = targetBottom - sourceBottom
                    let bottomControl1 = CGPoint(x: rightX - controlSpread, y: targetBottom - bottomDelta * 0.33)
                    let bottomControl2 = CGPoint(x: leftX + controlSpread, y: targetBottom - bottomDelta * 0.67)

                    var ribbon = Path()
                    ribbon.move(to: CGPoint(x: leftX, y: sourceTop))
                    ribbon.addCurve(
                        to: CGPoint(x: rightX, y: targetTop),
                        control1: topControl1,
                        control2: topControl2
                    )
                    ribbon.addLine(to: CGPoint(x: rightX, y: targetBottom))
                    ribbon.addCurve(
                        to: CGPoint(x: leftX, y: sourceBottom),
                        control1: bottomControl1,
                        control2: bottomControl2
                    )
                    ribbon.closeSubpath()

                    let ribbonOpacity = (0.08 + min(CGFloat(bridge.weight) * 0.015, 0.055)) * opacityScale
                    context.fill(
                        ribbon,
                        with: .color(NativeTheme.bridgeRibbon.opacity(ribbonOpacity))
                    )

                    if highlighted {
                        context.stroke(
                            ribbon,
                            with: .color(NativeTheme.bridgeRibbon.opacity(min(ribbonOpacity * 0.36, 0.34))),
                            style: StrokeStyle(lineWidth: 0.9)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    func glassCard() -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
            )
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    ContentView()
        .environmentObject(DiffViewModel())
}
