import Foundation
import UIKit

enum HikSDKInfo {
    static var available: Bool { HikMonSDK.available() }
    static var version: String { HikMonSDK.sdkVersion() }
    static var lastError: String { HikMonSDK.lastErrorText() }
}

/// 一台设备一个会话：登录一次，所有通道共用 userId
final class HikSession {
    let key: String
    private(set) var device: Device

    private(set) var userId: Int = -1
    private(set) var channelCount: Int = 16
    private(set) var channelBase: Int = 1
    private(set) var lastError: String = ""
    private(set) var lastAddr: String = ""

    private let lock = NSLock()

    init(device: Device) {
        self.device = device
        self.key = device.key
    }

    func update(_ d: Device) { device = d }

    @discardableResult
    func ensureLogin(force: Bool = false) -> Int {
        lock.lock()
        defer { lock.unlock() }

        if !force, userId >= 0 { return userId }
        if userId >= 0 {
            HikMonSDK.logout(userId)
            userId = -1
        }
        HikMonSDK.globalInit()
        if !device.code.isEmpty {
            _ = HikMonSDK.setProtectKey(device.code)
        }

        let candidates = HostResolver.candidates(device.host, mode: device.ipMode)
        if candidates.isEmpty {
            lastError = "地址为空"
            return -1
        }
        if candidates.count > 1 {
            HikLog.shared.add("解析 \(device.host) → \(candidates.joined(separator: ", "))（\(device.ipModeName)）")
        }

        var lastErr = ""
        for host in candidates {
            HikLog.shared.add("登录 \(host):\(device.port)")
            let uid = HikMonSDK.loginHost(host,
                                          port: Int32(device.port),
                                          user: device.user,
                                          password: device.pass)
            if uid >= 0 {
                userId = uid
                lastAddr = host
                let cnt = Int(HikMonSDK.channelCount(uid))
                let base = Int(HikMonSDK.channelBase(uid))
                channelCount = cnt > 0 ? cnt : 16
                channelBase = base > 0 ? base : 1
                lastError = ""
                HikLog.shared.add("登录成功 \(device.label) @\(host) userId=\(uid) 通道\(channelCount) 基址\(channelBase)")
                return userId
            }
            lastErr = HikMonSDK.lastErrorText()
            HikLog.shared.add("  失败 \(lastErr)")
        }
        lastError = lastErr
        return -1
    }

    func openLive(channel: Int, view: UIView, subStream: Bool) -> Int {
        guard userId >= 0 else { return -1 }
        return Int(HikMonSDK.startRealPlay(userId,
                                           channel: Int32(channel),
                                           subStream: subStream,
                                           view: view))
    }

    func logout() {
        lock.lock()
        defer { lock.unlock() }
        if userId >= 0 { HikMonSDK.logout(userId) }
        userId = -1
    }
}

enum HostResolver {
    /// 安卓同款策略：IPv4 优先 / 仅 IPv4 / 仅 IPv6 / IPv6 优先
    static func candidates(_ raw: String, mode: Int) -> [String] {
        let host = Device.normalizeHost(raw)
        guard !host.isEmpty else { return [] }
        if host.contains(":") { return [host] }
        if host.range(of: "^\\d{1,3}(\\.\\d{1,3}){3}$", options: .regularExpression) != nil {
            return [host]
        }
        var v4: [String] = []
        var v6: [String] = []
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, nil, &hints, &res) == 0, let head = res {
            var p: UnsafeMutablePointer<addrinfo>? = head
            while let cur = p {
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                if let sa = cur.pointee.ai_addr {
                    if sa.pointee.sa_family == sa_family_t(AF_INET) {
                        var addr = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                        if inet_ntop(AF_INET, &addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                            v4.append(String(cString: buf))
                        }
                    } else if sa.pointee.sa_family == sa_family_t(AF_INET6) {
                        var addr = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                        if inet_ntop(AF_INET6, &addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                            v6.append(String(cString: buf))
                        }
                    }
                }
                p = cur.pointee.ai_next
            }
            freeaddrinfo(head)
        }
        if v4.isEmpty && v6.isEmpty { return [host] }
        switch mode {
        case 1: return v4.isEmpty ? [host] : v4
        case 2: return v6.isEmpty ? [host] : v6
        case 3: return v6 + v4
        default: return v4 + v6
        }
    }
}

final class HikSessions {
    static let shared = HikSessions()

    private var map: [String: HikSession] = [:]
    private let lock = NSLock()

    func session(for d: Device) -> HikSession {
        lock.lock()
        defer { lock.unlock() }
        if let s = map[d.key] {
            s.update(d)
            return s
        }
        let s = HikSession(device: d)
        map[d.key] = s
        return s
    }

    func drop(for d: Device) {
        lock.lock()
        let s = map.removeValue(forKey: d.key)
        lock.unlock()
        s?.logout()
    }

    func drop(key: String) {
        lock.lock()
        let s = map.removeValue(forKey: key)
        lock.unlock()
        s?.logout()
    }

    func closeAll() {
        lock.lock()
        let all = Array(map.values)
        map.removeAll()
        lock.unlock()
        all.forEach { $0.logout() }
    }
}
