import SwiftUI

struct PikiLogo: View {
    enum Style {
        case navigation
        case hero

        var height: CGFloat {
            switch self {
            case .navigation: 78.4
            case .hero: 120
            }
        }
    }

    let style: Style

    init(style: Style = .navigation) {
        self.style = style
    }

    var body: some View {
        Image("BrandLogo", bundle: brandLogoBundle)
            .resizable()
            .scaledToFit()
            .frame(height: style.height)
            .accessibilityLabel("Piki")
    }

    private var brandLogoBundle: Bundle? {
#if SWIFT_PACKAGE
        Bundle.module
#else
        nil
#endif
    }
}

#Preview {
    VStack(spacing: 24) {
        PikiLogo(style: .navigation)
        PikiLogo(style: .hero)
    }
    .padding()
    .background(Theme.primaryPanelBackground)
}
