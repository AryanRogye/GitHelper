import SwiftUI

/*
 Commit tree rendering map:

 ContentView.commitTreeArea
 +-- CommitTreeLegendCard
 |   +-- CommitTreeLegendItem
 |
 +-- CommitTreeGraphList
     +-- CommitTreeGraphBuilder.build(entries:)
     +-- CommitTreeGraphRowView (per row)
         +-- CommitTreeLaneCanvas
*/

/// Static help card above the commit tree.
/// Explains lane and merge visuals to the user.
struct CommitTreeLegendCard: View {
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

/// One tiny legend sample (colored lane swatch + title) inside `CommitTreeLegendCard`.
struct CommitTreeLegendItem: View {
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

/// Tree list container that transforms git log entries into lane-aware rows.
/// Entry point for commit graph rendering in `ContentView.commitTreeArea`.
struct CommitTreeGraphList: View {
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

/// Visual row combining commit metadata text with lane graph overlay.
/// One instance represents one `GitLogEntry`.
struct CommitTreeGraphRowView: View {
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

/// Canvas overlay that draws lane guides, links, and the commit node for a row.
/// Embedded by `CommitTreeGraphRowView`.
struct CommitTreeLaneCanvas: View {
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

/// Centralized palette so branch lanes keep consistent colors across rows.
enum CommitTreePalette {
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

/// Output model from `CommitTreeGraphBuilder`.
/// Holds row layout plus global lane width requirements.
struct CommitTreeGraph {
    let rows: [CommitTreeGraphRow]
    let maxLaneCount: Int
}

/// Render-ready row model for commit tree UI.
/// Includes lane placement and incoming/outgoing links.
struct CommitTreeGraphRow: Identifiable {
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

/// A single lane connection from one row's lane index to the next.
struct CommitTreeLaneLink: Hashable {
    let fromLane: Int
    let toLane: Int
    let colorIndex: Int
}

/// Builds lane positions and link geometry from linear `GitLogEntry` history.
/// This is the main layout engine for the commit tree view.
enum CommitTreeGraphBuilder {
    private struct LaneToken: Hashable {
        let hash: String
        let colorIndex: Int
    }

    static func build(entries: [GitLogEntry]) -> CommitTreeGraph {
        guard !entries.isEmpty else {
            return CommitTreeGraph(rows: [], maxLaneCount: 1)
        }

        // Keep only commits present in the current list so lane math stays bounded.
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

        // Connect matching commit tokens between adjacent rows to draw lane continuity.
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
