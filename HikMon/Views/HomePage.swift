import SwiftUI

struct HomePage: View {
    @EnvironmentObject private var store: DeviceStore
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            if store.devices.isEmpty {
                EmptyHint(text: "还没有添加设备\n点左上角「设备管理」→ 添加服务器")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.devices) { d in
                            DeviceCard(device: d, state: state, paused: state.livePaused)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
            }
        }
        .onAppear(perform: ensureDefaults)
    }

    /// 安卓登录成功时会给空收藏的设备默认收藏前 4 路，这里保持一致
    private func ensureDefaults() {
        for d in store.devices where d.favs.isEmpty {
            let session = HikSessions.shared.session(for: d)
            DispatchQueue.global(qos: .utility).async {
                guard session.ensureLogin() >= 0 else { return }
                DispatchQueue.main.async {
                    guard let cur = store.byID(d.id), cur.favs.isEmpty else { return }
                    var nd = cur
                    for i in 0..<min(4, session.channelCount) {
                        nd.favs.append(session.channelBase + i)
                    }
                    store.update(nd)
                    HikLog.shared.add("默认收藏 4 路通道")
                }
            }
        }
    }
}

private struct DeviceCard: View {
    let device: Device
    @ObservedObject var state: AppState
    var paused: Bool

    @EnvironmentObject private var store: DeviceStore
    @StateObject private var block: DeviceBlock

    init(device: Device, state: AppState, paused: Bool) {
        self.device = device
        self.state = state
        self.paused = paused
        _block = StateObject(wrappedValue: DeviceBlock(device: device))
    }

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(block.cells.enumerated()), id: \.element.id) { idx, cell in
                    CellView(cell: cell,
                             showFull: cell.channel > 0,
                             onFull: { openLive(cell.channel) },
                             onTap: { if cell.channel > 0 { openLive(cell.channel) } },
                             onLong: { if cell.channel > 0 { openPlayback(cell.channel) } })
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .id("\(device.id)-\(idx)-\(cell.channel)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(C.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(C.stroke, lineWidth: 1)
                )
        )
        .onAppear { if !paused { block.startAll() } }
        .onDisappear { block.stopAll() }
        .onChange(of: paused) { p in
            if p { block.stopAll() } else { block.startAll() }
        }
        .onChange(of: device.favs) { _ in
            block.rebuild()
            if !paused { block.startAll() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.label)
                    .font(.system(size: 15))
                    .foregroundStyle(C.text)
                Text(subLine)
                    .font(.system(size: 10))
                    .foregroundStyle(C.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ChipButton(text: "通道管理") {
                state.channelDev = device.id
                state.go(.channels)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var subLine: String {
        var s = "\(device.host):\(device.port) · 收藏 \(device.favs.count) 路"
        if device.talkChannel > 0 { s += " · 语音通道 \(device.talkChannel)" }
        return s
    }

    private func openLive(_ ch: Int) {
        state.liveDev = device.id
        state.liveChannel = ch
        state.go(.live)
    }

    private func openPlayback(_ ch: Int) {
        state.playDev = device.id
        state.playChannel = ch
        state.pbTime = Date()
        state.go(.playback)
    }
}
