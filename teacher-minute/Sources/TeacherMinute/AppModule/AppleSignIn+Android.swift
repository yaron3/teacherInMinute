//
//  AppleSignIn+Android.swift
//  teacher-minute
//
//  Created by Codex on 16/05/2026.
//

#if os(Android)
import SkipBridge

struct AndroidAppleAuth {
    func signIn() async throws -> String {
        let result = try await Task.detached(priority: .userInitiated) {
            try AndroidAppleSignInBridge.signIn()
        }.value
        print("Android Apple sign-in result: \(result)")
        return result
    }
}

private enum AndroidAppleSignInBridge {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidAppleSignInManager")
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
