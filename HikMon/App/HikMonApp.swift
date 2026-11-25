import SwiftUI

@main
struct HikMonApp: App {
    @StateObject private var store = DeviceStore()

    init() {
        HikLog.shared.startCapture()
        HikMonSDK.globalInit()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
