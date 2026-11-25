import SwiftUI

@main
struct HikMonApp: App {
    @StateObject private var store = DeviceStore()

    init() {
        HikLog.shared.startCapture()
        HikMonSDK.globalInit()
        HikLog.shared.add("瑞丰监控 iOS v1.01 启动")
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(store)
        }
    }
}
