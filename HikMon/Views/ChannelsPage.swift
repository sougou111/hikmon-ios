import SwiftUI

/// 通道浏览：一页 6 路（3 行 × 2 列），左右滑动翻页，⭐收藏 / 🎤语音通道
struct ChannelsPage: View {
    @EnvironmentObject private var store: DeviceStore
    @ObservedObject var state: AppState

    @State private var page = 0
    @State private var pageCount = 1
    @State private var cells: [LiveCell] = []
    @State private var device: Device?
    @State private var dragX: CGFloat = 0

    private let perPage = 6

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { flip(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(page > 0 ? C.text : C.faint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .disabled(page <= 0)

                Text("\(page + 1) / \(pageCount) 页")
                    .font(.system(size: 13))
                    .foregroundStyle(C.text)

                Button { flip(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(page < pageCount - 1 ? C.text : C.faint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .disabled(page >= pageCount - 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)

            grid
                .padding(.horizontal, 12)

            Spacer(minLength: 0)

            Text("左右滑动切换 · 点画面看回放 · 长按就地预览")
                .font(.system(size: 10))
                .foregroundStyle(C.faint)
                .padding(.top, 6)
        }
        .onAppear(perform: setup)
        .onDisappear { cells.forEach { $0.stop() } }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { v in dragX = v.translation.width }
                .onEnded { v in
                    let dx = v.translation.width
                    let dy = v.translation.height
                    dragX = 0
                    if abs(dx) > 40 && abs(dx) > abs(dy) * 1.2 {
                        flip(dx < 0 ? 1 : -1)
                    }
                }
        )
    }

    // MARK: 网格

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { col in
                        let slot = row * 2 + col
                        cellView(slot: slot)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(slot: Int) -> some View {
        if slot < cells.count {
            let cell = cells[slot]
            VStack(spacing: 0) {
                CellView(cell: cell,
                         showFull: false,
                         onTap: { openPlayback(slot) },
                         onLong: { playInline(slot) })
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                HStack(spacing: 4) {
                    Text(nameOf(slot))
                        .font(.system(size: 11))
                        .foregroundStyle(C.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button { toggleFav(slot) } label: { starChip(slot) }
                        .buttonStyle(.plain)
                    Button { toggleMic(slot) } label: { micChip(slot) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(C.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(C.stroke, lineWidth: 1)
                    )
            )
        } else {
            Color.clear
        }
    }

    private func starChip(_ slot: Int) -> some View {
        let fav = isFav(slot)
        return Text(fav ? "★" : "☆")
            .font(.system(size: 12))
            .foregroundStyle(fav ? C.star : C.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fav ? Color(hex: 0x1D2A3D) : C.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(fav ? C.accent : C.stroke, lineWidth: 1)
                    )
            )
    }

    private func micChip(_ slot: Int) -> some View {
        let on = isTalk(slot)
        return Text("🎤")
            .font(.system(size: 12))
            .foregroundStyle(on ? C.talk : C.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on ? Color(hex: 0x17301F) : C.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(on ? C.talk : C.stroke, lineWidth: 1)
                    )
            )
    }

    // MARK: 数据

    private func setup() {
        guard let d = store.byID(state.channelDev) else { return }
        device = d
        let session = HikSessions.shared.session(for: d)
        let total = max(1, session.channelCount)
        pageCount = max(1, (total + perPage - 1) / perPage)
        page = 0
        if cells.isEmpty {
            cells = (0..<perPage).map { _ in
                LiveCell(device: d, channel: 0, tip: "—", sound: false)
            }
        }
        bind(0)

        // 登录拿到真实通道数后再校正页数/默认收藏
        DispatchQueue.global(qos: .userInitiated).async {
            let uid = session.ensureLogin()
            DispatchQueue.main.async {
                guard uid >= 0 else { return }
                let total = max(1, session.channelCount)
                self.pageCount = max(1, (total + perPage - 1) / perPage)
                if d.favs.isEmpty {
                    var nd = d
                    for i in 0..<min(4, total) { nd.favs.append(session.channelBase + i) }
                    store.update(nd)
                    self.device = nd
                    HikLog.shared.add("默认收藏 4 路通道")
                }
                self.bind(self.page)
            }
        }
    }

    private func channelOf(_ slot: Int) -> Int {
        guard let d = device else { return 0 }
        let base = HikSessions.shared.session(for: d).channelBase
        let total = HikSessions.shared.session(for: d).channelCount
        let idx = page * perPage + slot
        if idx >= total { return 0 }
        return base + idx
    }

    private func nameOf(_ slot: Int) -> String {
        let ch = channelOf(slot)
        guard ch > 0, let d = device else { return "—" }
        return "通道 \(ch - HikSessions.shared.session(for: d).channelBase + 1)"
    }

    private func isFav(_ slot: Int) -> Bool {
        guard let d = device, channelOf(slot) > 0 else { return false }
        return d.favs.contains(channelOf(slot))
    }

    private func isTalk(_ slot: Int) -> Bool {
        guard let d = device, channelOf(slot) > 0 else { return false }
        return d.talkChannel == channelOf(slot)
    }

    private func bind(_ p: Int) {
        guard let d = device else { return }
        page = p
        for slot in 0..<perPage {
            let cell = cells[slot]
            cell.stop()
            let ch = channelOf(slot)
            if ch == 0 {
                cell.setChannel(0, tip: "—")
            } else {
                let n = ch - HikSessions.shared.session(for: d).channelBase + 1
                cell.setChannel(ch, tip: "通道 \(n)\n点画面播放")
                cell.start()
            }
        }
        HikLog.shared.add("通道页 \(p + 1)/\(pageCount) 开始播放")
    }

    private func flip(_ dir: Int) {
        let np = page + dir
        guard np >= 0, np < pageCount else { return }
        cells.forEach { $0.stop() }
        bind(np)
    }

    private func playInline(_ slot: Int) {
        guard channelOf(slot) > 0 else { return }
        bind(page)
        cells[slot].restart()
    }

    private func toggleFav(_ slot: Int) {
        guard let d = device, channelOf(slot) > 0 else { return }
        let ch = channelOf(slot)
        store.mutate(d.id) { dev in
            if let i = dev.favs.firstIndex(of: ch) { dev.favs.remove(at: i) } else { dev.favs.append(ch) }
        }
        device = store.byID(d.id)
        HikLog.shared.add((isFav(slot) ? "收藏" : "取消收藏") + " 通道 \(ch - HikSessions.shared.session(for: d).channelBase + 1)")
    }

    private func toggleMic(_ slot: Int) {
        guard let d = device, channelOf(slot) > 0 else { return }
        let ch = channelOf(slot)
        store.mutate(d.id) { dev in
            dev.talkChannel = (dev.talkChannel == ch) ? 0 : ch
        }
        device = store.byID(d.id)
        HikLog.shared.add(device?.talkChannel == 0 ? "取消语音通道" : "语音通道 = 通道 \(ch - HikSessions.shared.session(for: d).channelBase + 1)")
    }

    private func openPlayback(_ slot: Int) {
        guard let d = device, channelOf(slot) > 0 else { return }
        cells.forEach { $0.stop() }
        state.playDev = d.id
        state.playChannel = channelOf(slot)
        state.pbTime = Date()
        state.go(.playback)
    }
}
