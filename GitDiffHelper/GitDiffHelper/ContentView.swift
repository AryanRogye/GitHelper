import AppKit
import SwiftUI

// Main workbench shell that coordinates sidebar state and the currently selected screen.
struct ContentView: View {
    @EnvironmentObject private var model: DiffViewModel
    @Namespace private var glassNamespace
    @State private var showAdvancedInspector = false
    @State private var selectedTwoCommitBaseID: String?
    @State private var visibleFileCount = 0
    @State private var focusedHunkID: UUID?
    @State private var selectedScreen: WorkbenchScreen = .diff
    @AppStorage("BridgeDiff.diffTextScale") private var storedDiffTextScale = 1.0
    @AppStorage("BridgeDiff.treeScale") private var storedTreeScale = 1.0

    private static let fileRenderBatchSize = 24

    // MARK: - Derived State

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


    var body: some View {
        NavigationSplitView {
            GitDiffSidebar()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
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
                await model.ensureCommitLogLoaded()
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
                    await model.ensureCommitLogLoaded()
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
                    GitCommitLogArea(
                        
                    )
                case .tree:
                    GitCommitTreeArea(
                        storedTreeScale: $storedTreeScale
                    )
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
