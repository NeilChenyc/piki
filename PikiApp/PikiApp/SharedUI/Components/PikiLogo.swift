import SwiftUI

struct PikiLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.primary.gradient)
            // Simplified geometric pattern
            HStack(spacing: 3) {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 6, height: 6)
                VStack(spacing: 3) {
                    Circle()
                        .fill(.white.opacity(0.7))
                        .frame(width: 5, height: 5)
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}

#Preview {
    PikiLogo()
        .frame(width: 32, height: 32)
        .padding()
}
