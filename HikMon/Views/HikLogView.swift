import Foundation
import SwiftUI
import Darwin

/// 应用内日志面板：
/// 把 stderr 重定向到管道（NSLog 也走 stderr），所以 HCNetSDK / PlayM4 的报错
/// 都会被抓到，保留最近 800 行，界面上直接看、直接分享出去。
final class HikLog: ObservableObject {
    static let shared = HikLog()

    @Published private(set) var lines: [String] = []

    private let queue = DispatchQueue(label: "com.ynvr.hikmon.log")
    private let cap = 800
    private var buffer = ""
    private var pipe: Pipe?

    private init() {}

    func startCapture() {
        guard pipe == nil else { return }
        let p = Pipe()
        pipe = p
        setvbuf(stderr, nil, _IONBF, 0)
        dup2(p.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        p.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            let s = String(decoding: data, as: UTF8.self)
            self?.append(s)
        }
        add("---- HikMon 启动，日志已接管 ----")
    }

    /// 从 Swift 侧补一条（状态变化、按钮点击之类）
    func add(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        append("[app \(f.string(from: Date()))] \(s)\n")
    }

    private func append(_ chunk: String) {
        queue.async {
            self.buffer += chunk
            var parts = self.buffer.components(separatedBy: "\n")
            guard parts.count > 1 else {
                if self.buffer.count > 16_384 { self.buffer = String(self.buffer.suffix(8192)) }
                return
            }
            self.buffer = parts.removeLast()
            let fresh = parts.map { $0.replacingOccurrences(of: "\r", with: "") }.filter { !$0.isEmpty }
            guard !fresh.isEmpty else { return }
            DispatchQueue.main.async {
                self.lines.append(contentsOf: fresh)
                if self.lines.count > self.cap {
                    self.lines.removeFirst(self.lines.count - self.cap)
                }
            }
        }
    }

    func clear() {
        lines.removeAll()
        queue.async { self.buffer = "" }
    }

    var text: String { lines.joined(separator: "\n") }
}

struct HikLogView: View {
    @ObservedObject private var log = HikLog.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(log.lines.isEmpty ? "暂无日志。进一次预览/回放再回来看。" : log.lines.joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .navigationTitle("SDK 日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: log.text.isEmpty ? "（暂无日志）" : log.text) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("清空") { log.clear() }
                }
            }
        }
    }
}
