# BridgeDiff

BridgeDiff is a native macOS Git diff workbench built with SwiftUI.

It is designed to make code-review diffs easier to scan by combining:
- a familiar side-by-side unified-diff layout
- line-level metadata (line numbers, markers, hunks)
- curved bridge overlays that visually connect related deletion and insertion blocks

## What This App Is

BridgeDiff is a **read-focused diff viewer** for local Git repositories.

It helps you answer:
- What changed?
- Where did code likely move or get rewritten?
- Which files and hunks matter most in this comparison?

It is not trying to replace full Git clients. It is focused on high-signal visual review.

## Core Features

- Native macOS UI (SwiftUI + AppKit integrations).
- Compare modes:
  - `Working Changes` (`git diff`)
  - `Recent Commit` (`HEAD~1` vs `HEAD`)
  - `Compare Branch` (selected ref vs `HEAD`)
  - `Custom Compare` (base/head refs + optional path filter)
- Repository library with recent comparison sessions.
- Searchable repository sidebar with status summaries.
- Sticky file headers while scrolling.
- Focused hunk highlighting so one change block can be emphasized.
- Curved bridge visualization between delete/add regions inside a hunk.
- Large-diff performance guardrails:
  - background parsing
  - progressive file/hunk rendering
  - selective bridge-overlay rendering for very large hunks

## What It Does Not Do

- No staging/commit/push operations.
- No merge conflict resolution UI.
- No inline code editing.
- No semantic AST diffing (diff parsing is line-based unified diff).

## How It Works

1. BridgeDiff runs local `git` commands in the selected repository.
2. Raw unified diff output is parsed into:
   - files
   - hunks
   - rows (context/add/delete/meta)
3. For each hunk, delete/add runs are grouped into bridge candidates.
4. The app renders side-by-side code lanes, gutter metadata, and optional bridge overlays.

## Privacy and Data

- All diffing is done locally via your installed `git`.
- BridgeDiff does not require network access to inspect diffs.
- Repository library/session metadata is stored in `UserDefaults`.
- When folders are chosen via file picker, security-scoped bookmarks are used for future access.

## Requirements

- macOS
- Xcode (to run the app project)
- Git installed and available in `PATH`

## Run

1. Open `GitDiffHelper/GitDiffHelper.xcodeproj` in Xcode.
2. Select the `GitDiffHelper` scheme.
3. Press `Cmd+R`.

## Quick Start

1. Click `Choose Repository` and select a project root folder.
2. Start with `Working Changes`.
3. Use `Recent Commit` for quick commit-to-commit review.
4. Use `Compare Branch` or `Custom Compare` for targeted analysis.
5. Click a hunk to focus its bridges and reduce visual noise.

## Project Structure

- `GitDiffHelper/GitDiffHelper/ContentView.swift`: main UI and interaction layout.
- `GitDiffHelper/GitDiffHelper/DiffViewModel.swift`: state, loading, compare actions, repository/session library.
- `GitDiffHelper/GitDiffHelper/GitService.swift`: local Git command execution and validation.
- `GitDiffHelper/GitDiffHelper/DiffParser.swift`: unified diff parsing + bridge-group construction.
- `GitDiffHelper/GitDiffHelper/DiffModels.swift`: diff and repository data models.
