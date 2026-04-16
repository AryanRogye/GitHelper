import AppKit
import SwiftUI

// Main workbench shell that coordinates sidebar state and the currently selected screen.
struct ContentView: View {
    @EnvironmentObject private var model: DiffViewModel
    @Namespace private var glassNamespace
    @State private var showAdvancedInspector = false
    @State private var selectedTwoCommitBaseID: String?
    @State private var librarySearchText = ""
    @State private var showRecentComparisons = false
    @State private var visibleFileCount = 0
    @State private var focusedHunkID: UUID?
    @State private var selectedScreen: WorkbenchScreen = .diff
    @AppStorage("BridgeDiff.diffTextScale") private var storedDiffTextScale = 1.0
    @AppStorage("BridgeDiff.treeScale") private var storedTreeScale = 1.0

    private static let fileRenderBatchSize = 24

    // MARK: - Derived State

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

    private var activeStatusLine: String {
        selectedScreen == .diff ? model.statusLine : model.logStatusLine
    }

    private var activeHasError: Bool {
        selectedScreen == .diff ? model.hasError : model.logHasError
    }

    private var selectedTwoCommitBase: GitLogEntry? {
        guard let selectedTwoCommitBaseID else {
            return nil
        }
        return model.recentBranchCommits.first(where: { $0.id == selectedTwoCommitBaseID })
    }

    private var selectedTwoCommitHeads: [GitLogEntry] {
        guard let selectedTwoCommitBase else {
            return []
        }
        return model.recentBranchCommits.filter { $0.id != selectedTwoCommitBase.id }
    }

    private var diffTextScale: CGFloat {
        DiffTypography.clamp(CGFloat(storedDiffTextScale))
    }

