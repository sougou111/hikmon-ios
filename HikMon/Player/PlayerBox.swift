import SwiftUI
import UIKit
import MobileVLCKit

/// 一个播放实例（实时/回放共用）。VLC 负责 RTSP 拉流 + H.264/H.265 硬解。
final class PlayerBox: NSObject, ObservableObject {
    let player = VLCMediaPlayer()
    @Published var isPlaying = false
    @Published var failed = false
    @Published var stateText = "准备中"

    private var urlString: String?
    private var watchdog: Task<Void, Never>?

    override init() {
        super.init()
        player.delegate = self
    }

    func play(_ url: String) {
        stop()
        urlString = url
        guard let u = URL(string: url) else { failed = true; stateText = "地址不合法"; return }
        let media = VLCMedia(url: u)
        media.addOption(":network-caching=800")
        media.addOption(":clock-jitter=0")
        media.addOption(":clock-synchro=0")
        media.addOption(":rtsp-tcp")          // 弱网下 UDP 丢包严重，先走 TCP
        player.media = media
        player.play()
        stateText = "连接中"
        failed = false

        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, !Task.isCancelled, !self.isPlaying else { return }
            self.failed = true
            self.stateText = "10 秒未出画面"
        }
    }

    func stop() {
        watchdog?.cancel()
        player.stop()
        isPlaying = false
    }

    func snapshot() -> UIImage? {
        guard let drawable = player.drawable as? UIView else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: drawable.bounds)
        return renderer.image { ctx in drawable.layer.render(in: ctx.cgContext) }
    }
}

extension PlayerBox: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            switch player.state {
            case .playing:
                isPlaying = true
                failed = false
                stateText = ""
                watchdog?.cancel()
            case .error:
                failed = true
                stateText = "拉流失败（检查账号/端口/码流）"
            case .ended:
                isPlaying = false
            default:
                break
            }
        }
    }
}

/// VLC 的画面容器
struct VLCVideoView: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        player.drawable = v
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if player.drawable as? UIView !== uiView {
            player.drawable = uiView
        }
    }
}

