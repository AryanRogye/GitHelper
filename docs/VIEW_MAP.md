# Views Folder Map

Use this file as a quick index before opening individual view files.

## Top-level map

ContentView routes into one of three screens:

- Diff screen -> `GitDiffHelper/GitDiffHelper/Views/Diff/DiffViews.swift`
- Commit log screen -> `GitDiffHelper/GitDiffHelper/Views/CommitLog/CommitLogViews.swift`
- Commit tree screen -> `GitDiffHelper/GitDiffHelper/Views/CommitTree/CommitTreeViews.swift`

Shared UI pieces:

- Sidebar controls -> `GitDiffHelper/GitDiffHelper/Views/Sidebar/SidebarComponents.swift`
- Advanced compare inspector + toolbar chips -> `GitDiffHelper/GitDiffHelper/Views/Inspector/InspectorComponents.swift`

## Visual hierarchy (quick)

Diff:

ContentView.diffArea
+-- DiffFileStickyHeader
+-- DiffFileCard
    +-- HunkView
        +-- HunkRowsChunkView
            +-- DiffLineRow
                +-- SideGridCell
                +-- GutterGridCell
        +-- BridgeOverlay

Commit tree:

ContentView.commitTreeArea
+-- CommitTreeLegendCard
+-- CommitTreeGraphList
    +-- CommitTreeGraphRowView
        +-- CommitTreeLaneCanvas

Commit log:

ContentView.commitLogArea
+-- CommitLogRow
    +-- CommitAuthorAvatarView
