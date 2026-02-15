# BridgeDiff

BridgeDiff is a native macOS app that helps you understand code changes fast.

It turns raw Git diffs into a visual review workspace so you can quickly answer:
- What changed?
- Where did code move?
- Which files matter most right now?

If you are new to Git tooling, this is made for you. Pick a repo, click a compare mode, and start reviewing.

## Why This Feels Different

BridgeDiff is built for reading changes, not managing Git operations.

- Side-by-side diff lanes with line numbers and clear add/delete markers
- Curved bridge overlays that connect related removed and added blocks
- Sticky file headers and focused-hunk mode so big diffs stay readable
- Commit log screen with branch filtering
- Menu bar quick panel for instant access to working-tree changes

## No GitHub Required

You do not need GitHub to use BridgeDiff.

- Works with any local Git repository
- Runs local `git` commands on your machine
- Can be used offline for diff and log workflows
- Does not require pushing code anywhere

## Quick Start (2 Minutes)

1. Open `GitDiffHelper/GitDiffHelper.xcodeproj` in Xcode.
2. Select the `GitDiffHelper` scheme.
3. Press `Cmd+R`.
4. In BridgeDiff, click `Choose Repository` and pick your project folder.
5. Click `Working Changes` to see uncommitted edits immediately.

## Main Workflows

### 1) Diff Workbench

Use the toolbar to switch comparisons:

- `Working Changes`: shows staged + unstaged edits
- `Recent Commit`: compares `HEAD~1` to `HEAD`
- `Compare Branch`: compares selected branch to your current state
- `Compare Commit`: compare current state to a past commit, or compare two commits
- `Custom Compare`: type base/head refs and optional path filter

Inside the diff view:
- Click any hunk to focus it and reduce visual noise
- Scroll large changes progressively (files and hunks are loaded in batches)
- Use sticky file headers to keep context while scrolling

### 2) Commit Log Screen

Switch from `Diff` to `Commit Log` using the top segmented control.

- View commit subject, author, time, and decorations
- Filter history to `All Branches` or a specific branch/ref
- Refresh log without leaving the screen

### 3) Menu Bar Panel

BridgeDiff includes a menu bar window for fast check-ins.

- See current repository at a glance
- See working-tree file changes with status codes
- Click a changed file to open the main window and jump to that file in the diff

### 4) Repository Library + Session Recall

BridgeDiff remembers your recent repositories and comparisons.

- Search saved repositories in the sidebar
- Re-open recent comparison sessions per repository
- Session cards show file/hunk/bridge counts for quick context

## Keyboard Shortcuts

- `Cmd + +`: Zoom in diff text
- `Cmd + -`: Zoom out diff text
- `Cmd + 0`: Reset diff text zoom

## What BridgeDiff Does Not Do

BridgeDiff is intentionally read-focused.

- No staging, committing, pushing, or branch management
- No merge conflict resolution UI
- No inline file editing
- No semantic/AST diff engine (line-based unified diff parsing)

## Requirements

- macOS
- Xcode
- Git installed and available in `PATH`

## Build And Test From Terminal

```bash
cd /path/to/GitDiffTool
xcodebuild -project GitDiffHelper/GitDiffHelper.xcodeproj -scheme GitDiffHelper build
xcodebuild -project GitDiffHelper/GitDiffHelper.xcodeproj -scheme GitDiffHelper test
```

## Privacy And Local Data

- Diffing and history loading run through local `git` commands.
- Repository library/session metadata is stored locally in `UserDefaults`.
- Folder access is persisted with security-scoped bookmarks.
- Commit author avatar images are cached locally in your macOS cache directory.

## Project Layout

- `GitDiffHelper/GitDiffHelper/ContentView.swift`: main UI and workflows
- `GitDiffHelper/GitDiffHelper/DiffViewModel.swift`: state, loading, compare actions, session library
- `GitDiffHelper/GitDiffHelper/GitService.swift`: Git command execution and validation
- `GitDiffHelper/GitDiffHelper/DiffParser.swift`: unified diff parser and bridge grouping
- `GitDiffHelper/GitDiffHelper/GitDiffHelperApp.swift`: app entry, commands, menu bar extra

## Sanity Checklist

Before shipping, use:

- `docs/STARTUP_SANITY_CHECKLIST.md`
