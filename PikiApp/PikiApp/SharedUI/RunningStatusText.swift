import SwiftUI

struct RunningStatusText: View {
    let text: String
    let isActive: Bool
    let font: Font
    let color: Color
    var lineLimit: Int? = nil
    var alignment: Alignment = .leading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        baseText(color: color)
            .overlay {
                if shouldAnimate {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        GeometryReader { proxy in
                            let width = max(proxy.size.width, 1)
                            let highlightWidth = max(width * 0.5, 44)

                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.72),
                                    Color.white.opacity(0.0),
                                    .clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: highlightWidth)
                            .offset(x: highlightOffset(date: context.date, width: width, highlightWidth: highlightWidth))
                            .mask(
                                baseText(color: .white)
                                    .frame(maxWidth: .infinity, alignment: alignment)
                            )
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private var shouldAnimate: Bool {
        isActive && !reduceMotion
    }

    private func baseText(color: Color) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
    }

    private func highlightOffset(date: Date, width: CGFloat, highlightWidth: CGFloat) -> CGFloat {
        let cycleDuration = 1.45
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        let travel = width + highlightWidth
        return (progress * travel) - highlightWidth
    }
}
