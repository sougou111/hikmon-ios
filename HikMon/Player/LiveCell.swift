import Foundation
import UIKit
import SwiftUI

/// 一格画面（网格里的一格 / 单通道页的整屏），对应安卓的 Cell
final class LiveCell: ObservableObject, Identifiable {
    let id = UUID()
    let device: Device
    private(set) var channel: Int
    let canvas = SDKCanvasView()

    @Published private(set) var tip: String
    @Published private(set) var live = false

    private(set) var handle: Int = -1
    private var started = false
    private let withSound: Bool
    private let autoStart: Bool

    init(device: Device, channel: Int, tip: String, sound: Bool, autoStart: Bool = false) {
        self.device = device
        self.channel = channel
        self.tip = tip
        self.withSound = sound
        self.autoStart = autoStart
        self.canvas.onAttach = { [weak self] in
            guard let self, self.autoStart else { return }
            self.start()
        }
    }

    func setChannel(_ ch: Int, tip: String) {
        channel = ch
        self.tip = tip
    }

    func start() {
        guard !started, channel > 0 else { return }
        started = true
        tip = "连接中…"
        let session = HikSessions.shared.session(for: device)
        let ch = channel
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard session.ensureLogin() >= 0 else {
                DispatchQueue.main.async { self.tip = "登录失败"; self.started = false }
                return
            }
            DispatchQueue.main.async {
                guard self.started else { return }
                let h = session.openLive(channel: ch, view: self.canvas.renderView,
                                         subStream: self.device.streamType == 1)
                if h >= 0 {
                    self.handle = h
                    self.live = true
                    self.tip = ""
                    HikLog.shared.add("通道 \(ch) 播放 handle=\(h)")
                    _ = HikMonSDK.makeKeyFrame(session.userId, channel: Int32(ch))
                    if self.withSound { _ = HikMonSDK.openSound(h) }
                } else {
                    self.started = false
                    self.live = false
                    self.tip = "通道 \(ch)\nerr=\(HikMonSDK.lastErrorText())"
                    HikLog.shared.add("通道 \(ch) 失败 \(HikMonSDK.lastErrorText())")
                }
            }
        }
    }

    func stop() {
        started = false
        live = false
        if handle >= 0 {
            let h = handle
            handle = -1
            DispatchQueue.global(qos: .utility).async {
                HikMonSDK.stopRealPlay(h)
            }
        }
    }

    func restart() {
        stop()
        started = false
        start()
    }
}

/// 一台设备首页那一块：标题 + 2×2 网格
final class DeviceBlock: ObservableObject, Identifiable {
    let id: UUID
    let device: Device
    @Published var cells: [LiveCell] = []

    init(device: Device) {
        self.id = device.id
        self.device = device
        rebuild()
    }

    func rebuild() {
        for c in cells { c.stop() }
        cells = (0..<4).map { i in
            let ch = i < device.favs.count ? device.favs[i] : 0
            return LiveCell(device: device,
                            channel: ch,
                            tip: ch == 0 ? "未收藏\n通道" : "通道 \(ch)",
                            sound: false,
                            autoStart: ch > 0)
        }
    }

    func startAll() {
        for c in cells where c.channel > 0 { c.start() }
    }

    func stopAll() {
        for c in cells { c.stop() }
    }
}
