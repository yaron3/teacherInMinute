import SwiftUI

struct WhiteboardView: View {
  let strokes: [BoardStroke]
  let revision: String
  let onStrokeFinished: ([CGPoint]) -> Void
  let onClear: () -> Void
  @State var activeStroke: [CGPoint] = []

  var visibleStrokes: [[CGPoint]] {
    let remoteStrokes = strokes.map { stroke in
      stroke.points.map { CGPoint(x: $0.x, y: $0.y) }
    }
    return activeStroke.isEmpty ? remoteStrokes : remoteStrokes + [activeStroke]
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Board")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(theme.appPrimaryText)

        Spacer()

        Button("Clear") {
          activeStroke.removeAll()
          onClear()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(theme.appPink)
      }
      .padding(.horizontal, 16)

      GeometryReader { proxy in
        ZStack {
          theme.white

          if visibleStrokes.isEmpty {
            VStack(spacing: 8) {
              PlatformIcon(systemName: "pencil", size: 22, weight: .semibold, color: theme.appSecondaryText)
              Text("Use your finger to write or sketch.")
                .font(.system(size: 12))
                .foregroundStyle(theme.appSecondaryText)
            }
          }

          ForEach(visibleStrokes.indices, id: \.self) { index in
            Path { path in
              let points = visibleStrokes[index]
              guard let first = points.first else { return }
              path.move(to: first)
              for point in points.dropFirst() {
                path.addLine(to: point)
              }
            }
            .stroke(theme.appPrimaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          }
        }
        .id(revision)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(theme.appBorder, lineWidth: 1)
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let point = CGPoint(
                x: min(max(value.location.x, 0), proxy.size.width),
                y: min(max(value.location.y, 0), proxy.size.height)
              )
              if activeStroke.isEmpty {
                activeStroke = [point]
              } else {
                activeStroke = activeStroke + [point]
              }
            }
            .onEnded { _ in
              let completedStroke = activeStroke
              activeStroke.removeAll()
              onStrokeFinished(completedStroke)
            }
        )
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 14)
    }
    .padding(.top, 10)
    .background(theme.appGrayBackground.opacity(0.35))
  }
}
