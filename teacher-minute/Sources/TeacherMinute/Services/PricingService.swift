//
//  PricingService.swift
//  teacher-minute
//
//  Fetches the pricing catalog from Firestore (`pricing` collection).
//

import Foundation

#if !os(Android)
import FirebaseFirestore
#else
import SkipFirebaseFirestore
#endif

@MainActor
final class PricingService {
    static let shared = PricingService()

    private init() {}

    /// Returns all active pricing tiers from the `pricing` collection,
    /// sorted by `sortOrder` ascending.
    func fetchPricingOptions() async throws -> [PricingOption] {
        let snapshot = try await Firestore.firestore()
            .collection("pricing")
            .getDocuments()

        var options: [PricingOption] = []
        for doc in snapshot.documents {
            if let option = Self.makeOption(id: doc.documentID, data: doc.data()) {
                options.append(option)
            }
        }
        return options.sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func makeOption(id: String, data: [String: Any]) -> PricingOption? {
        let name = Self.string(data["name"])
        guard !name.isEmpty else { return nil }

        let priceCents: Int
        if let cents = intValue(data["priceCents"]) {
            priceCents = cents
        } else if let amount = doubleValue(data["price"]) {
            priceCents = Int((amount * 100.0).rounded())
        } else {
            priceCents = 0
        }

        let currency = {
            let raw = Self.string(data["currency"])
            return raw.isEmpty ? "USD" : raw
        }()

        let typeRaw = Self.string(data["type"])
        let type = PricingType(rawValue: typeRaw) ?? .payAsYouGo

        let description = Self.string(data["description"])
        let isHighlighted = (data["isHighlighted"] as? Bool) ?? false
        let sortOrder = intValue(data["sortOrder"]) ?? 0
        let purchaseSKU: String? = {
            let raw = Self.string(data["purchaseSKU"])
            return raw.isEmpty ? nil : raw
        }()

        return PricingOption(
            id: id,
            name: name,
            priceCents: priceCents,
            currency: currency,
            type: type,
            description: description,
            isHighlighted: isHighlighted,
            sortOrder: sortOrder,
            purchaseSKU: purchaseSKU
        )
    }

    private static func string(_ value: Any?) -> String {
        guard let value = value as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        if let value = value as? Double { return Int(value) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
