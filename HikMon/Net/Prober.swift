import Foundation
import Network

/// 端口 / 协议探测：用来解决「到底该填哪个端口」的问题
enum Prober {

    /// TCP 连通性
    static func tcp(host: String, port: Int, timeout: TimeInterval = 2.0) async -> Bool {
        guard let p = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let result: Bool = await withCheckedContinuation { cont in
            var done = false
            let finish: (Bool) -> Void = { ok in
                if done { return }
                done = true
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
        return result
    }

    /// RTSP 握手：发 OPTIONS，能收到 "RTSP/1.0 200/401" 就算这条端口上跑的是 RTSP
    static func rtsp(host: String, port: Int, timeout: TimeInterval = 4.0) async -> (ok: Bool, note: String) {
        guard let p = NWEndpoint.Port(rawValue: UInt16(port)) else { return (false, "端口非法") }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)

        return await withCheckedContinuation { cont in
            var done = false
            var buffer = Data()
            let finish: (Bool, String) -> Void = { ok, note in
                if done { return }
                done = true
                conn.cancel()
                cont.resume(returning: (ok, note))
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let req = "OPTIONS rtsp://\(host):\(port)/ RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: HikMon\r\n\r\n"
                    conn.send(content: req.data(using: .utf8), completion: .contentProcessed { err in
                        if err != nil { finish(false, "发送失败") }
                    })
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, err in
                        if let data { buffer.append(data) }
                        let text = String(decoding: buffer, as: UTF8.self)
                        if text.contains("RTSP/1.0") {
                            if text.contains(" 200") { finish(true, "RTSP 就绪") }
                            else if text.contains(" 401") { finish(true, "RTSP 需要鉴权（正常）") }
                            else { finish(false, text.split(separator: "\r\n").first.map(String.init) ?? "未知响应") }
                        } else if err != nil {
                            finish(false, "不是 RTSP 服务")
                        }
                    }
                case .failed:
                    finish(false, "连不上")
                default:
                    break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false, "超时（\(Int(timeout))s）") }
        }
    }

    /// 扫一批常用端口，返回开放的
    static func scan(host: String, ports: [Int] = [80, 8000, 554, 8080, 443, 8001, 8888, 37777]) async -> [Int] {
        var open: [Int] = []
        await withTaskGroup(of: (Int, Bool).self) { group in
            for p in ports {
                group.addTask { (p, await tcp(host: host, port: p, timeout: 1.6)) }
            }
            for await (p, ok) in group where ok {
                open.append(p)
            }
        }
        return open.sorted()
    }
}
