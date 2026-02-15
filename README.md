# BridgeDiff

A native macOS SwiftUI Git diff GUI with curved bridge connectors between deletion and insertion regions.

## Run

```bash
swift run
```

This launches a real desktop window (`BridgeDiff Native`).

## Usage

1. Click `Choose Repository Folder` and select your project root folder.
2. Click `Show Uncommitted Changes` for the easiest default diff view.
3. Optionally click `Compare Last Commit` for `HEAD~1` vs `HEAD`.
4. Use `Advanced Compare Options` only if you need custom refs or a path filter.
5. Use `Render Sample` if you want to preview the UI without loading Git data.

## Notes

- The app reads diffs by executing local `git diff` in the selected repo path.
- Curved bridges are drawn only when a hunk has both deleted (`-`) and added (`+`) lines in the same change block.
