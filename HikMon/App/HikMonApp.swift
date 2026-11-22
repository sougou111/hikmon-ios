import SwiftUI

@main
struct HikMonApp: App {
    @StateObject private var store = DeviceStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
