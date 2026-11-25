import SwiftUI

struct PlaybackPage: View {
    @EnvironmentObject private var store: DeviceStore
    @ObservedObject var state: AppState

    var body: some View {
        if let d = store.byID(state.playDev) {
            PlaybackContent(device: d, channel: state.playChannel,
                            initial: state.pbTime, state: state)
                .id("\(d.id.uuidString)-\(state.playChannel)")
        } else {
            EmptyHint(text: "设备不存在")
        }
    }
}

private struct PlaybackContent: View {
    let device: Device
    let channel: Int
    let initial: Date
    @ObservedObject var state: AppState

    @StateObject private var pb = PbEngine()
    @State private var time: Date
    @State private var windowMin = 60

    init(device: Device, channel: Int, initial: Date, state: AppState) {
        self.device = device
        self.channel = channel
        self.initial = initial
        self.state = state
        _time = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VideoPane(canvas: pb.canvas, tip: pb.tip,
                      onTap: { pb.togglePlayPause() },
                      onLong: { pb.toggleSpeed() })
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .padding(.horizontal, 10)

            HStack(alignment: .center) {
                Text(Self.fmt(time))
                    .font(.system(size: 16))
                    .foregroundStyle(C.text)
                Spacer()
                Text(stateText)
                    .font(.system(size: 11))
                    .foregroundStyle(C.sub)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 4)

            TimeBarView(time: $time, windowMin: $windowMin,
                        onScrubStart: { _ = pb.handle },
                        onCommit: { pb.seek(to: time) })
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 6)

            HStack(spacing: 6) {
                ForEach(jumps.indices, id: \.self) { i in
                    Button {
                        time = time.addingTimeInterval(Double(jumps[i].1) * 60)
                        pb.seek(to: time)
                    } label: {
                        Chip(text: jumps[i].0, stretch: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 6)

            HStack(spacing: 8) {
                Button { pb.togglePlayPause() } label: {
                    Chip(text: "播放/暂停", primary: true)
                }
                .buttonStyle(.plain)

                Button { pb.toggleSpeed() } label: {
                    Chip(text: "2× 倍速", stretch: true)
                }
                .buttonStyle(.plain)

                Button {
                    time = Date()
                    pb.seek(to: time)
                } label: {
                    Chip(text: "现在")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 10)

            Spacer(minLength: 0)
        }
        .onAppear {
            pb.configure(device: device, channel: channel, from: initial)
            pb.start(restart: false)
        }
        .onDisappear { pb.stop() }
    }

    private var jumps: [(String, Int)] {
        [("-1时", -60), ("-10分", -10), ("+10分", 10), ("+1时", 60)]
    }

    private var stateText: String {
        var s = pb.playing ? "回放中" : "已暂停"
        if pb.fast { s += " · 2×" }
        s += " · 视野 \(windowMin)分"
        return s
    }

    static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}

/// 竖向时间轴：上下拖动选时间、双指缩放窗口（10–360 分钟）、点按跳转
struct TimeBarView: View {
    @Binding var time: Date
    @Binding var windowMin: Int
    var onScrubStart: () -> Void
    var onCommit: () -> Void

    @State private var dragStart: Date?
    @State private var totalDy: CGFloat = 0
    @State private var pinchBase: Int = 60

    var body: some View {
        GeometryReader { geo in
            let h = max(120, geo.size.height)
            let w = geo.size.width

            Canvas { ctx, size in
                draw(ctx: &ctx, size: size)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(C.darkBanner)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if dragStart == nil {
                            dragStart = time
                            totalDy = 0
                            onScrubStart()
                        }
                        totalDy = v.translation.height
                        let minutes = -Double(v.translation.height) * Double(windowMin) / Double(h)
                        time = (dragStart ?? time).addingTimeInterval(minutes * 60)
                    }
                    .onEnded { v in
                        // 位移很小 = 点按跳转
                        if abs(totalDy) < 8 {
                            let deltaMin = Double(h / 2 - v.location.y) * Double(windowMin) / Double(h)
                            time = time.addingTimeInterval(deltaMin * 60)
                        }
                        dragStart = nil
                        totalDy = 0
                        onCommit()
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        if dragStart == nil { pinchBase = windowMin }
                        let nv = Int(Double(pinchBase) / Double(max(scale, 0.01)))
                        windowMin = min(360, max(10, nv))
                    }
                    .onEnded { _ in
                        onCommit()
                    }
            )
        }
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }

        let step = pickStep(windowMin)
        let pxPerMin = h / CGFloat(windowMin)

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        var cursor = time.addingTimeInterval(-Double(windowMin / 2) * 60)
        // 对齐到整步长
        let comps = cal.dateComponents([.minute], from: cursor)
        let rem = (comps.minute ?? 0) % step
        cursor = cursor.addingTimeInterval(-Double(rem) * 60)

        for _ in 0..<(windowMin / step + 2) {
            let diffMin = cursor.timeIntervalSince(time) / 60
            let y = h / 2 + CGFloat(diffMin) * pxPerMin
            if y < -6 || y > h + 6 {
                cursor = cursor.addingTimeInterval(Double(step) * 60)
                continue
            }
            let c = cal.dateComponents([.minute, .hour], from: cursor)
            let hourMark = (c.minute == 0)

            var line = Path()
            line.move(to: CGPoint(x: w * 0.42, y: y))
            line.addLine(to: CGPoint(x: w * 0.92, y: y))
            ctx.stroke(line, with: .color(hourMark ? Color(hex: 0x5A6474) : Color(hex: 0x39404C)),
                       lineWidth: 1)

            let inFooter = (y > h - 26) || (y < 10)
            if !inFooter {
                let label = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
                let text = Text(label)
                    .font(.system(size: hourMark ? 13 : 11, weight: hourMark ? .semibold : .regular))
                    .foregroundColor(hourMark ? .white : Color(hex: 0x8A94A6))
                ctx.draw(text, at: CGPoint(x: 10, y: y), anchor: .leading)
            }
            cursor = cursor.addingTimeInterval(Double(step) * 60)
        }

        // 中央指针
        ctx.fill(Path(CGRect(x: 0, y: h / 2 - 16, width: w, height: 32)),
                 with: .color(Color(hex: 0x3D8BFF).opacity(0.2)))
        var center = Path()
        center.move(to: CGPoint(x: 0, y: h / 2))
        center.addLine(to: CGPoint(x: w, y: h / 2))
        ctx.stroke(center, with: .color(C.accent), lineWidth: 2)

        // 底部条
        ctx.fill(Path(CGRect(x: 0, y: h - 22, width: w, height: 22)), with: .color(C.bg))
        ctx.draw(Text("窗口 \(windowMin) 分钟")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: 0x6E7A8C)),
                 at: CGPoint(x: 10, y: h - 11), anchor: .leading)
        ctx.draw(Text("双指缩放")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: 0x6E7A8C)),
                 at: CGPoint(x: w - 10, y: h - 11), anchor: .trailing)
    }

    private func pickStep(_ win: Int) -> Int {
        if win <= 12 { return 1 }
        if win <= 30 { return 2 }
        if win <= 60 { return 5 }
        if win <= 120 { return 10 }
        if win <= 240 { return 30 }
        return 60
    }
}

