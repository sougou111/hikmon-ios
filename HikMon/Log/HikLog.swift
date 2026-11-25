import Foundation
import UIKit
import Darwin

/// 运行日志，行为对齐安卓 log()：
/// 缓冲 3000 字符、每行 "HH:mm:ss  内容"、底部固定三行、日志页可全选复制。
/// 同时把 stderr 接管进来，HCNetSDK / PlayM4 自己的 NSLog 也会被抓到。
final class HikLog: ObservableObject {
    static let shared = HikLog()

    @Published private(set) var text: String = ""
    @Published private(set) var lines: [String] = []

    private let cap = 3000
    private let q = DispatchQueue(label: "com.ynvr.hikmon.logbuf")
    private var buf = ""
    private var pipe: Pipe?
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {}

    /// 只允许调一次（App 启动时）
    func startCapture() {
        guard pipe == nil else { return }
        let p = Pipe()
        pipe = p
        setvbuf(stderr, nil, _IONBF, 0)
        dup2(p.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        p.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            let s = String(decoding: d, as: UTF8.self)
            for raw in s.split(separator: "\n") {
                let line = String(raw).replacingOccurrences(of: "\r", with: "")
                if !line.isEmpty { self?.raw(line) }
            }
        }
    }

    func add(_ s: String) {
        raw(fmt.string(from: Date()) + "  " + s)
    }

    private func raw(_ line: String) {
        q.async {
            self.buf += line + "\n"
            if self.buf.count > self.cap {
                self.buf = String(self.buf.suffix(self.cap))
            }
            let snapshot = self.buf
            DispatchQueue.main.async {
                self.text = snapshot
                self.lines = snapshot.split(separator: "\n").map(String.init)
            }
        }
    }

    func clear() {
        q.async { self.buf = "" }
        text = ""
        lines = []
    }

    var tail: String {
        lines.suffix(3).joined(separator: "\n")
    }
}
