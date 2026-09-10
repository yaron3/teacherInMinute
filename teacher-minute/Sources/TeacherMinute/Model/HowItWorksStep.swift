//
//  HowItWorksStep.swift
//  teacher-minute
//
//  One step of a "How it works" panel. It carries only copy: the step's
//  number and its accent colour follow from where it sits in the array, so a
//  view model supplies the steps in order and never has to know the theme.
//

import Foundation

struct HowItWorksStep {
    let title: String
    let subtitle: String
}
