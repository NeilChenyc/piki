import SwiftUI

struct PikiLogo: View {
    var body: some View {
        Image("BrandLogo", bundle: brandLogoBundle)
            .resizable()
            .aspectRatio(contentMode: .fit)
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
    PikiLogo()
        .frame(width: 160, height: 64)
        .padding()
        .background(Color.white)
}
