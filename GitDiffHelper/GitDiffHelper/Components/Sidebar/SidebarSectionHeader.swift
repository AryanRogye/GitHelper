//
//  SidebarSectionHeader.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 4/16/26.
//

import SwiftUI

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
