import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: DiffViewModel
    @State private var showAdvancedOptions = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.93, blue: 0.88),
                    Color(red: 0.84, green: 0.9, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                headerCard
                controlsCard
                diffArea
            }
            .padding(16)
        }
        .task {
            await model.initialLoadIfNeeded()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BridgeDiff Native")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color(red: 0.16, green: 0.34, blue: 0.44))

            Text("Start in 2 steps")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))

            Text("1) Choose your project folder. 2) Click \"Show Uncommitted Changes\".")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.24, green: 0.35, blue: 0.42))

            Text(model.repoSummary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(red: 0.92, green: 0.96, blue: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Repository")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                Button {
                    chooseRepositoryFolder()
                } label: {
                    Label("Choose Repository Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button("Use Current Folder") {
                    Task {
                        await model.chooseRepository(path: FileManager.default.currentDirectoryPath)
                    }
                }
                .buttonStyle(.bordered)
            }

            PathChip(path: model.repoPath.isEmpty ? "No folder selected" : model.repoPath)

            Divider()

            Text("Load Diff")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                Button("Show Uncommitted Changes") {
                    Task {
                        await model.loadUncommittedChanges()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.repoPath.isEmpty)

                Button("Compare Last Commit") {
                    Task {
                        await model.loadLastCommit()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.repoPath.isEmpty)

                Button("Render Sample") {
                    model.renderSample()
                }
                .buttonStyle(.bordered)
            }

            DisclosureGroup("Advanced Compare Options", isExpanded: $showAdvancedOptions) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledField(label: "Base ref", placeholder: "HEAD~1", text: $model.baseRef)
                    LabeledField(label: "Head ref", placeholder: "HEAD", text: $model.headRef)
                    LabeledField(label: "Path filter", placeholder: "src/ or README.md", text: $model.pathFilter)

                    Button("Run Advanced Compare") {
                        Task {
                            await model.loadDiff()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.repoPath.isEmpty)
                }
                .padding(.top, 8)
            }

            Text(model.statusLine)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(model.hasError ? .red : Color(red: 0.18, green: 0.35, blue: 0.45))
        }
        .cardSurface()
    }

    @ViewBuilder
    private var diffArea: some View {
        if model.files.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No diff loaded yet")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Click \"Choose Repository Folder\", then \"Show Uncommitted Changes\".")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .cardSurface()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.files) { file in
                        DiffFileCard(file: file)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func chooseRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose Repository"
        panel.message = "Select your Git project folder."
        if !model.repoPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: model.repoPath, isDirectory: true)
        }

        if panel.runModal() == .OK, let selectedURL = panel.url {
            Task {
                await model.chooseRepository(path: selectedURL.path)
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
                .foregroundStyle(Color(red: 0.2, green: 0.34, blue: 0.43))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
        }
    }
}

private struct PathChip: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(Color(red: 0.18, green: 0.32, blue: 0.41))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.93, green: 0.96, blue: 0.98))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            .background(Color(red: 0.95, green: 0.97, blue: 0.98))

            ForEach(Array(file.hunks.enumerated()), id: \.element.id) { index, hunk in
                if index > 0 {
                    Divider()
                        .background(Color(red: 0.84, green: 0.89, blue: 0.92))
                }
                HunkView(hunk: hunk)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.78, green: 0.84, blue: 0.88), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(Color.white)
    }
}

private enum DiffGridStyle {
    static let rowHeight: CGFloat = 25
    static let numberColumnWidth: CGFloat = 48
    static let markerColumnWidth: CGFloat = 16
    static let gutterWidth: CGFloat = 64
    static let gridLine = Color(red: 0.84, green: 0.82, blue: 0.89)
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
                .foregroundStyle(Color(red: 0.3, green: 0.4, blue: 0.47))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.985, green: 0.99, blue: 0.995))

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
            .background(Color.white)
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
                    .foregroundStyle(Color(red: 0.6, green: 0.44, blue: 0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
            }
            .background(Color(red: 1.0, green: 0.97, blue: 0.91))
        } else {
            HStack(spacing: 0) {
                SideGridCell(side: .left, row: row)
                GutterGridCell(row: row, width: DiffGridStyle.gutterWidth)
                SideGridCell(side: .right, row: row)
            }
            .background(Color.white)
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
                .foregroundStyle(Color(red: 0.44, green: 0.52, blue: 0.58))
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
                background: Color.white,
                markerColor: Color.secondary,
                placeholder: false
            )
        case .delete:
            if side == .left {
                return (
                    lineNumber: row.oldLineNumber,
                    marker: "-",
                    text: row.text,
                    background: Color(red: 0.98, green: 0.91, blue: 0.95),
                    markerColor: Color(red: 0.72, green: 0.2, blue: 0.45),
                    placeholder: false
                )
            }
            return (
                lineNumber: nil,
                marker: " ",
                text: "",
                background: Color(red: 0.99, green: 0.98, blue: 0.995),
                markerColor: Color.secondary,
                placeholder: true
            )
        case .add:
            if side == .right {
                return (
                    lineNumber: row.newLineNumber,
                    marker: "+",
                    text: row.text,
                    background: Color(red: 0.91, green: 0.97, blue: 0.93),
                    markerColor: Color(red: 0.14, green: 0.48, blue: 0.3),
                    placeholder: false
                )
            }
            return (
                lineNumber: nil,
                marker: " ",
                text: "",
                background: Color(red: 0.99, green: 0.98, blue: 0.995),
                markerColor: Color.secondary,
                placeholder: true
            )
        case .meta:
            return (
                lineNumber: nil,
                marker: " ",
                text: row.text,
                background: Color(red: 1.0, green: 0.97, blue: 0.91),
                markerColor: Color.secondary,
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
                .fill(Color(red: 0.67, green: 0.53, blue: 0.81).opacity(0.24))
                .frame(width: 1)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }

    private func gutterBackground(for row: DiffRow) -> Color {
        switch row.kind {
        case .delete:
            return Color(red: 0.97, green: 0.94, blue: 0.985)
        case .add:
            return Color(red: 0.95, green: 0.95, blue: 0.985)
        case .context:
            return Color(red: 0.985, green: 0.985, blue: 0.996)
        case .meta:
            return Color(red: 1.0, green: 0.97, blue: 0.91)
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
                    with: .color(Color(red: 0.58, green: 0.45, blue: 0.76).opacity(0.28)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )

                var leftGuide = Path()
                leftGuide.move(to: CGPoint(x: leftX, y: 0))
                leftGuide.addLine(to: CGPoint(x: leftX, y: size.height))
                context.stroke(
                    leftGuide,
                    with: .color(Color(red: 0.64, green: 0.56, blue: 0.8).opacity(0.14)),
                    style: StrokeStyle(lineWidth: 1)
                )

                var rightGuide = Path()
                rightGuide.move(to: CGPoint(x: rightX, y: 0))
                rightGuide.addLine(to: CGPoint(x: rightX, y: size.height))
                context.stroke(
                    rightGuide,
                    with: .color(Color(red: 0.64, green: 0.56, blue: 0.8).opacity(0.14)),
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
                        with: .color(Color(red: 0.74, green: 0.58, blue: 0.9).opacity(ribbonOpacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    func cardSurface() -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.79, green: 0.84, blue: 0.88), lineWidth: 1)
            )
    }
}
