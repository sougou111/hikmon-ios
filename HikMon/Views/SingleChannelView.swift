import SwiftUI

/// 单通道全屏：SDK 直渲染 + 双指缩放(1–4×)/单指拖动/双击复位 + 静音 + 按住说话
struct SingleChannelView: View {
    let device: Device
    let channel: Int

    @Environment(\.dismiss) private var dismiss
    @StateObject private var player: LivePlayer
    @State private var showControls = true

    init(device: Device, channel: Int) {
        self.device = device
        self.channel = channel
        _player = StateObject(wrappedValue: LivePlayer(device: device, channel: channel))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SDKCanvasRepresentable(canvas: player.canvas)
                .ignoresSafeArea()

            if player.handle < 0 {
                VideoPlaceholder(text: player.status.isEmpty ? "连接中…" : player.status)
                    .ignoresSafeArea()
            }

            if showControls {
                controls
            }
        }
        .statusBarHidden()
        .onAppear {
            player.canvas.onSingleTap = {
                withAnimation(.easeInOut(duration: 0.15)) { showControls.toggle() }
            }
            player.start()
        }
        .onDisappear {
            player.canvas.onSingleTap = nil
            player.stop()
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }

                Spacer()

                Text("CH\(channel) · \(device.title)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())

                Spacer()

                Button {
                    player.toggleSound()
                } label: {
                    Image(systemName: player.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(player.soundOn ? Color.green : Color.white)
                        .padding(10)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 10) {
                if !player.status.isEmpty {
                    Text(player.status)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Button {
                        player.canvas.resetZoom()
                    } label: {
                        Label("1×", systemImage: "1.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                    }

                    talkButton

                    Button {
                        player.restart()
                    } label: {
                        Label("重连", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.bottom, 26)
        }
    }

    private var talkButton: some View {
        Text(player.talking ? "松开发送中…" : "按住说话")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(player.talking ? Color.red.opacity(0.8) : Color.black.opacity(0.5))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !player.talking { player.startTalk() }
                    }
                    .onEnded { _ in
                        player.stopTalk()
                    }
            )
    }
}
