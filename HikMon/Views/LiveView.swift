import SwiftUI

// MARK: - 单个通道格

struct LiveCell: View {
    @ObservedObject var player: LivePlayer
    let title: String
    var onExpand: () -> Void

    private var showPlaceholder: Bool { player.handle < 0 }

    var body: some View {
        ZStack {
            SDKCanvasRepresentable(canvas: player.canvas)

            if showPlaceholder {
                VideoPlaceholder(text: player.status.isEmpty ? "连接中…" : player.status)
            }

            VStack {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                    Spacer()
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                Spacer()
            }
            .padding(5)
        }
        .background(Color.black)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear { player.start() }
        .onDisappear { player.stop() }
    }
}

// MARK: - 2×2 网格

struct LiveView: View {
    let device: Device

    @StateObject private var grid: LiveGrid
    @State private var page = 0
    @State private var full: ChannelSelection?
    @State private var showPlayback = false
    @State private var showSettings = false

    init(device: Device) {
        self.device = device
        _grid = StateObject(wrappedValue: LiveGrid(device: device))
    }

    private var pageCount: Int { max(1, (grid.players.count + 3) / 4) }

    private var pagePlayers: [LivePlayer] {
        let start = page * 4
        guard start < grid.players.count else { return [] }
        return Array(grid.players[start..<min(start + 4, grid.players.count)])
    }

    var body: some View {
        VStack(spacing: 6) {
            if !HikSDKInfo.available {
                banner("HCNetSDK 未编译进来（HAS_HIKSDK=0），出不了画面")
            } else if grid.players.isEmpty {
                banner("这台设备没配置通道")
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4)],
                      spacing: 4) {
                ForEach(pagePlayers) { p in
                    LiveCell(player: p,
                             title: "\(device.streamTitle(p.channel)) \(device.name(for: p.channel))") {
                        p.stop()
                        full = ChannelSelection(id: p.channel)
                    }
                }
            }
            .padding(.horizontal, 4)

            if pageCount > 1 {
                HStack(spacing: 20) {
                    Button {
                        page = max(0, page - 1)
                    } label: { Image(systemName: "chevron.left") }
                        .disabled(page == 0)

                    Text("\(page + 1) / \(pageCount)")
                        .font(.caption)
                        .monospacedDigit()

                    Button {
                        page = min(pageCount - 1, page + 1)
                    } label: { Image(systemName: "chevron.right") }
                        .disabled(page >= pageCount - 1)
                }
                .padding(.vertical, 6)
            }

            Spacer(minLength: 0)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle(device.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showPlayback = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                Button {
                    pagePlayers.forEach { $0.restart() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .fullScreenCover(item: $full, onDismiss: {
            pagePlayers.forEach { $0.start() }
        }) { sel in
            SingleChannelView(device: device, channel: sel.id)
        }
        .sheet(isPresented: $showPlayback) {
            PlaybackView(device: device)
        }
        .onDisappear {
            grid.players.forEach { $0.stop() }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(Color.orange.opacity(0.15))
    }
}

struct ChannelSelection: Identifiable {
    let id: Int
}
