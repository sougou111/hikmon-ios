import SwiftUI

struct LivePage: View {
    @EnvironmentObject private var store: DeviceStore
    @ObservedObject var state: AppState

    var body: some View {
        if let d = store.byID(state.liveDev) {
            LiveContent(device: d, channel: state.liveChannel, state: state)
                .id("\(d.id.uuidString)-\(state.liveChannel)")
        } else {
            EmptyHint(text: "设备不存在")
        }
    }
}

private struct LiveContent: View {
    let device: Device
    let channel: Int
    @ObservedObject var state: AppState

    @StateObject private var cell: LiveCell
    @State private var pressing = false

    init(device: Device, channel: Int, state: AppState) {
        self.device = device
        self.channel = channel
        self.state = state
        _cell = StateObject(wrappedValue: LiveCell(device: device,
                                                   channel: channel,
                                                   tip: "连接中…",
                                                   sound: true,
                                                   autoStart: true,
                                                   interactive: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VideoPane(canvas: cell.canvas, tip: cell.live ? "" : cell.tip)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .padding(.horizontal, 10)

            Text("\(device.label) · 通道 \(channel)")
                .font(.system(size: 12))
                .foregroundStyle(C.sub)
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                Button { toggleMute() } label: {
                    Chip(text: state.liveMuted ? "🔇 取消静音" : "🔊 静音", primary: state.liveMuted, stretch: true)
                }
                .buttonStyle(.plain)

                Button {
                    state.playDev = device.id
                    state.playChannel = channel
                    state.pbTime = Date()
                    stopAll()
                    state.go(.playback)
                } label: {
                    Chip(text: "回放", stretch: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 6)

            // 按住说话
            Text(pressing ? "松手结束" : "按住说话")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(pressing ? Color(hex: 0x2A63C8) : C.accent)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !pressing else { return }
                            pressing = true
                            startTalk()
                        }
                        .onEnded { _ in
                            pressing = false
                            stopTalk()
                        }
                )
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 6)

            Text("按住按钮说话，松手停止（设备需要有喇叭才能听到）")
                .font(.system(size: 11))
                .foregroundStyle(C.faint)
                .padding(.horizontal, 6)

            Spacer(minLength: 0)
        }
        .onAppear {
            HikLog.shared.add("进入单通道 ch\(channel)")
        }
        .onDisappear {
            stopAll()
        }
    }

    private func toggleMute() {
        state.liveMuted.toggle()
        if state.liveMuted {
            _ = HikMonSDK.closeSound()
            HikLog.shared.add("预览声音 → 静音")
        } else {
            if cell.handle >= 0 { _ = HikMonSDK.openSound(cell.handle) }
            HikLog.shared.add("预览声音 → 开声")
        }
    }

    private func startTalk() {
        // 先停掉旧的监听，再按当前通道开对讲
        TalkEngine.shared.stop()
        var d = device
        d.talkMode = 0
        let ok = TalkEngine.shared.start(device: d, channel: channel, send: true)
        state.show(ok ? "对讲已开启" : "对讲失败")
    }

    private func stopTalk() {
        TalkEngine.shared.stop()
    }

    private func stopAll() {
        TalkEngine.shared.stop()
        cell.stop()
        if state.liveMuted {
            state.liveMuted = false
            _ = HikMonSDK.closeSound()
        }
    }
}


