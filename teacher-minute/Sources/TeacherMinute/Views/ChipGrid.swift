//
//  ChipGrid.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct ChipGrid<Content: View>: View {
    let minimumItemWidth: CGFloat
    let spacing: CGFloat
    let content: Content

    init(
        minimumItemWidth: CGFloat = 105,
        spacing: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumItemWidth = minimumItemWidth
        self.spacing = spacing
        self.content = content()
    }

    var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: minimumItemWidth),
                spacing: spacing,
                alignment: .leading
            )
        ]
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            content
        }
    }
}
