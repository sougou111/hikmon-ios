import Foundation

/// 与安卓 MainActivity.Dev 一一对应
struct Device: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 8000
    var user: String = "admin"
    var pass: String = ""
    var code: String = ""               // 码流加密验证码
    var talkChannel: Int = 0            // 语音通道号（0=未设置）
    var streamType: Int = 1             // 1=子码流 0=主码流
    var ipMode: Int = 0                 // 0=IPv4优先 1=仅IPv4 2=仅IPv6 3=IPv6优先
    var talkEnc: Int = 0                // 0=µ-law 1=A-law（界面不暴露，SDK 默认）
    var talkChOverride: Int = 0
    var talkMode: Int = 0               // 0=对讲+监听（界面不暴露）
    var isapiPort: Int = 80
    var favs: [Int] = []

    var key: String { "\(host):\(port):\(user)" }
    var label: String { name.isEmpty ? host : name }

    var streamTitle: String { streamType == 1 ? "子码流（省流量）" : "主码流（高清）" }

    var ipModeName: String {
        switch ipMode {
        case 1: return "仅 IPv4"
        case 2: return "仅 IPv6"
        case 3: return "IPv6 优先"
        default: return "IPv4 优先"
        }
    }

    static func normalizeHost(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = h.range(of: "^(?i)https?://", options: .regularExpression) { h.removeSubrange(r) }
        if let at = h.firstIndex(of: "@") { h = String(h[h.index(after: at)...]) }
        if let sl = h.firstIndex(of: "/") { h = String(h[..<sl]) }
        if h.hasPrefix("["), let close = h.firstIndex(of: "]") {
            h = String(h[h.index(after: h.startIndex)..<close])
        } else if h.filter({ $0 == ":" }).count == 1, let c = h.firstIndex(of: ":") {
            h = String(h[..<c])
        }
        return h.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 设备存储：**先落文件（Documents），再镜像 UserDefaults**。
/// Documents 在 App 覆盖升级时不会丢，所以自签重装同 bundle id 也能保留服务器列表。
/// 另外会把老版本（1.00 / 1.01 早期）用过的 key 全部迁移过来。
final class DeviceStore: ObservableObject {
    @Published var devices: [Device] = [] { didSet { save() } }

    private let defaultsKey = "hikmon.devices.v3"
    private let legacyKeys = ["hikmon.devices.v2", "hikmon.devices"]
    private let fileName = "hikmon-devices.json"

    private(set) var fileURL: URL
    private(set) var backupURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = dir.appendingPathComponent(fileName)
        backupURL = dir.appendingPathComponent("hikmon-devices-backup.json")
        load()
    }

    // MARK: - 读取

    private func load() {
        // 1) Documents 里的主文件（升级安装优先用这个）
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([Device].self, from: data),
           !list.isEmpty {
            devices = list
            return
        }
        // 2) 1.01 写过的 UserDefaults
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([Device].self, from: data),
           !list.isEmpty {
            devices = list
            save()
            return
        }
        // 3) 老版本（1.00 及以前）的 key / 旧字段结构
        for key in legacyKeys {
            if let data = UserDefaults.standard.data(forKey: key),
               let migrated = Self.migrateLegacy(data), !migrated.isEmpty {
                devices = migrated
                save()
                HikLog.shared.add("已从旧版本迁移 \(migrated.count) 台服务器")
                return
            }
        }
        // 4) 从备份文件恢复
        if let data = try? Data(contentsOf: backupURL),
           let list = try? JSONDecoder().decode([Device].self, from: data),
           !list.isEmpty {
            devices = list
            save()
            HikLog.shared.add("已从备份文件恢复 \(list.count) 台服务器")
        }
    }

    /// 1.00 的 Device：host/sdkPort/useSubStream/cameras，没有 favs/talkChannel
    private static func migrateLegacy(_ data: Data) -> [Device]? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var out: [Device] = []
        for o in arr {
            var d = Device()
            d.name = o["name"] as? String ?? ""
            d.host = Device.normalizeHost(o["host"] as? String ?? o["ip"] as? String ?? "")
            d.port = o["sdkPort"] as? Int ?? o["port"] as? Int ?? 8000
            d.user = o["user"] as? String ?? "admin"
            d.pass = o["pass"] as? String ?? ""
            d.code = o["code"] as? String ?? ""
            if let sub = o["useSubStream"] as? Bool { d.streamType = sub ? 1 : 0 }
            if let st = o["stream"] as? Int { d.streamType = st }
            if let mode = o["ipmode"] as? Int { d.ipMode = mode }
            if let tc = o["talk"] as? Int { d.talkChannel = tc }
            if let favs = o["favs"] as? [Int] { d.favs = favs }
            if let cams = o["cameras"] as? [[String: Any]] {
                d.favs = cams.compactMap { $0["channel"] as? Int }
            }
            guard !d.host.isEmpty else { continue }
            out.append(d)
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - 保存

    func save() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        try? data.write(to: fileURL, options: .atomic)
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    /// 备份文件（给「备份配置」分享用）
    func writeBackup() -> URL {
        if let data = try? JSONEncoder().encode(devices) {
            try? data.write(to: backupURL, options: .atomic)
        }
        return backupURL
    }

    @discardableResult
    func importBackup(from url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return false }
        if let list = try? JSONDecoder().decode([Device].self, from: data) {
            merge(list)
            return true
        }
        if let list = Self.migrateLegacy(data) {
            merge(list)
            return true
        }
        return false
    }

    /// 按 host:port:user 去重合并，不覆盖本地已有的新数据
    private func merge(_ incoming: [Device]) {
        for var d in incoming {
            if let i = devices.firstIndex(where: { $0.key == d.key }) {
                d.id = devices[i].id
                if d.favs.isEmpty { d.favs = devices[i].favs }
                devices[i] = d
            } else {
                devices.append(d)
            }
        }
    }

    // MARK: - CRUD

    func add(_ d: Device) { devices.append(d); save() }

    func update(_ d: Device) {
        if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d; save() }
    }

    func remove(id: UUID) {
        devices.removeAll { $0.id == id }
        save()
    }

    func byID(_ id: UUID?) -> Device? {
        guard let id else { return nil }
        return devices.first { $0.id == id }
    }

    func mutate(_ id: UUID, _ body: (inout Device) -> Void) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        body(&devices[i])
        save()
    }
}
