import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    private var logBranchMenuOptions: [String] {
        var refs = [DiffViewModel.allBranchesFilterLabel]
        refs.append(contentsOf: model.availableBranchRefs)
        var seen = Set<String>()
        return refs.filter { seen.insert($0).inserted }
    }

    private var logBranchFilterLabel: String {
        let selected = model.selectedLogBranchFilter
        if selected == DiffViewModel.allBranchesFilterLabel {
            return selected
        }
        return friendlyRefName(selected)
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

    private var diffTypography: DiffTypography {
        DiffTypography(scale: diffTextScale)
    }

    private var treeTypography: CommitTreeTypography {
        CommitTreeTypography(scale: CGFloat(storedTreeScale))
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

                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        topGlassPanel
                        switch selectedScreen {
                        case .diff:
                            diffArea
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
            }
            .navigationTitle("BridgeDiff")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Picker("Screen", selection: $selectedScreen) {
                        Label("Diff", systemImage: "rectangle.split.2x1").tag(WorkbenchScreen.diff)
                        Label("Commit Log", systemImage: "clock.arrow.circlepath").tag(WorkbenchScreen.log)
                        Label("Commit Tree", systemImage: "arrow.triangle.branch").tag(WorkbenchScreen.tree)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                    .help("Switch between diff view, commit history, and commit tree.")
                }

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

                if selectedScreen == .diff {
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

                            Menu {
                                compareCommitMenuContent
                            } label: {
                                ToolbarSymbolLabel("Compare Commit", systemImage: "clock.badge.checkmark")
                            }
                            .help("Compare a past commit on the current branch against your current working state.")
                            .accessibilityLabel("Compare to Past Commit")
                            .accessibilityHint("Choose a commit from the current branch and compare it to what you have now.")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Color.accentColor)
                        .disabled(model.repoPath.isEmpty)

                        Button {
                            showAdvancedInspector.toggle()
                        } label: {
                            ToolbarSymbolLabel("Custom Compare", systemImage: showAdvancedInspector ? "sidebar.trailing" : "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Color.accentColor)
                        .disabled(model.repoPath.isEmpty)
                        .help("Open advanced options for custom comparisons and path filters.")
                        .accessibilityLabel("Advanced Compare")
                        .accessibilityHint("Opens options to compare specific commits or branches and filter to a file or folder path.")
                    }
                } else {
                    ToolbarItemGroup(placement: .automatic) {
                        Menu {
                            ForEach(logBranchMenuOptions, id: \.self) { ref in
                                Button(friendlyRefName(ref)) {
                                    Task {
                                        await model.loadCommitLog(branchFilter: ref)
                                    }
                                }
                            }
                        } label: {
                            ToolbarSymbolLabel(logBranchFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Color.accentColor)
                        .disabled(model.repoPath.isEmpty || model.isLoadingLog)
                        .help("Filter commit history and tree to one branch or show all branches.")
                        .accessibilityLabel("Commit Log Branch Filter")
                        .accessibilityHint("Select which branch history is visible in commit history screens.")

                        Button {
                            Task {
                                await model.loadCommitLog(branchFilter: model.selectedLogBranchFilter)
                            }
                        } label: {
                            ToolbarSymbolLabel("Refresh Log", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Color.accentColor)
                        .disabled(model.repoPath.isEmpty || model.isLoadingLog)
                        .help("Reload commit history and tree from Git.")
                        .accessibilityLabel("Refresh Commit History")
                        .accessibilityHint("Refreshes commit history screens from Git with the current branch filter.")
                    }
                }
            }
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
    private var diffArea: some View {
        if model.isLoadingDiff && model.files.isEmpty {
//            VStack(alignment: .leading, spacing: 12) {
//                ProgressView("Loading diff...")
//                    .controlSize(.regular)
//                Text("Parsing changes. Large diffs can take a moment.")
//                    .font(.system(size: 13, weight: .medium, design: .rounded))
//                    .foregroundStyle(.secondary)
//            }
//            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
//            .padding(16)
//            .glassCard()
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
            ScrollViewReader { proxy in
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                            ForEach(visibleFiles) { file in
                                Section {
                                    DiffFileCard(
                                        file: file,
                                        focusedHunkID: $focusedHunkID,
                                        typography: diffTypography
                                    )
                                } header: {
                                    DiffFileStickyHeader(
                                        file: file,
                                        isActive: file.id == activeFileID
                                    )
                                    .id(file.id)
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
                .onChange(of: model.pendingRevealFilePath) { _, pendingPath in
                    guard let pendingPath else {
                        return
                    }
                    selectedScreen = .diff
                    Task {
                        await revealFileInDiff(path: pendingPath, using: proxy)
                    }
                }
            }
            .glassCard()
        }
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

    private func compareCommitLabel(for entry: GitLogEntry) -> String {
        let subject = entry.subject.count > 64 ? "\(entry.subject.prefix(61))..." : entry.subject
        return "\(entry.shortHash)  \(subject)"
    }

    private func twoCommitCompareLabel(base: GitLogEntry, head: GitLogEntry) -> String {
        "\(base.shortHash) -> \(head.shortHash)  \(head.subject)"
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

    @MainActor
    private func revealFileInDiff(path: String, using proxy: ScrollViewProxy) async {
        let targetPath = normalizedDiffPath(path)
        guard !targetPath.isEmpty else {
            model.clearPendingRevealFilePath()
            return
        }

        guard let targetIndex = model.files.firstIndex(where: { file in
            diffFile(file, matchesPath: targetPath)
        }) else {
            model.clearPendingRevealFilePath()
            return
        }

        if visibleFileCount <= targetIndex {
            visibleFileCount = targetIndex + 1
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        guard targetIndex < model.files.count else {
            model.clearPendingRevealFilePath()
            return
        }
        let targetFile = model.files[targetIndex]
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(targetFile.id, anchor: .top)
        }
        focusedHunkID = targetFile.hunks.first?.id
        model.clearPendingRevealFilePath()
    }

    private func diffFile(_ file: DiffFile, matchesPath targetPath: String) -> Bool {
        let candidates = [file.displayPath, file.oldPath, file.newPath]
            .map { normalizedDiffPath($0) }
            .filter { !$0.isEmpty && $0 != "/dev/null" }
        return candidates.contains(targetPath)
    }

    private func normalizedDiffPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
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

    @ViewBuilder
    private var compareCommitMenuContent: some View {
        if model.repoPath.isEmpty {
            Text("Choose a repository first")
        } else if model.isLoadingRecentBranchCommits {
            Text("Loading commits...")
        } else if model.recentBranchCommits.isEmpty {
            Button("Load \(friendlyRefName(model.currentBranchRef)) commits") {
                Task {
                    await model.loadRecentBranchCommits(force: true)
                }
            }
        } else {
            compareCommitMenuLoadedContent
        }
    }

    @ViewBuilder
    private var compareCommitMenuLoadedContent: some View {
        Section("Compare to Current State") {
            Text("Target: current working state (HEAD + staged + unstaged)")
            ForEach(model.recentBranchCommits, id: \.id) { entry in
                Button(compareCommitLabel(for: entry)) {
                    Task {
                        await model.compareAgainstCommit(entry.id)
                    }
                }
            }
        }

        Divider()

        Section("Compare Two Commits") {
            if let selectedBase = selectedTwoCommitBase {
                Text("Base: \(selectedBase.shortHash)")
                Button("Clear base selection") {
                    selectedTwoCommitBaseID = nil
                }
                Divider()
                ForEach(selectedTwoCommitHeads, id: \.id) { head in
                    Button(twoCommitCompareLabel(base: selectedBase, head: head)) {
                        Task {
                            await model.compareBetweenCommits(baseHash: selectedBase.id, headHash: head.id)
                        }
                    }
                }
            } else {
                Text("Pick the first commit (base)")
                ForEach(model.recentBranchCommits, id: \.id) { entry in
                    Button("Set base: \(compareCommitLabel(for: entry))") {
                        selectedTwoCommitBaseID = entry.id
                    }
                }
            }
        }

        Divider()
        Button("Refresh commit list") {
            Task {
                await model.loadRecentBranchCommits(force: true)
            }
        }
    }
}

private enum WorkbenchScreen: Hashable {
    case diff
    case log
    case tree
}

private struct LibraryStatus {
    let title: String
    let color: Color
    let symbol: String
}

private struct AdvancedCompareInspector: View {
    @ObservedObject var model: DiffViewModel
    let onClose: () -> Void

    private var selectableRefs: [String] {
        model.availableBranchRefs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Custom Compare")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NativeTheme.readableSecondary)
                }
                .buttonStyle(.plain)
                .help("Close compare inspector")
            }

            Text("Supports branch names and commit hashes (for example: 2d8b243 or cfb646e).")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(NativeTheme.readableSecondary)

            VStack(alignment: .leading, spacing: 10) {
                RefInputField(
                    label: "Base ref",
                    placeholder: "HEAD~1 or 2d8b243",
                    text: $model.baseRef,
                    refs: selectableRefs
                )
                RefInputField(
                    label: "Head ref",
                    placeholder: "HEAD or cfb646e",
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
                    }
                }
                .buttonStyle(.glassProminent)

                Button("Close") {
                    onClose()
                }
                .buttonStyle(.glass)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
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

private struct CommitLogRow: View {
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

private struct CommitTreeLegendCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commit Tree Guide")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(NativeTheme.fileListPrimary)

            Text("Every dot is a commit. Vertical lines continue a branch, diagonal lines show where branches split or merge, and labels show branch/tag pointers.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(NativeTheme.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                CommitTreeLegendItem(color: CommitTreePalette.color(for: 0), title: "Branch lane")
                CommitTreeLegendItem(color: CommitTreePalette.color(for: 3), title: "Merge path")
                CommitTreeLegendItem(color: CommitTreePalette.color(for: 6), title: "Another branch")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(NativeTheme.border.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct CommitTreeLegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 16, height: 3)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(NativeTheme.readableSecondary)
        }
    }
}

private struct CommitTreeGraphList: View {
    let entries: [GitLogEntry]
    let typography: CommitTreeTypography

    var body: some View {
        let graph = CommitTreeGraphBuilder.build(entries: entries)
        LazyVStack(spacing: 0) {
            ForEach(Array(graph.rows.enumerated()), id: \.element.id) { index, row in
                CommitTreeGraphRowView(
                    row: row,
                    maxLaneCount: graph.maxLaneCount,
                    typography: typography,
                    showsDivider: index < graph.rows.count - 1
                )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.40))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NativeTheme.border.opacity(0.68), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.22), value: entries.map(\.id))
    }
}

private struct CommitTreeGraphRowView: View {
    let row: CommitTreeGraphRow
    let maxLaneCount: Int
    let typography: CommitTreeTypography
    let showsDivider: Bool

    private var graphWidth: CGFloat {
        if maxLaneCount <= 1 {
            return typography.laneLeadingInset * 2
        }
        return CGFloat(maxLaneCount - 1) * typography.laneWidth + (typography.laneLeadingInset * 2)
    }

    private var commitTypeLabel: String {
        if row.entry.parentHashes.isEmpty {
            return "Root"
        }
        if row.entry.parentHashes.count > 1 {
            return "Merge (\(row.entry.parentHashes.count))"
        }
        return "Commit"
    }

    private var commitTypeColor: Color {
        if row.entry.parentHashes.isEmpty {
            return .mint
        }
        if row.entry.parentHashes.count > 1 {
            return .orange
        }
        return NativeTheme.readableSecondary
    }

    private var parentSummary: String {
        if row.entry.parentHashes.isEmpty {
            return "No parents (starting point)."
        }
        let shortParents = row.entry.parentHashes.map { String($0.prefix(7)) }
        if shortParents.count <= 3 {
            return "Parents: \(shortParents.joined(separator: ", "))"
        }
        let listed = shortParents.prefix(3).joined(separator: ", ")
        return "Parents: \(listed) +\(shortParents.count - 3) more"
    }

    private var refTags: [String] {
        row.entry.decorations
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear
                .frame(width: graphWidth, height: 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.entry.shortHash)
                        .font(.system(size: typography.hashFontSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NativeTheme.readableSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(NativeTheme.metaBackground)
                        )

                    Text(row.entry.subject)
                        .font(.system(size: typography.subjectFontSize, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .foregroundStyle(NativeTheme.fileListPrimary)

                    Spacer(minLength: 8)

                    Text(row.entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: typography.metaFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(NativeTheme.readableSecondary)
                }

                HStack(spacing: 8) {
                    CommitAuthorAvatarView(authorName: row.entry.authorName, authorEmail: row.entry.authorEmail)
                    Text(row.entry.authorName)
                        .font(.system(size: typography.authorFontSize, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(NativeTheme.fileListPrimary)

                    Text(commitTypeLabel)
                        .font(.system(size: typography.metaFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(commitTypeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(commitTypeColor.opacity(0.18))
                        )

                    Spacer(minLength: 0)
                }

                Text(parentSummary)
                    .font(.system(size: typography.metaFontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(NativeTheme.readableSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !refTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(refTags.enumerated()), id: \.offset) { _, tag in
                                Text(tag)
                                    .font(.system(size: typography.metaFontSize, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(NativeTheme.fileListPrimary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(NativeTheme.metaBackground)
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, typography.rowHorizontalPadding)
        .padding(.vertical, typography.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                CommitTreeLaneCanvas(
                    row: row,
                    maxLaneCount: maxLaneCount,
                    typography: typography
                )
                .frame(width: graphWidth, height: proxy.size.height, alignment: .topLeading)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(NativeTheme.border.opacity(0.52))
                    .frame(height: 1)
            }
        }
    }
}

private struct CommitTreeLaneCanvas: View {
    let row: CommitTreeGraphRow
    let maxLaneCount: Int
    let typography: CommitTreeTypography

    var body: some View {
        Canvas { context, size in
            let topY: CGFloat = 0
            let centerY = size.height * 0.5
            let bottomY = size.height

            for lane in 0..<max(1, maxLaneCount) {
                let laneX = xPosition(for: lane)
                var guidePath = Path()
                guidePath.move(to: CGPoint(x: laneX, y: topY))
                guidePath.addLine(to: CGPoint(x: laneX, y: bottomY))
                context.stroke(
                    guidePath,
                    with: .color(NativeTheme.border.opacity(0.2)),
                    style: StrokeStyle(lineWidth: typography.guideLineWidth, dash: [2, 5])
                )
            }

            for link in row.incoming {
                draw(link: link, startY: topY, endY: centerY, context: &context)
            }

            for link in row.outgoing {
                draw(link: link, startY: centerY, endY: bottomY, context: &context)
            }

            let nodeX = xPosition(for: row.nodeLane)
            let nodeColor = CommitTreePalette.color(for: row.nodeColorIndex)
            let nodeRadius = typography.nodeDiameter * 0.5
            let nodeRect = CGRect(
                x: nodeX - nodeRadius,
                y: centerY - nodeRadius,
                width: typography.nodeDiameter,
                height: typography.nodeDiameter
            )

            context.fill(Path(ellipseIn: nodeRect), with: .color(nodeColor))
            context.stroke(
                Path(ellipseIn: nodeRect),
                with: .color(Color.black.opacity(0.65)),
                lineWidth: typography.nodeStrokeWidth
            )
        }
        .accessibilityHidden(true)
    }

    private func xPosition(for lane: Int) -> CGFloat {
        CGFloat(lane) * typography.laneWidth + typography.laneLeadingInset
    }

    private func draw(
        link: CommitTreeLaneLink,
        startY: CGFloat,
        endY: CGFloat,
        context: inout GraphicsContext
    ) {
        let fromX = xPosition(for: link.fromLane)
        let toX = xPosition(for: link.toLane)

        var path = Path()
        path.move(to: CGPoint(x: fromX, y: startY))

        if abs(fromX - toX) < 0.5 {
            path.addLine(to: CGPoint(x: toX, y: endY))
        } else {
            let control = CGPoint(
                x: (fromX + toX) * 0.5,
                y: startY + ((endY - startY) * 0.42)
            )
            path.addQuadCurve(to: CGPoint(x: toX, y: endY), control: control)
        }

        context.stroke(
            path,
            with: .color(CommitTreePalette.color(for: link.colorIndex)),
            lineWidth: typography.branchLineWidth
        )
    }
}

private enum CommitTreePalette {
    static let colors: [Color] = [
        Color(red: 0.30, green: 0.79, blue: 0.94),
        Color(red: 0.98, green: 0.75, blue: 0.34),
        Color(red: 0.72, green: 0.59, blue: 0.96),
        Color(red: 0.33, green: 0.86, blue: 0.64),
        Color(red: 0.98, green: 0.52, blue: 0.38),
        Color(red: 0.98, green: 0.45, blue: 0.73),
        Color(red: 0.40, green: 0.85, blue: 0.82),
        Color(red: 0.91, green: 0.57, blue: 0.96),
        Color(red: 0.54, green: 0.71, blue: 0.99),
        Color(red: 0.97, green: 0.90, blue: 0.47)
    ]

    static func color(for index: Int) -> Color {
        guard !colors.isEmpty else {
            return Color.accentColor
        }
        return colors[abs(index) % colors.count]
    }
}

private struct CommitTreeGraph {
    let rows: [CommitTreeGraphRow]
    let maxLaneCount: Int
}

private struct CommitTreeGraphRow: Identifiable {
    let entry: GitLogEntry
    let nodeLane: Int
    let nodeColorIndex: Int
    let incoming: [CommitTreeLaneLink]
    let outgoing: [CommitTreeLaneLink]
    let laneCount: Int

    var id: String {
        entry.id
    }
}

private struct CommitTreeLaneLink: Hashable {
    let fromLane: Int
    let toLane: Int
    let colorIndex: Int
}

private enum CommitTreeGraphBuilder {
    private struct LaneToken: Hashable {
        let hash: String
        let colorIndex: Int
    }

    static func build(entries: [GitLogEntry]) -> CommitTreeGraph {
        guard !entries.isEmpty else {
            return CommitTreeGraph(rows: [], maxLaneCount: 1)
        }

        let visibleCommitIDs = Set(entries.map(\.id))
        var rows: [CommitTreeGraphRow] = []
        rows.reserveCapacity(entries.count)

        var lanes: [LaneToken] = []
        var nextColorIndex = 0
        var maxLaneCount = 1

        for entry in entries {
            var currentLanes = lanes
            let nodeLane: Int

            if let existingLane = currentLanes.firstIndex(where: { $0.hash == entry.id }) {
                nodeLane = existingLane
            } else {
                currentLanes.insert(
                    LaneToken(hash: entry.id, colorIndex: allocateColorIndex(nextColorIndex: &nextColorIndex)),
                    at: 0
                )
                nodeLane = 0
            }

            let nodeColorIndex = currentLanes[nodeLane].colorIndex
            let incoming = laneLinks(from: lanes, to: currentLanes)

            var nextLanes = currentLanes
            nextLanes.remove(at: nodeLane)

            var filteredParents: [String] = []
            filteredParents.reserveCapacity(entry.parentHashes.count)
            var seenParents = Set<String>()

            for parentHash in entry.parentHashes {
                let normalized = parentHash.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    continue
                }
                guard visibleCommitIDs.contains(normalized) else {
                    continue
                }
                if seenParents.insert(normalized).inserted {
                    filteredParents.append(normalized)
                }
            }

            var insertionOffset = 0
            for (parentPosition, parentHash) in filteredParents.enumerated() {
                if nextLanes.contains(where: { $0.hash == parentHash }) {
                    continue
                }

                let colorIndex = parentPosition == 0
                    ? nodeColorIndex
                    : allocateColorIndex(nextColorIndex: &nextColorIndex)
                let insertionIndex = min(nodeLane + insertionOffset, nextLanes.count)
                nextLanes.insert(
                    LaneToken(hash: parentHash, colorIndex: colorIndex),
                    at: insertionIndex
                )
                insertionOffset += 1
            }

            var outgoing = laneLinks(from: currentLanes, to: nextLanes)

            for parentHash in filteredParents {
                guard let parentLane = nextLanes.firstIndex(where: { $0.hash == parentHash }) else {
                    continue
                }
                let parentLink = CommitTreeLaneLink(
                    fromLane: nodeLane,
                    toLane: parentLane,
                    colorIndex: nextLanes[parentLane].colorIndex
                )
                if !outgoing.contains(parentLink) {
                    outgoing.append(parentLink)
                }
            }

            let laneCount = max(
                max(currentLanes.count, nextLanes.count),
                maxLaneDepth(for: incoming),
                maxLaneDepth(for: outgoing),
                nodeLane + 1
            )
            maxLaneCount = max(maxLaneCount, laneCount)

            rows.append(
                CommitTreeGraphRow(
                    entry: entry,
                    nodeLane: nodeLane,
                    nodeColorIndex: nodeColorIndex,
                    incoming: incoming,
                    outgoing: outgoing,
                    laneCount: laneCount
                )
            )

            lanes = nextLanes
        }

        return CommitTreeGraph(rows: rows, maxLaneCount: maxLaneCount)
    }

    private static func laneLinks(from source: [LaneToken], to target: [LaneToken]) -> [CommitTreeLaneLink] {
        guard !source.isEmpty, !target.isEmpty else {
            return []
        }

        var targetIndexByHash: [String: Int] = [:]
        targetIndexByHash.reserveCapacity(target.count)
        for (index, token) in target.enumerated() {
            targetIndexByHash[token.hash] = index
        }

        var links: [CommitTreeLaneLink] = []
        links.reserveCapacity(source.count)

        for (sourceLane, token) in source.enumerated() {
            guard let targetLane = targetIndexByHash[token.hash] else {
                continue
            }
            links.append(
                CommitTreeLaneLink(
                    fromLane: sourceLane,
                    toLane: targetLane,
                    colorIndex: token.colorIndex
                )
            )
        }

        return links
    }

    private static func maxLaneDepth(for links: [CommitTreeLaneLink]) -> Int {
        links.reduce(0) { partial, link in
            max(partial, max(link.fromLane, link.toLane) + 1)
        }
    }

    private static func allocateColorIndex(nextColorIndex: inout Int) -> Int {
        defer { nextColorIndex += 1 }
        return nextColorIndex
    }
}

private struct CommitAuthorAvatarView: View {
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

private struct DiffFileCard: View {
    let file: DiffFile
    @Binding var focusedHunkID: UUID?
    let typography: DiffTypography
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
                        focusedHunkID: $focusedHunkID,
                        typography: typography
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
        let contentType = UTType(filenameExtension: ext) ?? .plainText
        let icon = NSWorkspace.shared.icon(for: contentType)
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
    static let deleteLineNumber = Color(nsColor: .systemRed).opacity(0.72)
    static let addLineNumber = Color(nsColor: .systemGreen).opacity(0.72)
    static let deleteLineNumberBackground = Color(nsColor: .systemRed).opacity(0.11)
    static let addLineNumberBackground = Color(nsColor: .systemGreen).opacity(0.11)
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
    static let baseRowHeight: CGFloat = 25
    static let numberGutterWidth: CGFloat = 56
    static let markerColumnWidth: CGFloat = 16
    static let gutterWidth: CGFloat = 64
    static let gridLine = NativeTheme.border
}

private struct CommitTreeTypography {
    static let defaultScale: CGFloat = 1.0
    static let minScale: CGFloat = 0.75
    static let maxScale: CGFloat = 1.8
    static let scaleStep: CGFloat = 0.1

    let scale: CGFloat

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private var clampedScale: CGFloat {
        Self.clamp(scale)
    }

    var laneWidth: CGFloat {
        18 * clampedScale
    }

    var laneLeadingInset: CGFloat {
        10 * clampedScale
    }

    var branchLineWidth: CGFloat {
        max(1.7, 2.2 * clampedScale)
    }

    var guideLineWidth: CGFloat {
        max(0.75, 1.0 * clampedScale)
    }

    var nodeDiameter: CGFloat {
        max(8, 11 * clampedScale)
    }

    var nodeStrokeWidth: CGFloat {
        max(0.8, 1.0 * clampedScale)
    }

    var rowHorizontalPadding: CGFloat {
        10 * clampedScale
    }

    var rowVerticalPadding: CGFloat {
        max(7, 8 * clampedScale)
    }

    var hashFontSize: CGFloat {
        11 * clampedScale
    }

    var subjectFontSize: CGFloat {
        13 * clampedScale
    }

    var authorFontSize: CGFloat {
        11 * clampedScale
    }

    var metaFontSize: CGFloat {
        10 * clampedScale
    }
}

private struct DiffTypography {
    static let defaultScale: CGFloat = 1.0
    static let minScale: CGFloat = 0.75
    static let maxScale: CGFloat = 1.8
    static let scaleStep: CGFloat = 0.1

    let scale: CGFloat

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private var clampedScale: CGFloat {
        Self.clamp(scale)
    }

    var rowHeight: CGFloat {
        max(19, ceil(DiffGridStyle.baseRowHeight * clampedScale))
    }

    var hunkHeaderFontSize: CGFloat {
        11 * clampedScale
    }

    var lineNumberFontSize: CGFloat {
        11 * clampedScale
    }

    var markerFontSize: CGFloat {
        12 * clampedScale
    }

    var lineTextFontSize: CGFloat {
        12 * clampedScale
    }
}

private enum DiffSide {
    case left
    case right
}

private struct HunkView: View {
    let hunk: DiffHunk
    @Binding var focusedHunkID: UUID?
    let typography: DiffTypography

    private static let rowChunkSize = 320
    private static let bridgeOverlayRowLimit = 1800
    private static let separatorRowLimit = 4000

    var body: some View {
        VStack(spacing: 0) {
            Text(hunk.header)
                .font(.system(size: typography.hunkHeaderFontSize, weight: .medium, design: .monospaced))
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
                        showsSeparators: shouldDrawRowSeparators,
                        typography: typography
                    )
                }
            }
            .background(NativeTheme.fileCardBackground)
            .overlay {
                if shouldRenderBridgeOverlay {
                    BridgeOverlay(
                        bridges: hunk.bridges,
                        rowHeight: typography.rowHeight,
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
        return focusedHunkID == hunk.id ? 1.15 : 1.0
    }
}

private struct HunkRowsChunkView: View {
    let rows: [DiffRow]
    let rowRange: Range<Int>
    let showsSeparators: Bool
    let typography: DiffTypography

    var body: some View {
        ForEach(rowRange, id: \.self) { rowIndex in
            DiffLineRow(row: rows[rowIndex], typography: typography)
                .frame(height: typography.rowHeight)
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
    let typography: DiffTypography

    var body: some View {
        if row.kind == .meta {
            HStack(spacing: 0) {
                Text(verbatim: row.text)
                    .font(.system(size: typography.lineTextFontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(NativeTheme.metaText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
            }
            .background(NativeTheme.metaBackground)
        } else {
            HStack(spacing: 0) {
                SideGridCell(side: .left, row: row, typography: typography)
                GutterGridCell(row: row, width: DiffGridStyle.gutterWidth)
                SideGridCell(side: .right, row: row, typography: typography)
            }
            .background(NativeTheme.fileCardBackground)
        }
    }
}

private struct SideGridCell: View {
    let side: DiffSide
    let row: DiffRow
    let typography: DiffTypography

    var body: some View {
        let cell = cellData(for: row, side: side)

        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                cell.lineNumberBackground
                Text(cell.lineNumber.map(String.init) ?? "")
                    .font(.system(size: typography.lineNumberFontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(cell.lineNumberColor)
                    .padding(.trailing, 8)
            }
            .frame(width: DiffGridStyle.numberGutterWidth, alignment: .trailing)

            Rectangle()
                .fill(DiffGridStyle.gridLine.opacity(0.75))
                .frame(width: 1)

            Text(cell.marker)
                .font(.system(size: typography.markerFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(cell.markerColor)
                .frame(width: DiffGridStyle.markerColumnWidth, alignment: .center)

            Rectangle()
                .fill(DiffGridStyle.gridLine.opacity(0.75))
                .frame(width: 1)

            Text(verbatim: cell.text.isEmpty ? " " : cell.text)
                .font(.system(size: typography.lineTextFontSize, weight: .regular, design: .monospaced))
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
        lineNumberBackground: Color,
        lineNumberColor: Color,
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
                lineNumberBackground: NativeTheme.lineNumberGutter,
                lineNumberColor: NativeTheme.lineNumber,
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
                    lineNumberBackground: NativeTheme.deleteLineNumberBackground,
                    lineNumberColor: NativeTheme.deleteLineNumber,
                    placeholder: false
                )
            }
            return (
                lineNumber: row.oldLineNumber,
                marker: " ",
                text: " ",
                background: NativeTheme.deletePlaceholderBackground,
                markerColor: NativeTheme.placeholderLineNumber,
                lineNumberBackground: NativeTheme.lineNumberGutter,
                lineNumberColor: NativeTheme.placeholderLineNumber,
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
                    lineNumberBackground: NativeTheme.addLineNumberBackground,
                    lineNumberColor: NativeTheme.addLineNumber,
                    placeholder: false
                )
            }
            return (
                lineNumber: row.newLineNumber,
                marker: " ",
                text: " ",
                background: NativeTheme.addPlaceholderBackground,
                markerColor: NativeTheme.placeholderLineNumber,
                lineNumberBackground: NativeTheme.lineNumberGutter,
                lineNumberColor: NativeTheme.placeholderLineNumber,
                placeholder: true
            )
        case .meta:
            return (
                lineNumber: nil,
                marker: " ",
                text: row.text,
                background: NativeTheme.metaBackground,
                markerColor: .secondary,
                lineNumberBackground: NativeTheme.lineNumberGutter,
                lineNumberColor: NativeTheme.lineNumber,
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
                let gutterHalf = gutterWidth * 0.5
                let guideInset: CGFloat = 3
                let bridgeOverlap: CGFloat = 1.5
                let leftGuideX = centerX - gutterHalf + guideInset
                let rightGuideX = centerX + gutterHalf - guideInset
                let leftX = centerX - gutterHalf - bridgeOverlap
                let rightX = centerX + gutterHalf + bridgeOverlap

                var centerGuide = Path()
                centerGuide.move(to: CGPoint(x: centerX, y: 0))
                centerGuide.addLine(to: CGPoint(x: centerX, y: size.height))
                context.stroke(
                    centerGuide,
                    with: .color(NativeTheme.centerGuide.opacity(guideOpacity)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )

                var leftGuide = Path()
                leftGuide.move(to: CGPoint(x: leftGuideX, y: 0))
                leftGuide.addLine(to: CGPoint(x: leftGuideX, y: size.height))
                context.stroke(
                    leftGuide,
                    with: .color(NativeTheme.sideGuides.opacity(guideOpacity)),
                    style: StrokeStyle(lineWidth: 1)
                )

                var rightGuide = Path()
                rightGuide.move(to: CGPoint(x: rightGuideX, y: 0))
                rightGuide.addLine(to: CGPoint(x: rightGuideX, y: size.height))
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

                    let verticalExtension = min(3, rowHeight * 0.14)
                    let sourceTop = max(0, CGFloat(deletedMin) * rowHeight - verticalExtension)
                    let sourceBottom = min(size.height, CGFloat(deletedMax + 1) * rowHeight + verticalExtension)
                    let targetTop = max(0, CGFloat(addedMin) * rowHeight - verticalExtension)
                    let targetBottom = min(size.height, CGFloat(addedMax + 1) * rowHeight + verticalExtension)
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
        .frame(width: 700, height: 500)
        .environmentObject(DiffViewModel())
}
