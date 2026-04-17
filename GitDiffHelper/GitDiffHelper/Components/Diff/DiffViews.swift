import AppKit
import SwiftUI
import UniformTypeIdentifiers

/*
 Diff screen rendering map:

 ContentView.diffArea
 +-- DiffFileStickyHeader
 +-- DiffFileCard (per file)
     +-- HunkView (per hunk)
         +-- HunkRowsChunkView (chunked rows)
             +-- DiffLineRow
                 +-- SideGridCell(.left)
                 +-- GutterGridCell
                 +-- SideGridCell(.right)
         +-- BridgeOverlay (optional)
*/

/// Card container for a single changed file.
/// Handles progressive hunk rendering for large files.
struct DiffFileCard: View {
    let file: DiffFile
    @Binding var focusedHunkID: UUID?
    let typography: DiffTypography
    @State private var visibleHunkCount = 0

    private static let hunkBatchSize = 12
    
    var strokeColor: Color {
        file.seen ? NativeTheme.seenBorder : NativeTheme.border
    }

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
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(strokeColor, lineWidth: 1)
        )
        .background(NativeTheme.fileCardBackground, in: RoundedRectangle(cornerRadius: 12))
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


/// System-derived file icon used next to file headers.
struct FileTypeIcon: View {
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

/// Indicates which side of the split diff grid is being rendered.
enum DiffSide {
    case left
    case right
}

/// One hunk block (`@@ ... @@`) including lines and optional bridge overlay.
/// Focus can be set by tapping the hunk.
struct HunkView: View {
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
                .background(NativeTheme.hunkHeaderBackground, in: .rect(
                    topLeadingRadius: 10,
                    topTrailingRadius: 10
                ))

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

        // Render large hunks in slices to keep SwiftUI layout cost stable.
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

/// Chunk renderer for ranges of rows inside one hunk.
/// Keeps very large hunks cheaper to lay out.
struct HunkRowsChunkView: View {
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

/// Single visual row in the diff grid.
/// Meta rows render full-width; content rows render split left/right cells.
struct DiffLineRow: View {
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

/// Left or right side cell for one diff row.
/// Responsible for numbers, +/- marker, text, and placeholder behavior.
struct SideGridCell: View {
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

/// Center gutter between left and right sides.
/// Displays row-type tinting and guide separators.
struct GutterGridCell: View {
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

/// Curved bridge ribbons connecting deletion/addition groups in one hunk.
/// Drawn as a non-interactive Canvas overlay.
struct BridgeOverlay: View {
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

                    // Expand each side slightly so ribbons remain continuous between adjacent rows.
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
