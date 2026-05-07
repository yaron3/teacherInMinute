#if canImport(UIKit)
import UIKit

extension UIApplication {
	var rootVC: UIViewController? {
		return self.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow }?
			.rootViewController
	}

	static func topMostViewController() -> UIViewController? {
		return UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow }?
			.rootViewController
	}
}
#endif
