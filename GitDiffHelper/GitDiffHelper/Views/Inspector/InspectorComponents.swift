import SwiftUI

/*
 Advanced compare + toolbar component map:

 ContentView (diff mode)
 +-- AdvancedCompareInspector
 |   +-- RefInputField (base/head)
 |   +-- LabeledField (path filter)
 |
 +-- Toolbar buttons use ToolbarSymbolLabel
 +-- Top status panel uses StatusChip
*/

/// Right-side panel for custom compare inputs (base/head refs + optional path filter).
/// Appears when `ContentView` toggles advanced inspector in diff mode.
struct AdvancedCompareInspector: View {
    @ObservedObject var model: DiffViewModel
    let onClose: () -> Void

    private var selectableRefs: [String] {
        model.availableBranchRefs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Custom Compare")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NativeTheme.readableSecondary)
                }
                .buttonStyle(.plain)
                .help("Close compare inspector")
            }

            Text("Supports branch names and commit hashes (for example: 2d8b243 or cfb646e).")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(NativeTheme.readableSecondary)

            VStack(alignment: .leading, spacing: 10) {
                RefInputField(
                    label: "Base ref",
                    placeholder: "HEAD~1 or 2d8b243",
                    text: $model.baseRef,
                    refs: selectableRefs
                )
                RefInputField(
                    label: "Head ref",
                    placeholder: "HEAD or cfb646e",
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
                    }
                }
                .buttonStyle(.glassProminent)

                Button("Close") {
                    onClose()
                }
                .buttonStyle(.glass)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }
}

/// Compact label used for toolbar buttons across screens.
/// Keeps icon/title alignment consistent.
struct ToolbarSymbolLabel: View {
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

/// Ref selector field used by the advanced inspector.
/// Supports free text plus quick picks from discovered refs.
struct RefInputField: View {
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

/// Generic labeled text field used for path filter input in the advanced inspector.
struct LabeledField: View {
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

/// Reusable status capsule used in the top glass panel.
/// Displays one status line with optional error coloring.
struct StatusChip: View {
    let title: String
    let value: String
    let id: String
    let namespace: Namespace.ID
    var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(NativeTheme.readableSecondary)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isError ? Color.red : Color.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(.regular.interactive(), in: Capsule())
        .glassEffectID(id, in: namespace)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
