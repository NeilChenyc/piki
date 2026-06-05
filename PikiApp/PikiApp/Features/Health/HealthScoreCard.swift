import SwiftUI
import Charts

struct HealthScoreCard: View {
    let score: HealthScore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(score.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: score.trend.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(score.trend.color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(score.value > 0 ? "\(Int(score.value))" : "--")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("%")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.border.opacity(0.3))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressColor)
                        .frame(width: geo.size.width * score.value / 100)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .cardStyle()
    }

    private var progressColor: Color {
        switch score.value {
        case 80...: Theme.success
        case 60..<80: .orange
        default: Theme.error
        }
    }
}

struct HealthTrendChart: View {
    let data: [HealthTrendPoint]

    var body: some View {
        if data.isEmpty {
            VStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.textTertiary)
                Text("No data yet — run a lint check to start tracking")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(data) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Theme.primary.gradient.opacity(0.3))

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Theme.primary)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: 0...100)
        }
    }
}
