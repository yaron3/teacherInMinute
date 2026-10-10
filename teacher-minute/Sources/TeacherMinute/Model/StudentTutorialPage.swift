//
//  StudentTutorialPage.swift
//  teacher-minute
//
//  One page of Instant Teacher's tutorial: a picture, a title, and either a
//  line or two under it or, for a screenshot of the app, numbered callouts
//  that point at its controls. Like `HowItWorksStep` it carries only copy and
//  asset names; the view decides how each kind of picture is drawn.
//

import Foundation

struct StudentTutorialPage {
  enum Art {
    /// One of the brand's character renders, drawn large.
    case character(String)
    /// A line icon from the brand's set, drawn in a tinted circle.
    case icon(String)
    /// A screenshot of the app, in the language on screen, with the page's
    /// callouts numbered over it.
    case screenshot(String)
  }

  /// A numbered marker on a screenshot and the line explaining it. `x` and
  /// `y` place the marker as fractions of the screenshot's width and height,
  /// from its top left corner in either language.
  struct Callout {
    let text: String
    let x: Double
    let y: Double
  }

  let art: Art
  let title: String
  var body: String = ""
  var callouts: [Callout] = []
}
