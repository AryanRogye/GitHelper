import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DiffViewModel
    @Namespace private var glassNamespace
    @State private var showAdvancedSheet = false

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

    var body: some View {
        NavigationSplitView {
            List {
                Section("Workspace") {
                    Button("Choose Repository...", systemImage: "folder.badge.plus") {
                        chooseRepositoryFolder()
                    }
                    .help("Pick a folder that contains your .git repository")

                    Button("Use Current Folder", systemImage: "folder") {
                        Task {
                            await model.chooseRepository(path: FileManager.default.currentDirectoryPath)
                        }
                    }
                }

                Section("Repository Library") {
                    if model.library.isEmpty {
                        Text("No repositories saved yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.library) { entry in
                            Button {
                                Task {
                                    await model.loadLibraryRepository(id: entry.id)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(width: 16, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(entry.displayName)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        Text("\(friendlyRefName(entry.lastBranch)) • \(entry.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .sidebarSelectableRow(isSelected: model.selectedLibraryRepoID == entry.id)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.removeLibraryRepository(id: entry.id)
                                } label: {
                                    Label("Remove from Library", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if let selectedEntry = selectedLibraryEntry {
                    Section("Recent Comparisons (\(selectedEntry.displayName))") {
                        if displayedSessions.isEmpty {
                            Text("No sessions yet for this repository.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(displayedSessions) { session in
                                Button {
                                    Task {
                                        await model.loadLibrarySession(repoID: selectedEntry.id, sessionID: session.id)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(friendlyCompareLabel(session.compareLabel))
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("\(session.fileCount) files • \(session.hunkCount) hunks • \(session.bridgeCount) bridges")
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(.secondary)
                                        Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .sidebarSelectableRow(isSelected: model.selectedLibrarySessionID == session.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
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
        }
    }

    private var topGlassPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BridgeDiff Workbench")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Native macOS diff tooling with bridge visualization.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Use Current Folder", systemImage: "folder") {
                    Task {
                        await model.chooseRepository(path: FileManager.default.currentDirectoryPath)
                    }
                }
                .buttonStyle(.glass)
            }

            Text(model.repoPath.isEmpty ? "No repository selected" : model.repoPath)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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
        .glassCard()
    }

    @ViewBuilder
    private var diffArea: some View {
        if model.files.isEmpty {
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
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.files) { file in
                        DiffFileCard(file: file)
                    }
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
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isError ? Color.red : Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .glassEffectID(id, in: namespace)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiffFileCard: View {
    let file: DiffFile

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(file.displayPath.isEmpty ? "(unknown file)" : file.displayPath)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text("\(file.hunks.count) hunk\(file.hunks.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NativeTheme.headerRow)

            ForEach(Array(file.hunks.enumerated()), id: \.element.id) { index, hunk in
                if index > 0 {
                    Divider()
                        .background(NativeTheme.border.opacity(0.8))
                }
                HunkView(hunk: hunk)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(NativeTheme.fileCardBackground)
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
                    ? Color.accentColor.opacity(0.16)
                    : (isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.08) : Color.clear)
            )
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                isSelected ? Color.accentColor.opacity(0.35) : Color.clear,
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
    static let field = Color(nsColor: .textBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let headerRow = Color(nsColor: .underPageBackgroundColor)
    static let fileCardBackground = Color(nsColor: .textBackgroundColor)
    static let contextBackground = Color(nsColor: .textBackgroundColor)
    static let lineNumber = Color(nsColor: .secondaryLabelColor)
    static let hunkHeaderText = Color(nsColor: .secondaryLabelColor)
    static let hunkHeaderBackground = Color(nsColor: .underPageBackgroundColor).opacity(0.7)
    static let metaText = Color(nsColor: .tertiaryLabelColor)
    static let metaBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.08)
    static let deleteBackground = Color.red.opacity(0.12)
    static let deleteMarker = Color.red.opacity(0.85)
    static let addBackground = Color.green.opacity(0.12)
    static let addMarker = Color.green.opacity(0.8)
    static let placeholderBackground = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let gutterDelete = Color.red.opacity(0.06)
    static let gutterAdd = Color.green.opacity(0.06)
    static let gutterContext = Color(nsColor: .controlBackgroundColor).opacity(0.4)
    static let gutterAccent = Color.accentColor.opacity(0.2)
    static let centerGuide = Color.accentColor.opacity(0.2)
    static let sideGuides = Color(nsColor: .separatorColor).opacity(0.28)
    static let bridgeRibbon = Color.accentColor
}

private enum DiffGridStyle {
    static let rowHeight: CGFloat = 25
    static let numberColumnWidth: CGFloat = 48
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

    var body: some View {
        VStack(spacing: 0) {
            Text(hunk.header)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NativeTheme.hunkHeaderText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(NativeTheme.hunkHeaderBackground)

            VStack(spacing: 0) {
                ForEach(Array(hunk.rows.enumerated()), id: \.element.id) { index, row in
                    DiffLineRow(row: row)
                        .frame(height: DiffGridStyle.rowHeight)
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle()
                                    .fill(DiffGridStyle.gridLine.opacity(0.62))
                                    .frame(height: 1)
                            }
                        }
                }
            }
            .background(NativeTheme.fileCardBackground)
            .overlay {
                BridgeOverlay(
                    bridges: hunk.bridges,
                    rowHeight: DiffGridStyle.rowHeight,
                    gutterWidth: DiffGridStyle.gutterWidth
                )
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
            Text(cell.lineNumber.map(String.init) ?? "")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(NativeTheme.lineNumber)
                .frame(width: DiffGridStyle.numberColumnWidth, alignment: .trailing)
                .padding(.trailing, 8)

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
                .padding(.horizontal, 8)
        }
        .opacity(cell.placeholder ? 0.33 : 1.0)
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
                lineNumber: nil,
                marker: " ",
                text: "",
                background: NativeTheme.placeholderBackground,
                markerColor: .secondary,
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
                lineNumber: nil,
                marker: " ",
                text: "",
                background: NativeTheme.placeholderBackground,
                markerColor: .secondary,
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

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard size.width > 320 else {
                    return
                }

                let centerX = size.width * 0.5
                let leftX = centerX - (gutterWidth * 0.5) + 6
                let rightX = centerX + (gutterWidth * 0.5) - 6

                var centerGuide = Path()
                centerGuide.move(to: CGPoint(x: centerX, y: 0))
                centerGuide.addLine(to: CGPoint(x: centerX, y: size.height))
                context.stroke(
                    centerGuide,
                    with: .color(NativeTheme.centerGuide),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )

                var leftGuide = Path()
                leftGuide.move(to: CGPoint(x: leftX, y: 0))
                leftGuide.addLine(to: CGPoint(x: leftX, y: size.height))
                context.stroke(
                    leftGuide,
                    with: .color(NativeTheme.sideGuides),
                    style: StrokeStyle(lineWidth: 1)
                )

                var rightGuide = Path()
                rightGuide.move(to: CGPoint(x: rightX, y: 0))
                rightGuide.addLine(to: CGPoint(x: rightX, y: size.height))
                context.stroke(
                    rightGuide,
                    with: .color(NativeTheme.sideGuides),
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

                    let ribbonOpacity = 0.12 + min(CGFloat(bridge.weight) * 0.02, 0.08)
                    context.fill(
                        ribbon,
                        with: .color(NativeTheme.bridgeRibbon.opacity(ribbonOpacity))
                    )
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
