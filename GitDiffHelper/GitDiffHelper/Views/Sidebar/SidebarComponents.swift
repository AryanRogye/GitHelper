import SwiftUI

/*
 Sidebar composition (used in ContentView's left navigation pane):

 ContentView sidebar List
 +-- SidebarSearchField
 +-- SidebarSectionHeader
 +-- row.sidebarSelectableRow(isSelected:)
     +-- SidebarSelectableRowModifier
*/

/// Search field shown at the top of the repository sidebar.
/// Used in `ContentView` before repository rows.
struct SidebarSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(NativeTheme.readableSecondary)
                .frame(width: 14, height: 14)

            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NativeTheme.sidebarSearchBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NativeTheme.sidebarSearchBorder, lineWidth: 1)
        )
    }
}

/// Small section title style for sidebar list sections.
/// Used for labels like "Repository Library".
struct SidebarSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(NativeTheme.readableSecondary)
            .textCase(nil)
    }
}

/// Shared row treatment for hover + selected visual state in the sidebar.
/// Applied via `View.sidebarSelectableRow(isSelected:)`.
struct SidebarSelectableRowModifier: ViewModifier {
    let isSelected: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(backgroundFill)
            .overlay(selectionStroke)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var backgroundFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isSelected
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                    : (isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.10) : Color.clear)
            )
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                isSelected ? Color.accentColor.opacity(0.24) : Color.clear,
                lineWidth: 1
            )
    }
}

extension View {
    /// Applies the standard selectable repository row styling in the sidebar.
    func sidebarSelectableRow(isSelected: Bool) -> some View {
        modifier(SidebarSelectableRowModifier(isSelected: isSelected))
    }
}
