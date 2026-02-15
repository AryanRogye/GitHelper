import SwiftUI

@main
struct BridgeDiffNativeApp: App {
    @StateObject private var model = DiffViewModel()

    var body: some Scene {
        WindowGroup("BridgeDiff Native") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 720)
        }
    }
}
