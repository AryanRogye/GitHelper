# Startup And Launch Sanity Checklist

Use this before shipping a production build.

## Launch Safety

- [ ] App launches from Xcode (Debug) without crash.
- [ ] App launches standalone from `Release` build output.
- [ ] App can cold-launch with no repository selected.
- [ ] App can relaunch after previous session state exists in `UserDefaults`.

## Repository Selection

- [ ] Selecting a valid Git repo succeeds.
- [ ] Selecting a non-Git folder shows a friendly error and does not crash.
- [ ] Security-scoped folder access still works after relaunch.

## Diff Flows

- [ ] `Working Changes` renders expected files.
- [ ] `Recent Commit` (`HEAD~1` -> `HEAD`) renders expected files.
- [ ] `Compare Branch` works for at least one branch.
- [ ] `Custom Compare` handles valid refs and invalid refs safely.

## Performance And Stability

- [ ] Large diff can scroll without freeze/crash.
- [ ] Loading indicator appears during heavy parse.
- [ ] No repeated crash when switching repos rapidly.

## Visual Regression Quick Check

- [ ] App is dark mode only as intended.
- [ ] Sidebar selection/hover states remain legible.
- [ ] Active file and focused hunk states are visible.
- [ ] Red/green diff colors remain readable and not over-saturated.

## Final Release Gate

- [ ] `xcodebuild -configuration Release build` passes.
- [ ] `xcodebuild test` passes.
- [ ] No high-priority runtime crash in local smoke testing.
