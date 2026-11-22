import SwiftUI

struct PlaybackView: View {
    let device: Device
    let cameras: [Camera]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var box = PlayerBox()
    @State private var channel: Int
    @State private var start: Date = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    @State private var hours: Int = 2
    @State private var err = ""

    init(device: Device, cameras: [Camera]) {
        self.device = device
        self.cameras = cameras
        _channel = State(initialValue: cameras.first?.channel ?? 1)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    VLCVideoView(player: box.player)
                    if !box.isPlaying && !box.failed {
                        ProgressView().tint(.white)
                    }
                    if box.failed {
                        Text(box.stateText).font(.caption).foregroundStyle(.orange)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                Form {
                    if cameras.count > 1 {
                        Picker("通道", selection: $channel) {
                            ForEach(cameras) { c in
                                Text("CH\(c.channel) \(c.name)").tag(c.channel)
                            }
                        }
                    }
                    DatePicker("开始时间", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    Picker("时长", selection: $hours) {
                        Text("1 小时").tag(1)
                        Text("2 小时").tag(2)
                        Text("4 小时").tag(4)
                    }
                    Button {
                        play()
                    } label: {
                        Label("播放这段录像", systemImage: "play.circle.fill")
                    }
                    if !err.isEmpty {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
                .frame(maxHeight: 320)
            }
            .navigationTitle("回放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { box.stop(); dismiss() }
                }
            }
            .onDisappear { box.stop() }
        }
    }

    private func play() {
        let end = start.addingTimeInterval(TimeInterval(hours * 3600))
        let url = device.playbackURL(channel: channel, from: start, to: end)
        box.play(url)
        err = ""
    }
}
