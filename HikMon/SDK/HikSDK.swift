import Foundation
import UIKit

// MARK: - SDK 元信息

enum HikSDKInfo {
    static var available: Bool { HikMonSDK.available() }
    static var version: String { HikMonSDK.sdkVersion() }
    static var lastError: String { HikMonSDK.lastErrorText() }
}

// MARK: - 单设备会话（登录一次，多通道复用）

final class HikSession {
    let device: Device

    private(set) var userId: Int = -1
    private(set) var serverChannelCount: Int = 0
    private(set) var lastError: String = ""

    /// 4 宫格会并发的调 ensureLogin，这里串行化，避免同一设备重复登录
    private let loginLock = NSLock()

    init(device: Device) { self.device = device }

    var isLoggedIn: Bool { userId >= 0 }

    /// 登录（幂等）。forceRelogin = true 时先登出再登。
    @discardableResult
    func ensureLogin(forceRelogin: Bool = false) -> Bool {
        loginLock.lock()
        defer { loginLock.unlock() }

        if !forceRelogin, userId >= 0 { return true }
        if userId >= 0 {
            HikMonSDK.logout(userId)
            userId = -1
        }
        HikMonSDK.globalInit()

        var host = device.host
        if device.resolveMode == .localDNS, let ip = HikMonSDK.resolveHost(device.host) {
            host = ip
        }

        let uid = HikMonSDK.loginHost(host,
                                      port: Int32(device.sdkPort),
                                      user: device.user,
                                      password: device.pass)
        guard uid >= 0 else {
            lastError = HikMonSDK.lastErrorText()
            return false
        }
        userId = uid
        let n = Int(HikMonSDK.channelCount(uid))
        if n > 0 { serverChannelCount = n }
        lastError = ""
        return true
    }

    func logout() {
        if userId >= 0 { HikMonSDK.logout(userId) }
        userId = -1
    }

    /// 开一路实时预览，返回 realplay 句柄
    func openLive(channel: Int, view: UIView) -> Int {
        guard userId >= 0 else { return -1 }
        return Int(HikMonSDK.startRealPlay(userId,
                                           channel: Int32(channel),
                                           subStream: device.useSubStream,
                                           view: view))
    }
}

// MARK: - 会话池（同一设备只登录一次）

final class HikSessions {
    static let shared = HikSessions()

    private var map: [String: HikSession] = [:]
    private let lock = NSLock()

    private func key(_ d: Device) -> String {
        "\(d.host)|\(d.sdkPort)|\(d.user)|\(d.pass)|\(d.resolveMode.rawValue)"
    }

    func session(for device: Device) -> HikSession {
        lock.lock()
        defer { lock.unlock() }
        if let s = map[key(device)] { return s }
        let s = HikSession(device: device)
        map[key(device)] = s
        return s
    }

    func drop(for device: Device) {
        lock.lock()
        let k = key(device)
        let s = map.removeValue(forKey: k)
        lock.unlock()
        s?.logout()
    }

    func closeAll() {
        lock.lock()
        let all = map.values
        map.removeAll()
        lock.unlock()
        all.forEach { $0.logout() }
    }
}
