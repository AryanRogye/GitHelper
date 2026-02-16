# BridgeDiff Architecture

This document maps the main app flow and where code now lives after the UI split.

## High-level flow

1. `DiffViewModel` owns all repository state, async Git loading, and persisted library/session data.
2. `ContentView` is the workbench shell: sidebar selection, toolbar actions, and screen switching.
3. Screen-specific rendering is delegated to focused view files:
   - Diff rendering
   - Commit log rows
   - Commit tree graph
   - Sidebar and inspector components
4. `GitService` executes Git commands, `DiffParser` converts unified diff text to structured models, and view layers render those models.

## File map

- `GitDiffHelper/GitDiffHelper/ContentView.swift`
  - Shell/orchestration only (navigation, toolbar, screen routing, reveal/zoom helpers).
- `GitDiffHelper/GitDiffHelper/Views/Sidebar/SidebarComponents.swift`
  - Sidebar search/header and selectable row styling.
- `GitDiffHelper/GitDiffHelper/Views/Inspector/InspectorComponents.swift`
  - Advanced comparison inspector and ref/path controls.
- `GitDiffHelper/GitDiffHelper/Views/CommitLog/CommitLogViews.swift`
  - Commit log row and author avatar UI.
- `GitDiffHelper/GitDiffHelper/Views/CommitTree/CommitTreeViews.swift`
  - Commit tree legend, row UI, lane canvas, and lane graph builder.
- `GitDiffHelper/GitDiffHelper/Views/Diff/DiffViews.swift`
  - File cards, hunk rows, side-by-side line grid, and bridge overlay rendering.
- `GitDiffHelper/GitDiffHelper/Styling/AppTheme.swift`
  - Shared theme colors, typography scaling, and reusable glass card styling.

## Practical editing guide

- Add/adjust data loading behavior: start in `DiffViewModel.swift`.
- Change compare/log/tree routing or toolbar behavior: `ContentView.swift`.
- Tweak visuals/spacing/colors globally: `Styling/AppTheme.swift`.
- Modify only one screen's rendering: edit the corresponding file in `Views/`.
