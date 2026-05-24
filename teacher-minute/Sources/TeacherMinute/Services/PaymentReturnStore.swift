import Foundation
import Observation

enum PaymentReturnStatus {
    case success
    case failed
    case cancelled
    case noResponse
    case unknown(String)

    init(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "success", "succeeded", "paid", "approved", "completed", "complete":
            self = .success
        case "fail", "failed", "failure", "error", "denied", "declined":
            self = .failed
        case "cancel", "cancelled", "canceled", "user_cancelled", "user_canceled":
            self = .cancelled
        case "no_response", "noresponse", "incomplete", "not_completed":
            self = .noResponse
        default:
            self = .unknown(normalized.isEmpty ? rawValue : normalized)
        }
    }
}

struct PaymentReturnResult: Identifiable {
    let id = UUID()
    let status: PaymentReturnStatus
    let sessionID: String?
    let orderID: String?
    let rawURL: URL

    var title: String {
        switch status {
        case .success:
            LocalizationSupport.localized("Payment Complete")
        case .failed:
            LocalizationSupport.localized("Payment Failed")
        case .cancelled:
            LocalizationSupport.localized("Payment Cancelled")
        case .noResponse:
            LocalizationSupport.localized("Payment Confirmation Pending")
        case .unknown:
            LocalizationSupport.localized("Payment Update")
        }
    }

    var message: String {
        switch status {
        case .success:
            return LocalizationSupport.localized("Your payment was completed successfully.")
        case .failed:
            return LocalizationSupport.localized("The payment did not complete. Please try again.")
        case .cancelled:
            return LocalizationSupport.localized("No payment was taken. You can choose a plan again when you are ready")
        case .noResponse:
            return LocalizationSupport.localized("We have not received PayPal confirmation yet. If payment was approved, your account will update after PayPal confirms it.")
        case .unknown(let rawStatus):
            let format = LocalizationSupport.localized("Payment returned with status: %@")
            return String(format: format, rawStatus.isEmpty ? LocalizationSupport.localized("Unknown") : rawStatus)
        }
    }

    static func noResponse() -> PaymentReturnResult {
        PaymentReturnResult(
            status: .noResponse,
            sessionID: nil,
            orderID: nil,
            rawURL: URL(string: "teacherminute://payment-return?status=no_response") ?? URL(fileURLWithPath: "/")
        )
    }

    static func cancelledWithoutReturnURL() -> PaymentReturnResult {
        PaymentReturnResult(
            status: .cancelled,
            sessionID: nil,
            orderID: nil,
            rawURL: URL(string: "teacherminute://payment-return?status=cancelled&source=missing_return") ?? URL(fileURLWithPath: "/")
        )
    }

    static func confirmedWithoutReturnURL() -> PaymentReturnResult {
        PaymentReturnResult(
            status: .success,
            sessionID: nil,
            orderID: nil,
            rawURL: URL(string: "teacherminute://payment-return?status=success&source=balance_refresh") ?? URL(fileURLWithPath: "/")
        )
    }

    private init(status: PaymentReturnStatus, sessionID: String?, orderID: String?, rawURL: URL) {
        self.status = status
        self.sessionID = sessionID
        self.orderID = orderID
        self.rawURL = rawURL
    }

    init?(url: URL) {
        guard url.scheme == "teacherminute" || url.host == "teacherminute.app" else {
            logger.info("[PaymentReturn] ignored URL scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil")")
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        var query: [String: String] = [:]
        for item in queryItems {
            query[item.name.lowercased()] = item.value ?? ""
        }
        let pathStatus = url.pathComponents.dropFirst().first ?? ""
        let hostStatus = url.host == "payment-return" ? "" : (url.host ?? "")
        let rawStatus = query["status"]
            ?? query["result"]
            ?? query["paymentstatus"]
            ?? query["payment_status"]
            ?? (pathStatus.isEmpty ? nil : pathStatus)
            ?? (hostStatus.isEmpty ? nil : hostStatus)
            ?? "unknown"

        let parsedStatus = PaymentReturnStatus(rawValue: rawStatus)
        let parsedSessionID = query["sessionid"] ?? query["session_id"]
        let parsedOrderID = query["orderid"] ?? query["order_id"] ?? query["token"]
        logger.info("[PaymentReturn] parsed url=\(url.absoluteString) rawStatus=\(rawStatus) sessionID=\(parsedSessionID ?? "nil") orderID=\(parsedOrderID ?? "nil")")

        self.status = parsedStatus
        self.sessionID = parsedSessionID
        self.orderID = parsedOrderID
        self.rawURL = url
    }
}

@Observable
@MainActor
final class PaymentReturnStore {
    static let shared = PaymentReturnStore()

    var latestResult: PaymentReturnResult?
    var resultVersion = 0

    private init() {}

    func handle(url: URL) {
        logger.info("[PaymentReturn] received openURL=\(url.absoluteString)")
        guard let result = PaymentReturnResult(url: url) else { return }
        latestResult = result
        resultVersion += 1
        logger.info("[PaymentReturn] stored resultVersion=\(self.resultVersion) status=\(String(describing: result.status))")
    }

    func handleMissingReturn() {
        logger.info("[PaymentReturn] no deep link result received; storing cancelledWithoutReturnURL")
        latestResult = .cancelledWithoutReturnURL()
        resultVersion += 1
    }

    func handleConfirmedWithoutReturnURL() {
        logger.info("[PaymentReturn] payment confirmed by balance refresh without deep link")
        latestResult = .confirmedWithoutReturnURL()
        resultVersion += 1
    }

    func consumeLatestResult() {
        logger.info("[PaymentReturn] consuming latest result")
        latestResult = nil
        resultVersion += 1
    }
}
