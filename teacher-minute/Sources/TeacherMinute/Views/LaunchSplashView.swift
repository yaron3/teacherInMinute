import SwiftUI

struct LaunchSplashView: View {
  var body: some View {
    ZStack {
      Color(.systemBackground)
        .ignoresSafeArea()

      VStack(spacing: 32) {
        Image("LaunchIcon", bundle: .module)
          .resizable()
          .scaledToFit()
          .frame(width: 120, height: 120)
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        ProgressView()
          .progressViewStyle(.circular)
          .scaleEffect(1.2)
      }
    }
  }
}

#if os(iOS)
struct LaunchSplashView_Previews: PreviewProvider {
  static var previews: some View {
    LaunchSplashView()
  }
}
#endif
