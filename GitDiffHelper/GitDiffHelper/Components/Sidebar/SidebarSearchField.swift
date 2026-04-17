//
//  SidebarSearchField.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 4/16/26.
//

import SwiftUI

/// Search field shown at the top of the repository sidebar.
/// Used in `ContentView` before repository rows.
struct SidebarSearchField: View {
    @Binding var text: String
    
    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

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
        .padding(.vertical, 8)
        .background(
            shape
                .fill(NativeTheme.sidebarSearchBackground)
        )
        .overlay(
            shape
                .stroke(NativeTheme.sidebarSearchBorder, lineWidth: 1)
        )
    }
}