    private var treeTypography: CommitTreeTypography {
        CommitTreeTypography(scale: CGFloat(storedTreeScale))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainContent
        }
        .task {
            await model.initialLoadIfNeeded()
            resetVisibleFiles(totalFiles: model.files.count)
            switch selectedScreen {
            case .diff:
                await model.loadRecentBranchCommits()
            case .log, .tree:
                await ensureCommitLogLoaded()
            }
        }
        .onReceive(model.$files) { files in
            focusedHunkID = nil
            resetVisibleFiles(totalFiles: files.count)
            guard selectedScreen == .diff else {
                return
            }
            Task {
                await model.loadRecentBranchCommits()
            }
        }
        .onChange(of: selectedScreen) { _, nextScreen in
            if nextScreen == .diff {
                Task {
                    await model.loadRecentBranchCommits()
                }
            } else {
                Task {
                    await ensureCommitLogLoaded()
                }
            }
        }
        .onChange(of: model.recentBranchCommits) { _, commits in
            guard let selectedTwoCommitBaseID else {
                return
            }
            if !commits.contains(where: { $0.id == selectedTwoCommitBaseID }) {
                self.selectedTwoCommitBaseID = nil
            }
        }
        .onChange(of: model.repoPath) { _, _ in
            selectedTwoCommitBaseID = nil
        }
        .onChange(of: model.currentBranchRef) { _, _ in
            selectedTwoCommitBaseID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .diffZoomIn)) { _ in
            switch selectedScreen {
            case .diff:
                updateDiffTextScale(by: DiffTypography.scaleStep)
            case .tree:
                updateTreeScale(by: CommitTreeTypography.scaleStep)
            case .log:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .diffZoomOut)) { _ in
            switch selectedScreen {
            case .diff:
                updateDiffTextScale(by: -DiffTypography.scaleStep)
            case .tree:
                updateTreeScale(by: -CommitTreeTypography.scaleStep)
            case .log:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .diffZoomReset)) { _ in
            switch selectedScreen {
            case .diff:
                storedDiffTextScale = Double(DiffTypography.defaultScale)
            case .tree:
                storedTreeScale = Double(CommitTreeTypography.defaultScale)
            case .log:
                break
            }
        }
    }
    
    private var mainContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                topGlassPanel
                switch selectedScreen {
                case .diff:
                    DiffArea(
                        selectedScreen: $selectedScreen,
                        visibleFileCount: $visibleFileCount,
                        focusedHunkID: $focusedHunkID
                    )
                case .log:
                    commitLogArea
                case .tree:
                    commitTreeArea
                }
            }
            
            if selectedScreen == .diff, showAdvancedInspector {
                AdvancedCompareInspector(model: model) {
                    showAdvancedInspector = false
                }
                .frame(width: 360)
            }
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.18), value: showAdvancedInspector)
        .navigationTitle("BridgeDiff")
        .toolbar {
            GitDiffToolbar(
                showAdvancedInspector: $showAdvancedInspector,
                selectedScreen: $selectedScreen,
                selectedTwoCommitBaseID: $selectedTwoCommitBaseID,
                onChooseRepositoryFolder: {
                    chooseRepositoryFolder()
                }
            )
        }
    }
    
    // MARK: - Sidebar
    private var sidebar: some View {
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
                    SidebarSearchField(text: $librarySearchText)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
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
    }

    // MARK: - Screen Regions

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
                        value: activeStatusLine,
                        id: "status-chip",
                        namespace: glassNamespace,
                        isError: activeHasError
                    )
                }
            }
        }
        .padding(.top, 8)
        .glassCard()
    }

    @ViewBuilder
    private var commitLogArea: some View {
        if model.repoPath.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No repository selected")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Choose a repository, then open Commit Log.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
        } else if model.isLoadingLog && model.logEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView("Loading commit history...")
                    .controlSize(.regular)
                Text("Reading commits from Git.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
            .task {
                await ensureCommitLogLoaded()
            }
        } else if model.logEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No commits found")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(model.logStatusLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await model.loadCommitLog(branchFilter: model.selectedLogBranchFilter)
                    }
                } label: {
                    Label("Reload Commit Log", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
            .task {
                await ensureCommitLogLoaded()
            }
        } else {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.logEntries) { entry in
                            CommitLogRow(entry: entry)
                        }
                    }
                    .padding(8)
                }

                if model.isLoadingLog {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            }
            .glassCard()
            .task {
                await ensureCommitLogLoaded()
            }
        }
    }

    @ViewBuilder
    private var commitTreeArea: some View {
        if model.repoPath.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No repository selected")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Choose a repository, then open Commit Tree.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
        } else if model.isLoadingLog && model.logEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView("Building commit tree...")
                    .controlSize(.regular)
                Text("Reading commit ancestry and branch paths from Git.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
            .task {
                await ensureCommitLogLoaded()
            }
        } else if model.logEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No commits found")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(model.logStatusLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await model.loadCommitLog(branchFilter: model.selectedLogBranchFilter)
                    }
                } label: {
                    Label("Reload Commit Tree", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
            .task {
                await ensureCommitLogLoaded()
            }
        } else {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        CommitTreeLegendCard()
                        CommitTreeGraphList(entries: model.logEntries, typography: treeTypography)
                    }
                    .padding(8)
                }

                if model.isLoadingLog {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            }
            .glassCard()
            .task {
                await ensureCommitLogLoaded()
            }
        }
    }

    // MARK: - User Actions

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

    private func ensureCommitLogLoaded() async {
        guard !model.repoPath.isEmpty, !model.isLoadingLog else {
            return
        }
        if model.logEntries.isEmpty || model.logHasError {
            await model.loadCommitLog(branchFilter: model.selectedLogBranchFilter)
        }
    }

    // MARK: - Formatting Helpers

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

    // MARK: - Incremental Diff Rendering
    private func resetVisibleFiles(totalFiles: Int) {
        visibleFileCount = min(totalFiles, Self.fileRenderBatchSize)
    }

    private func updateDiffTextScale(by delta: CGFloat) {
        let nextScale = DiffTypography.clamp(diffTextScale + delta)
        storedDiffTextScale = Double(nextScale)
    }

    private func updateTreeScale(by delta: CGFloat) {
        let currentScale = CGFloat(storedTreeScale)
        let nextScale = CommitTreeTypography.clamp(currentScale + delta)
        storedTreeScale = Double(nextScale)
    }
}

enum WorkbenchScreen: Hashable {
    case diff
    case log
    case tree
}

struct LibraryStatus {
    let title: String
    let color: Color
    let symbol: String
}

#Preview {
    ContentView()
        .frame(width: 700, height: 500)
        .environmentObject(DiffViewModel())
}
