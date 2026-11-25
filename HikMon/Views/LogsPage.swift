import SwiftUI

struct LogsPage: View {
    @ObservedObject private var log = HikLog.shared
    @EnvironmentObject private var store: DeviceStore
    @State private var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = log.text
                    toast = "日志已复制"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { toast = nil }
                } label: { Chip(text: "复制全部", primary: true) }
                    .buttonStyle(.plain)

                Button {
                    log.clear()
                } label: { Chip(text: "清空") }
                    .buttonStyle(.plain)

                Spacer()

                if let t = toast {
                    Text(t).font(.system(size: 11)).foregroundStyle(C.sub)
                }
            }
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.text.isEmpty ? "暂无日志" : log.text)
                        .font(.system(size: 10))
                        .foregroundStyle(C.logText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .id("bottom")
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}
