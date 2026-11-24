import SwiftUI

enum Theme {
    static let accent = Color(red: 0.784, green: 0.961, blue: 0.376)
    static let onAccent = Color(red: 0.07, green: 0.086, blue: 0.039)
    static let ground = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let surface = Color(red: 0.078, green: 0.09, blue: 0.11)
    static let surfaceRaised = Color(red: 0.106, green: 0.122, blue: 0.145)
    static let secondaryText = Color(red: 0.722, green: 0.745, blue: 0.776)
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
}

/// 浮在相机画面上的毛玻璃底
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

/// 圆形图标按钮，保证 44pt 的点击区域
struct CircleIconButton: View {
    let systemName: String
    let label: String
    var filled = false
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(filled ? Theme.onAccent : Color.white)
                .frame(width: size, height: size)
                .background {
                    if filled {
                        Circle().fill(Theme.accent)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
        }
        .accessibilityLabel(label)
    }
}
