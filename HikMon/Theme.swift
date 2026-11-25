import SwiftUI
import UIKit

// 与安卓 MainActivity 里那套色值/圆角/内边距完全一致
enum C {
    static let bg        = Color(hex: 0x0E1116)
    static let card      = Color(hex: 0x171B22)
    static let stroke    = Color(hex: 0x262C36)
    static let text      = Color(hex: 0xE8EDF5)
    static let sub       = Color(hex: 0x8A94A6)
    static let accent    = Color(hex: 0x3D8BFF)
    static let star      = Color(hex: 0xFFC53D)
    static let talk      = Color(hex: 0x34C759)
    static let faint     = Color(hex: 0x5F6876)
    static let hintC     = Color(hex: 0x555F6E)
    static let cellBg    = Color(hex: 0x05070A)
    static let cellEdge  = Color(hex: 0x20242C)
    static let logText   = Color(hex: 0xB8C2D0)
    static let banner    = Color(hex: 0x16202E)
    static let dangerBg  = Color(hex: 0x2A1518)
    static let dangerEdge = Color(hex: 0x5A2A2E)
    static let dangerText = Color(hex: 0xFF6B6B)
    static let darkBanner = Color(hex: 0x14181F)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// 安卓 chip：圆角 18、内边距 15×9、13 号字；primary 用 accent 填充
struct Chip: View {
    let text: String
    var primary: Bool = false
    var stretch: Bool = false
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(primary ? .white : C.text)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .frame(maxWidth: stretch ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(primary ? C.accent : C.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(primary ? C.accent : C.stroke, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
    }
}

struct ChipButton: View {
    let text: String
    var primary: Bool = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Chip(text: text, primary: primary) }
            .buttonStyle(.plain)
    }
}

struct CardBox<Content: View>: View {
    var radius: CGFloat = 14
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(C.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(C.stroke, lineWidth: 1)
                    )
            )
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(C.sub)
            .padding(.top, 18)
            .padding(.bottom, 9)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HintLine: View {
    let text: String
    var color: Color = C.hintC
    var size: CGFloat = 12
    var body: some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(color)
            .padding(.vertical, 10)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 输入框：安卓 input() —— 卡片底、圆角 12、14 号字、内边距 14×12
struct HikField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: ph)
            } else {
                TextField("", text: $text, prompt: ph)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(keyboard)
        .font(.system(size: 14))
        .foregroundColor(C.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(C.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(C.stroke, lineWidth: 1)
                )
        )
        .padding(.bottom, 9)
    }

    private var ph: Text {
        Text(placeholder).foregroundColor(C.hintC)
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(C.sub)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }
}
