//
//  GoogleAuth+Android.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

#if os(Android)
import SkipBridge

struct AndroidGoogleAuth {
    func signIn() async throws -> String {
        let result = try await Task.detached(priority: .userInitiated) {
            try AndroidGoogleSignInBridge.signIn()
        }.value
        logger.info("Android Google sign-in result: \(result)")
        return result
    }

    static func uid(from signInResult: String) -> String? {
        let parts = signInResult.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "success", !parts[1].isEmpty else {
            return nil
        }
        return String(parts[1])
    }
}

private enum AndroidGoogleSignInBridge {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidGoogleSignInManager")
    private static let signInMethod = managerClass.getStaticMethodID(
        name: "signIn",
        sig: "()Ljava/lang/String;"
    )!

    static func signIn() throws -> String {
        try jniContext {
            try managerClass.callStatic(
                method: signInMethod,
                options: [.kotlincompat],
                args: []
            )
        }
    }
}
#endif
