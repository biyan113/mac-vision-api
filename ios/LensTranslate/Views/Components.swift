import SwiftUI

/// 在相机画面上循环扫过的亮线
struct ScanLine: View {
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 2)
                .shadow(color: Theme.accent.opacity(0.7), radius: 10)
                .offset(y: proxy.size.height * (0.12 + 0.6 * progress))
                .opacity(reduceMotion ? 0 : (progress < 0.04 || progress > 0.96 ? 0 : 1))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: false)) {
                progress = 1
            }
        }
    }
}

/// 底部的模式切换
struct ModeSwitcher: View {
    @Binding var mode: RootView.Mode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootView.Mode.allCases) { item in
                Button {
                    withAnimation(Theme.spring) { mode = item }
                } label: {
                    Text(item.title)
                        .font(.system(size: 15, weight: mode == item ? .bold : .medium))
                        .foregroundStyle(mode == item ? Color.black : Color.white)
                        .frame(minWidth: 56, minHeight: 44)
                        .padding(.horizontal, 6)
                        .background {
                            if mode == item {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                }
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.1), in: Capsule())
    }
}

/// 随音量起伏的波形
struct Waveform: View {
    var level: Float
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 31

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 4, height: height(for: index, time: time))
                        .opacity(0.45 + 0.55 * centre(index))
                }
            }
            .frame(height: 56)
        }
        .accessibilityHidden(true)
    }

    private func centre(_ index: Int) -> Double {
        1 - abs(Double(index) - Double(barCount - 1) / 2) / (Double(barCount - 1) / 2)
    }

    private func height(for index: Int, time: TimeInterval) -> CGFloat {
        guard active else { return 4 }
        let wobble = (sin(time * 6 + Double(index) * 0.9) + 1) / 2
        let amount = Double(level) * (0.35 + 0.65 * wobble) * (0.3 + 0.7 * centre(index))
        return CGFloat(4 + 52 * min(amount, 1))
    }
}

/// 向外扩散的光环，用在正在工作的按钮上
struct PulseRing: ViewModifier {
    var active: Bool
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                if active, !reduceMotion {
                    Circle()
                        .stroke(Theme.accent.opacity(expanded ? 0 : 0.6), lineWidth: 3)
                        .scaleEffect(expanded ? 1.6 : 1)
                        .onAppear {
                            expanded = false
                            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                                expanded = true
                            }
                        }
                }
            }
    }
}

extension View {
    func pulseRing(active: Bool) -> some View {
        modifier(PulseRing(active: active))
    }
}

/// 从释义里取出适合贴在画面上的简短注释，例如 “vt. 保持；雇；记住” → “保持；雇”
func shortGloss(_ definition: String) -> String {
    guard var line = definition.split(separator: "\n").first.map(String.init) else { return "" }
    if let range = line.range(of: #"^[a-z]+\.\s*"#, options: .regularExpression) {
        line.removeSubrange(range)
    }
    let parts = line.split(whereSeparator: { "；;，,".contains($0) }).prefix(2)
    return parts.joined(separator: "；")
}
