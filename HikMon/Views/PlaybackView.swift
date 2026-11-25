import SwiftUI
import Combine

/// 回放：按时间点播（PlayBackByTime_V40 + 数据回调 + PlayM4 解码）
struct PlaybackView: View {
    let device: Device

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: PlaybackEngine

    @State private var channel: Int
    @State private var startDate: Date
    @State private var minutes: Int = 30
    @State private var sliderValue: Double = 0
    @State private var dragging = false

    init(device: Device) {
        self.device = device
        _engine = StateObject(wrappedValue: PlaybackEngine(device: device))
        _channel = State(initialValue: device.channels.first ?? 1)
        _startDate = State(initialValue: Date().addingTimeInterval(-1800))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    SDKCanvasRepresentable(canvas: engine.canvas)
                    if engine.handle < 0 {
                        VideoPlaceholder(text: engine.status.isEmpty ? "还没有开始回放" : engine.status)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        Button {
                            engine.togglePause()
                        } label: {
                            Image(systemName: engine.playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 34))
                        }
                        .disabled(engine.handle < 0)

                        Text(timeText(engine.position))
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()

                        Slider(value: $sliderValue,
                               in: 0...max(engine.duration, 1),
                               onEditingChanged: { editing in
                            dragging = editing
                            if !editing { engine.seek(to: sliderValue) }
                        })
                        .disabled(engine.handle < 0)

                        Text(timeText(engine.duration))
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)

                    Form {
                        Section("点播区间") {
                            if device.channels.count > 1 {
                                Picker("通道", selection: $channel) {
                                    ForEach(device.channels, id: \.self) { ch in
                                        Text("CH\(ch) \(device.name(for: ch))").tag(ch)
                                    }
                                }
                            }
                            DatePicker("开始时间", selection: $startDate,
                                       displayedComponents: [.date, .hourAndMinute])
                            Picker("时长", selection: $minutes) {
                                Text("15 分钟").tag(15)
                                Text("30 分钟").tag(30)
                                Text("1 小时").tag(60)
                                Text("2 小时").tag(120)
                                Text("4 小时").tag(240)
                            }
                        }

                        Section {
                            Button {
                                engine.start(channel: channel,
                                             from: startDate,
                                             seconds: TimeInterval(minutes * 60))
                            } label: {
                                Label("开始回放", systemImage: "play.rectangle.fill")
                            }
                            if !engine.status.isEmpty {
                                Text(engine.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("回放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        engine.stop()
                        dismiss()
                    }
                }
            }
            .onReceive(engine.$position) { v in
                if !dragging { sliderValue = min(v, max(engine.duration, 1)) }
            }
            .onDisappear { engine.stop() }
        }
    }

    private func timeText(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "00:00" }
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
