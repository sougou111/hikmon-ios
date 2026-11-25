import SwiftUI

enum AppPage: Equatable {
    case home, devices, channels, diag, logs, live, settings, playback
}

/// 对标安卓 MainActivity 里的 page / channelDev / playDev / liveChannel …
final class AppState: ObservableObject {
    @Published var page: AppPage = .home

    @Published var livePaused = false
    @Published var liveMuted = false

    @Published var channelDev: UUID?
    @Published var playDev: UUID?
    @Published var diagDev: UUID?
    @Published var settingsDev: UUID?
    @Published var liveDev: UUID?

    @Published var liveChannel: Int = 1
    @Published var playChannel: Int = 1
    @Published var pbTime: Date = Date()

    @Published var showAddForm = false
    @Published var editID: UUID?

    @Published var toast: String?
    private var toastWork: DispatchWorkItem?

    func show(_ s: String) {
        toastWork?.cancel()
        toast = s
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) { self?.toast = nil }
        }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: w)
    }

    func go(_ p: AppPage) {
        page = p
        HikLog.shared.add("页面 → \(p)")
    }
}

struct AppShell: View {
    @EnvironmentObject private var store: DeviceStore
    @StateObject private var state = AppState()


    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(C.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) {
            if let t = state.toast {
                Text(t)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 60)
                    .transition(.opacity)
            }
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 0) {
            ChipButton(text: leftTitle) { leftAction() }

            VStack(alignment: .leading, spacing: 1) {
                Text("监控")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(C.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(C.sub)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.page == .home {
                ChipButton(text: state.livePaused ? "▶ 播放" : "⏸ 暂停") {
                    state.livePaused.toggle()
                    if state.livePaused {
                        HikLog.shared.add("已暂停全部预览")
                    } else {
                        HikLog.shared.add("恢复预览")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var leftTitle: String {
        switch state.page {
        case .home: return "设备管理"
        case .devices, .channels, .live: return "返回首页"
        case .settings: return "返回设备"
        case .logs: return "返回设备"
        case .diag, .playback: return "返回"
        }
    }

    private func leftAction() {
        switch state.page {
        case .home:  state.go(.devices)
        case .devices, .channels, .live: state.go(.home)
        case .settings: state.go(.devices)
        case .diag: state.go(.devices)
        case .logs: state.go(.devices)
        case .playback: state.go(.home)
        }
    }

    private var subtitle: String {
        switch state.page {
        case .home:
            return store.devices.isEmpty ? "还没有设备，点左上角「设备管理」添加"
                                         : "\(store.devices.count) 台设备"
        case .devices:
            return "服务器管理"
        case .channels:
            let d = store.byID(state.channelDev)
            return "\(d?.label ?? "") · 每页 6 路，左右滑动"
        case .live:
            let d = store.byID(state.liveDev)
            return "\(d?.label ?? "") · 通道 \(state.liveChannel) · 实时预览"
        case .playback:
            let d = store.byID(state.playDev)
            return "\(d?.label ?? "") · 通道 \(state.playChannel) · 回放"
        case .settings:
            let d = store.byID(state.settingsDev)
            return "\(d?.label ?? "") · 设置"
        case .diag:
            let d = store.byID(state.diagDev)
            return "\(d?.label ?? "") · 设备诊断（只读）"
        case .logs:
            return "运行日志（可复制）"
        }
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch state.page {
        case .home:      HomePage(state: state)
        case .devices:   DevicesPage(state: state)
        case .channels:  ChannelsPage(state: state)
        case .live:      LivePage(state: state)
        case .playback:  PlaybackPage(state: state)
        case .settings:  SettingsPage(state: state)
        case .diag:      DiagPage(state: state)
        case .logs:      LogsPage()
        }
    }

    // MARK: 底部不再显示日志；日志在「设备管理 → 日志记录」里看
}


