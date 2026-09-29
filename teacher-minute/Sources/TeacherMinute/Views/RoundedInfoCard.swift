//
//  RoundedInfoCard.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

/// A card of details — a lesson's, a message's — in the brand's card style.
struct RoundedInfoCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .brandCard(cornerRadius: 16, padding: 18)
  }
}
