import LensCore
import SwiftUI

/// 翻译模式：把译文贴在原文的位置上
struct TranslationOverlay: View {
    @ObservedObject var live: LiveTextModel
    @ObservedObject var bridge: TranslationBridge
    var showOriginal: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(live.lines) { line in
                    let rect = PreviewGeometry.viewRect(forNormalized: line.box, imageSize: live.imageSize, viewSize: proxy.size)
                    label(for: line, height: rect.height)
                        .frame(width: max(rect.width + 8, 24), height: max(rect.height + 4, 16))
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .animation(.easeOut(duration: 0.25), value: live.lines)
        }
        .opacity(showOriginal ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: showOriginal)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func label(for line: RecognizedLine, height: CGFloat) -> some View {
        if let translated = bridge.translation(for: line.text) {
            Text(translated)
                .font(.system(size: max(height * 0.72, 10), weight: .semibold))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            // 还没翻译完：流动的高光条
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.accent.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1)
                )
        }
    }
}

/// 学词模式：保留原文，只标出词书里的单词
struct LearnOverlay: View {
    @ObservedObject var live: LiveTextModel
    var focusedID: Int?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(live.highlights) { highlight in
                    let rect = PreviewGeometry.viewRect(forNormalized: highlight.box, imageSize: live.imageSize, viewSize: proxy.size)
                    let focused = highlight.entry.id == focusedID
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.accent.opacity(focused ? 0.4 : 0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: focused ? 2 : 1)
                        )
                        .frame(width: rect.width + 6, height: rect.height + 4)
                        .position(x: rect.midX, y: rect.midY)

                    if focused {
                        Text(shortGloss(highlight.entry.definition))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Theme.onAccent, in: Capsule())
                            .fixedSize()
                            .position(x: rect.midX, y: rect.minY - 20)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
            }
            .animation(.easeOut(duration: 0.25), value: live.highlights)
            .animation(Theme.spring, value: focusedID)
        }
        .allowsHitTesting(false)
    }
}

/// 找出最靠近画面中心的一项
@MainActor
enum Focus {
    static func nearestLine(in live: LiveTextModel, viewSize: CGSize) -> RecognizedLine? {
        live.lines.min { lhs, rhs in
            distance(lhs.box, live, viewSize) < distance(rhs.box, live, viewSize)
        }
    }

    static func nearestHighlight(in live: LiveTextModel, viewSize: CGSize) -> Highlight? {
        live.highlights.min { lhs, rhs in
            distance(lhs.box, live, viewSize) < distance(rhs.box, live, viewSize)
        }
    }

    private static func distance(_ box: CGRect, _ live: LiveTextModel, _ viewSize: CGSize) -> CGFloat {
        let rect = PreviewGeometry.viewRect(forNormalized: box, imageSize: live.imageSize, viewSize: viewSize)
        return PreviewGeometry.distanceFromCenter(rect, in: viewSize)
    }
}
