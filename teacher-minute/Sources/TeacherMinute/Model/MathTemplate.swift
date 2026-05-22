//
//  MathTemplate.swift
//  teacher-minute
//
//  Templates and parameter-aware LaTeX rendering for common equations.
//

import Foundation

struct MathTemplateField: Identifiable, Hashable {
    let key: String
    let label: String
    let placeholder: String
    var id: String { key }
}

enum MathTemplate: String, CaseIterable, Identifiable {
    case freeform = "freeform"
    case hyperbolaHorizontal = "hyperbola_horizontal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freeform:
            return "Free Equation"
        case .hyperbolaHorizontal:
            return "Hyperbola (Horizontal)"
        }
    }

    var hint: String {
        switch self {
        case .freeform:
            return "Build the equation with the math keyboard."
        case .hyperbolaHorizontal:
            return "(x - h)²/a² − (y - k)²/b² = 1"
        }
    }

    var fields: [MathTemplateField] {
        switch self {
        case .freeform:
            return []
        case .hyperbolaHorizontal:
            return [
                MathTemplateField(key: "h", label: "h", placeholder: "2"),
                MathTemplateField(key: "k", label: "k", placeholder: "-5"),
                MathTemplateField(key: "a2", label: "a²", placeholder: "36"),
                MathTemplateField(key: "b2", label: "b²", placeholder: "81"),
            ]
        }
    }

    func render(values: [String: String]) -> String {
        switch self {
        case .freeform:
            return ""
        case .hyperbolaHorizontal:
            let h = values["h"] ?? ""
            let k = values["k"] ?? ""
            let a2 = MathTemplate.cleanedDenominator(values["a2"] ?? "")
            let b2 = MathTemplate.cleanedDenominator(values["b2"] ?? "")
            let xPart = MathTemplate.signedTerm(variable: "x", value: h)
            let yPart = MathTemplate.signedTerm(variable: "y", value: k)
            return "\\frac{\(xPart)^{2}}{\(a2)} - \\frac{\(yPart)^{2}}{\(b2)} = 1"
        }
    }

    // Renders "(variable - n)" or "(variable + |n|)" depending on sign.
    private static func signedTerm(variable: String, value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "(\(variable))"
        }
        if let num = Double(trimmed) {
            if num < 0 {
                let abs = -num
                return "(\(variable) + \(MathTemplate.formatNumber(abs)))"
            } else {
                return "(\(variable) - \(MathTemplate.formatNumber(num)))"
            }
        }
        if trimmed.hasPrefix("-") {
            let rest = String(trimmed.dropFirst())
            return "(\(variable) + \(rest))"
        }
        return "(\(variable) - \(trimmed))"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }

    // Denominator can be entered as a raw number ("36") or a power ("6^2").
    private static func cleanedDenominator(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : trimmed
    }
}
