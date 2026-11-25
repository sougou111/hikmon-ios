import SwiftUI

/// 设备诊断：只用 NET_DVR_STDXMLConfig 读，不写任何配置
struct DiagPage: View {
    @EnvironmentObject private var store: DeviceStore
    @ObservedObject var state: AppState

    @State private var out = "点上面「读取设备配置」开始"
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { run() } label: { Chip(text: "读取设备配置", primary: true) }
                    .buttonStyle(.plain)
                Button {
                    UIPasteboard.general.string = out
                    state.show("已复制")
                } label: { Chip(text: "复制结果") }
                    .buttonStyle(.plain)
                Spacer()
            }

            Text("只读取设备配置，不修改任何设置。")
                .font(.system(size: 11))
                .foregroundStyle(C.sub)
                .padding(.vertical, 8)

            ScrollView {
                Text(out)
                    .font(.system(size: 10))
                    .foregroundStyle(C.logText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func append(_ s: String) {
        if let first = s.split(separator: "\n").first {
            HikLog.shared.add(String(first.prefix(200)))
        }
        out += s
    }

    private func run() {
        guard !running, let d = store.byID(state.diagDev) else { return }
        running = true
        out = "读取中…\n"
        let session = HikSessions.shared.session(for: d)

        DispatchQueue.global(qos: .userInitiated).async {
            guard session.ensureLogin() >= 0 else {
                DispatchQueue.main.async {
                    append("登录失败，无法读取")
                    running = false
                }
                return
            }
            let uid = session.userId
            let base = session.channelBase
            let cnt = session.channelCount
            var urls: [String] = ["/ISAPI/System/deviceInfo"]
            let tryN = min(2, max(1, cnt))
            for i in 0..<tryN {
                let ch = base + i
                urls += [
                    "/ISAPI/System/Video/inputs/channels/\(ch)/motionDetection",
                    "/ISAPI/ContentMgmt/InputProxy/channels/\(ch)/motionDetection",
                    "/ISAPI/Smart/LineDetection/\(ch)",
                    "/ISAPI/Smart/FieldDetection/\(ch)",
                    "/ISAPI/Smart/faceDetect/\(ch)",
                    "/ISAPI/Streaming/channels/\(ch * 100 + 1)",
                    "/ISAPI/Streaming/channels/\(ch * 100 + 2)"
                ]
            }
            urls += ["/ISAPI/Smart/capabilities",
                     "/ISAPI/System/Audio/channels",
                     "/ISAPI/System/TwoWayAudio/channels"]

            for url in urls {
                let xml = HikMonSDK.stdXML(uid, url: "GET " + url, body: nil, status: nil)
                let body = xml.isEmpty ? "（空）" : xml.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    append("\n──── \(url)\n结果: \(xml.isEmpty ? "失败 \(HikMonSDK.lastErrorText())" : "OK")  size=\(xml.count)\n\(body)\n")
                }
            }
            DispatchQueue.main.async {
                append("\n=== 读取完成")
                running = false
            }
        }
    }
}
