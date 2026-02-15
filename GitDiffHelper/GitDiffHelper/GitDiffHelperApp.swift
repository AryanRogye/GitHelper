//
//  GitDiffHelperApp.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 2/14/26.
//

import SwiftUI

@main
struct GitDiffHelperApp: App {
    @StateObject private var model = DiffViewModel()

    var body: some Scene {
        WindowGroup("BridgeDiff") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1360, height: 860)
    }
}
