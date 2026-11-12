//
//  ProTeacherEarningsUITests.swift
//  TeacherMinuteUITests
//
//  Pro Teacher's payout method, against the real backend on the local Firebase
//  emulators (updateTeacherPayoutMethod validates it there). QA test plan:
//
//   IOS-M-08  a bank account, then Bit, set in turn from Earnings: each saved
//             to users/{uid}.payoutMethod and shown on the card; a branch
//             number the backend refuses shows its error and saves nothing;
//             a malformed Bit number or PayPal address cannot be saved
//
//  PayPal is offered only when the app's Remote Config says so; when it is,
//  the form's check on the address is tested, but no address is saved — the
//  backend looks the address's mail server up on the network.
//
//  IOS-M-07 (the lesson's amount on the Earnings screen) runs with the live
//  lesson, in ProTeacherLessonUITests.
//

import XCTest

final class ProTeacherEarningsUITests: ProTeacherEmulatorTestCase {

    /// IOS-M-08.
    @MainActor
    func testSettingABankAccountThenBit() async throws {
        try await signInAsNewTeacher()
        settleAfterSignIn()
        try openEarnings()

        // A bank account with a one-digit branch: the form lets it through,
        // the backend refuses it.
        try openPayoutForm()
        try require(tapWhenHittable(app.buttons["payout_method_type_bank"], "Bank transfer"), "no bank transfer option")
        let bank = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'payout_bank_'")).firstMatch
        try require(tapWhenHittable(bank, "a bank"), "no bank to choose")
        let bankCode = String(bank.identifier.dropFirst("payout_bank_".count))
        try fill("payout_branch_number", with: "1")
        try fill("payout_account_number", with: "12345678")
        try fill("payout_account_holder", with: "Emulator Teacher")
        try save()
        try require(app.staticTexts["payout_method_error"].waitForExistence(timeout: 20),
                    "a one-digit branch number was not refused")
        let refused = try await payoutMethod()
        XCTAssertNil(refused, "a refused bank account was saved: \(refused ?? [:])")

        try fill("payout_branch_number", with: "123")
        try save()
        try require(waitForDisappearance(app.buttons["payout_method_save"], timeout: 20), "saving the bank account did not close the form")
        let savedBank = try await waitForPayoutMethod(type: "bank")
        XCTAssertEqual(savedBank["bankCode"] as? String, bankCode)
        XCTAssertEqual(savedBank["branchNumber"] as? String, "123")
        XCTAssertEqual(savedBank["accountNumber"] as? String, "12345678")
        XCTAssertEqual(savedBank["accountHolderName"] as? String, "Emulator Teacher")
        try expectSummary(containing: "5678")

        // Bit: a malformed number cannot be saved; a good one replaces the bank.
        try openPayoutForm()
        try require(tapWhenHittable(app.buttons["payout_method_type_bit"], "Bit"), "no Bit option")
        try fill("payout_bit_phone", with: "12")
        XCTAssertFalse(app.buttons["payout_method_save"].isEnabled, "a malformed Bit number could be saved")
        try fill("payout_bit_phone", with: "0501234567")
        try save()
        // Offered to put the number on the profile too: not now.
        _ = waitForAny([app.buttons["dialog_cancel_button"]], timeout: 5)
        _ = tapIfPresent(app.buttons["dialog_cancel_button"])
        try require(waitForDisappearance(app.buttons["payout_method_save"], timeout: 20), "saving Bit did not close the form")
        let savedBit = try await waitForPayoutMethod(type: "bit")
        XCTAssertEqual(savedBit["phone"] as? String, "0501234567")
        XCTAssertNil(savedBit["accountNumber"], "switching to Bit left the bank account behind")
        try expectSummary(containing: "0501234567")

        // PayPal, when offered: a malformed address cannot be saved.
        try openPayoutForm()
        if app.buttons["payout_method_type_paypal"].waitForExistence(timeout: 3) {
            try require(tapWhenHittable(app.buttons["payout_method_type_paypal"], "PayPal"), "PayPal could not be chosen")
            try fill("payout_paypal_email", with: "not-an-address")
            XCTAssertFalse(app.buttons["payout_method_save"].isEnabled, "a malformed PayPal address could be saved")
        } else {
            attach("PayPal", "not offered: enable_paypal_payout is off in Remote Config")
        }
    }

    // MARK: - Steps

    @MainActor
    private func openEarnings() throws {
        let edit = app.buttons["earnings_payout_method_edit"]
        // Tapped again until Earnings opens: a tap while a sheet closes misses.
        for _ in 0..<4 where !edit.exists {
            try require(tapWhenHittable(app.buttons["tab_item_earnings"], "the Earnings tab"), "no Earnings tab")
            _ = edit.waitForExistence(timeout: 8)
        }
        try require(edit.exists, "Earnings has no way to set a payout method")
    }

    @MainActor
    private func openPayoutForm() throws {
        try require(tapWhenHittable(app.buttons["earnings_payout_method_edit"], "the payout method's edit"), "the payout method could not be edited")
        try require(app.buttons["payout_method_save"].waitForExistence(timeout: 15), "the payout form did not open")
    }

    /// Replaces whatever the field holds with `text`.
    @MainActor
    private func fill(_ id: String, with text: String) throws {
        let field = app.textFields[id]
        try require(field.waitForExistence(timeout: 10), "no \(id) field")
        for _ in 0..<3 where !field.isHittable { app.swipeUp() }
        try require(tapWhenHittable(field, id), "\(id) was never tappable")
        clear(field)
        field.typeText(text)
    }

    @MainActor
    private func save() throws {
        dismissKeyboard()
        let save = app.buttons["payout_method_save"]
        for _ in 0..<3 where !save.isHittable { app.swipeUp() }
        try require(save.isEnabled, "Save is not enabled")
        try require(tapWhenHittable(save, "Save"), "Save was never tappable")
    }

    @MainActor
    private func expectSummary(containing text: String) throws {
        let summary = app.staticTexts["earnings_payout_method_summary"]
        try require(summary.waitForExistence(timeout: 15), "the payout method card shows no summary")
        let deadline = Date().addingTimeInterval(15)
        while !summary.label.contains(text) && Date() < deadline { pause(seconds: 0.5) }
        XCTAssertTrue(summary.label.contains(text), "the card shows \"\(summary.label)\", not \(text)")
    }

    /// users/{uid}.payoutMethod as plain values, or nil when none is saved.
    private func payoutMethod() async throws -> [String: Any]? {
        let fields = try await backend.fields("users/\(appTeacher.uid)") ?? [:]
        guard let map = ((fields["payoutMethod"] as? [String: Any])?["mapValue"] as? [String: Any])?["fields"] as? [String: Any]
        else { return nil }
        return map.compactMapValues { ($0 as? [String: Any])?["stringValue"] ?? ($0 as? [String: Any])?["booleanValue"] }
    }

    private func waitForPayoutMethod(type: String) async throws -> [String: Any] {
        for _ in 0..<40 {
            if let method = try await payoutMethod(), method["type"] as? String == type { return method }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw Failed("no \(type) payout method was saved")
    }

    @MainActor
    private func settleAfterSignIn() {
        let sheet = app.sheets["Save Password?"]
        if sheet.waitForExistence(timeout: 20) {
            _ = tapIfPresent(sheet.buttons["Not Now"])
            pause(seconds: 1)
        }
    }

    @MainActor
    private func require(_ condition: Bool, _ message: String) throws {
        guard !condition else { return }
        attach("screen", app?.debugDescription ?? "no app")
        throw Failed(message)
    }

    private struct Failed: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
