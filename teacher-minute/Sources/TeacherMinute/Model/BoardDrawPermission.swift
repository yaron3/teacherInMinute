import Foundation

/// The student's leave to draw on the board, as the two sides pass it back and
/// forth at `questions/{qid}/boardPermission`.
///
/// The student asks by writing `requested` under a fresh `requestId`; the
/// teacher answers by writing `granted` or `declined` under the same id. Each
/// request carries its own id so a second ask, after a decline or after a grant
/// ran out, reads as new on the teacher's side rather than as the old one.
///
/// How long a grant lasts is not written here: the student's app keeps that
/// window itself, restarting it with every stroke (see
/// `ChatSessionViewModel.boardDrawWindowSeconds`), so neither side has to trust
/// the other's clock.
struct BoardDrawPermission: Equatable {
  enum Status: String {
    case requested, granted, declined
  }

  var status: Status
  var requestId: String

  init(status: Status, requestId: String) {
    self.status = status
    self.requestId = requestId
  }

  /// Reads the node as written by either app; nil for anything incomplete.
  init?(dictionary: [String: Any]) {
    guard let rawStatus = dictionary["status"] as? String,
          let status = Status(rawValue: rawStatus),
          let requestId = dictionary["requestId"] as? String,
          !requestId.isEmpty else { return nil }
    self.status = status
    self.requestId = requestId
  }
}

/// Where the student's own ask to draw stands, as the board shows it.
enum BoardDrawRequestState: Equatable {
  /// Nothing asked, or the last ask has been dealt with.
  case none
  /// Asked, and the teacher has not answered yet.
  case pending
}
