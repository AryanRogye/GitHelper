//
//  GitDiffHelperApp.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 2/14/26.
//

import SwiftUI
import AppKit

@main
struct GitDiffHelperApp: App {
    @StateObject private var model = DiffViewModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup("BridgeDiff") {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1360, height: 860)
    }
}
