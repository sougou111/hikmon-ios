import Foundation

// MARK: - 海康 ISAPI 客户端（HTTP Digest，URLSession 原生支持）

final class ISAPIClient: NSObject {

    private let device: Device
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 25
        cfg.httpAdditionalHeaders = ["User-Agent": "HikMon/1.0"]
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    init(device: Device) {
        self.device = device
        super.init()
    }

    // MARK: 鉴权（Digest / Basic 都交给系统，凭据在这里给）

    private func handle(_ challenge: URLAuthenticationChallenge,
                        _ completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completion(.useCredential, URLCredential(trust: trust))
            return
        }
        guard challenge.previousFailureCount < 3 else {
            completion(.cancelAuthenticationChallenge, nil)
            return
        }
        completion(.useCredential, URLCredential(user: device.user, password: device.pass, persistence: .forSession))
    }

    // MARK: 底层请求

    private func url(_ path: String) -> URL? {
        URL(string: device.isapiBase + path)
    }

    func get(_ path: String) async throws -> Data {
        guard let u = url(path) else { throw ISAPIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ISAPIError.noResponse }
        guard (200..<300).contains(http.statusCode) else { throw ISAPIError.http(http.statusCode) }
        return data
    }

    func put(_ path: String, body: String) async throws -> Data {
        guard let u = url(path) else { throw ISAPIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "PUT"
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ISAPIError.noResponse }
        guard (200..<300).contains(http.statusCode) else { throw ISAPIError.http(http.statusCode) }
        return data
    }

    // MARK: 设备信息

    struct DeviceInfo {
        var name = ""
        var model = ""
        var serial = ""
        var firmware = ""
        var deviceType = ""
    }

    func deviceInfo() async throws -> DeviceInfo {
        let data = try await get("/ISAPI/System/deviceInfo")
        let xml = String(decoding: data, as: UTF8.self)
        var info = DeviceInfo()
        info.name = Self.text(xml, "deviceName")
        info.model = Self.text(xml, "model")
        info.serial = Self.text(xml, "serialNumber")
        info.firmware = Self.text(xml, "firmwareVersion")
        info.deviceType = Self.text(xml, "deviceType")
        return info
    }

    // MARK: 通道列表

    /// NVR 走 InputProxy（IP 通道），IPC 走 StreamingChannel；两套都试
    func channels() async throws -> [Camera] {
        if let list = try? await proxyChannels(), !list.isEmpty { return list }
        if let list = try? await streamingChannels(), !list.isEmpty { return list }
        return []
    }

    private func proxyChannels() async throws -> [Camera] {
        let data = try await get("/ISAPI/ContentMgmt/InputProxy/channels")
        let xml = String(decoding: data, as: UTF8.self)
        return Self.blocks(xml, tag: "InputProxyChannel").compactMap { block in
            guard let id = Int(Self.text(block, "id")) else { return nil }
            let name = Self.text(block, "name")
            return Camera(channel: id, name: name.isEmpty ? "通道 \(id)" : name)
        }
    }

    private func streamingChannels() async throws -> [Camera] {
        let data = try await get("/ISAPI/Streaming/channels")
        let xml = String(decoding: data, as: UTF8.self)
        var out: [Camera] = []
        for block in Self.blocks(xml, tag: "StreamingChannel") {
            guard let id = Int(Self.text(block, "id")) else { continue }
            // 只保留主码流（101/201/301…），子码流 id 以 02 结尾
            if id % 100 != 1 { continue }
            let name = Self.text(block, "channelName")
            out.append(Camera(channel: id / 100, name: name.isEmpty ? "通道 \(id / 100)" : name))
        }
        return out
    }

    // MARK: 抓图

    func snapshot(channel: Int) async throws -> Data {
        let id = device.streamID(channel, sub: device.useSubStream)
        return try await get("/ISAPI/Streaming/channels/\(id)/picture")
    }

    // MARK: 云台

    func ptz(channel: Int, pan: Int, tilt: Int, zoom: Int) async {
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <PTZData><pan>\(pan)</pan><tilt>\(tilt)</tilt><zoom>\(zoom)</zoom></PTZData>
        """
        _ = try? await put("/ISAPI/PTZCtrl/channels/\(channel)/continuous", body: body)
    }

    // MARK: 工具

    static func text(_ xml: String, _ tag: String) -> String {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex)
        else { return "" }
        return String(xml[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func blocks(_ xml: String, tag: String) -> [String] {
        var out: [String] = []
        var search = xml.startIndex
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        while let s = xml.range(of: open, range: search..<xml.endIndex),
              let e = xml.range(of: close, range: s.upperBound..<xml.endIndex) {
            out.append(String(xml[s.upperBound..<e.lowerBound]))
            search = e.upperBound
        }
        return out
    }
}

extension ISAPIClient: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }
}

enum ISAPIError: LocalizedError {
    case badURL
    case noResponse
    case http(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "地址不合法"
        case .noResponse: return "没有响应"
        case .http(let code):
            switch code {
            case 401: return "HTTP 401（账号或密码不对）"
            case 403: return "HTTP 403（无权限）"
            case 404: return "HTTP 404（设备不支持该接口）"
            default: return "HTTP \(code)"
            }
        case .empty: return "空响应"
        }
    }
}
