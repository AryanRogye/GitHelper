import SwiftUI

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
