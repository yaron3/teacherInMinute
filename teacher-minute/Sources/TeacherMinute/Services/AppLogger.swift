//
//  AppLogger.swift
//  teacher-minute
//
//  The module's `logger`. It writes to the system log like the `Logger` it
//  wraps, and every `error` is also reported: an `app_error` Analytics event,
//  a Crashlytics log line and a Crashlytics non-fatal. So a failure that is
//  only logged still shows up in both consoles.
//

import Foundation
#if os(Android)
import SkipFuse
#else
import OSLog
#endif

struct AppLogger: Sendable {
  let base: Logger

  init(subsystem: String, category: String) {
    base = Logger(subsystem: subsystem, category: category)
  }

  func debug(_ message: String) {
    #if os(Android)
    base.debug(message)
    #else
    base.debug("\(message, privacy: .public)")
    #endif
  }

  func info(_ message: String) {
    #if os(Android)
    base.info(message)
    #else
    base.info("\(message, privacy: .public)")
    #endif
  }

  func warning(_ message: String) {
    #if os(Android)
    base.warning(message)
    #else
    base.warning("\(message, privacy: .public)")
    #endif
  }

  /// Logs `message` and reports it to Analytics and Crashlytics. The caller's
  /// file and function name the error's source, which is what both consoles
  /// group by; the message itself carries the details.
  func error(_ message: String, file: String = #fileID, function: String = #function) {
    #if os(Android)
    base.error(message)
    #else
    base.error("\(message, privacy: .public)")
    #endif
    let source = AppLogger.source(file: file, function: function)
    Task { @MainActor in
      AnalyticsService.shared.reportError(source: source, message: message, error: nil)
    }
  }

  /// `TeacherMinute/ViewModel/LoginViewModel.swift` + `login(email:)` →
  /// `LoginViewModel.login`.
  static func source(file: String, function: String) -> String {
    let fileName = file.split(separator: "/").last.map(String.init) ?? file
    let typeName = fileName.hasSuffix(".swift") ? String(fileName.dropLast(6)) : fileName
    let functionName = function.split(separator: "(").first.map(String.init) ?? function
    return "\(typeName).\(functionName)"
  }
}

/// `try?` that reports what it swallows: a failure goes to Analytics and
/// Crashlytics as a `logger.error` from the caller would, and the caller still
/// gets `nil`. Cancellation is not a failure and is not reported.
@discardableResult
func attempt<T>(
  isolation: isolated (any Actor)? = #isolation,
  file: String = #fileID,
  function: String = #function,
  _ body: () async throws -> T
) async -> T? {
  do {
    return try await body()
  } catch is CancellationError {
    return nil
  } catch {
    logger.error("attempt failed: \(error.localizedDescription)", file: file, function: function)
    return nil
  }
}

/// `attempt` for a body that already returns an optional, flattened as `try?`
/// flattens it: `nil` for a failure and for a `nil` result alike.
@discardableResult
func attempt<T>(
  isolation: isolated (any Actor)? = #isolation,
  file: String = #fileID,
  function: String = #function,
  _ body: () async throws -> T?
) async -> T? {
  do {
    return try await body()
  } catch is CancellationError {
    return nil
  } catch {
    logger.error("attempt failed: \(error.localizedDescription)", file: file, function: function)
    return nil
  }
}
