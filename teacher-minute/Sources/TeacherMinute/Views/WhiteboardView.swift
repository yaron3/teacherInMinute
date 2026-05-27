import SwiftUI
#if canImport(UIKit) && !os(Android)
import UIKit
#endif

struct WhiteboardView: View {
  static let logicalSize = CGSize(width: 2000, height: 2000)
  static let minZoom: CGFloat = 1.0
  static let maxZoom: CGFloat = 6.0
  
  let strokes: [BoardStroke]
  let revision: String
  let onStrokeFinished: ([CGPoint]) -> Void
  let onClear: () -> Void
  let onViewportChanged: (CGRect) -> Void
  let peerViewport: CGRect?
  @Binding var isMaximized: Bool
  
  @State var activeStroke: [CGPoint] = []
  @State var viewport: CGRect = CGRect(origin: .zero, size: WhiteboardView.logicalSize)
  @State var viewportInitialized = false
  @State var isMoveMode = false
  @State var lastMoveDragTranslation: CGSize = .zero
  
  @Environment(\.horizontalSizeClass) var hSizeClass
  @Environment(\.colorScheme) var colorScheme
  
  init(
	strokes: [BoardStroke],
	revision: String,
	onStrokeFinished: @escaping ([CGPoint]) -> Void,
	onClear: @escaping () -> Void,
	onViewportChanged: @escaping (CGRect) -> Void = { _ in },
	peerViewport: CGRect? = nil,
	isMaximized: Binding<Bool> = .constant(false)
  ) {
	self.strokes = strokes
	self.revision = revision
	self.onStrokeFinished = onStrokeFinished
	self.onClear = onClear
	self.onViewportChanged = onViewportChanged
	self.peerViewport = peerViewport
	self._isMaximized = isMaximized
  }
  
  var theme: AppTheme { AppTheme(colorScheme: colorScheme) }
  var isCompact: Bool { hSizeClass != .regular }
  
  var visibleStrokes: [[CGPoint]] {
	let remote = strokes.map { stroke in
	  stroke.points.map { CGPoint(x: $0.x, y: $0.y) }
	}
	return activeStroke.isEmpty ? remote : remote + [activeStroke]
  }

  func usesScrollableViewport(viewSize: CGSize) -> Bool {
	guard viewSize.width > 0, viewSize.height > 0 else { return isCompact }
	let shortSide = min(viewSize.width, viewSize.height)
	return isCompact || shortSide < 700
  }
  
  var logicalBounds: CGRect {
	let base = CGRect(origin: .zero, size: Self.logicalSize)
	guard let peerViewport else { return base }
	return base.union(peerViewport)
  }
  
  var body: some View {
	VStack(alignment: .leading, spacing: 8) {
	  header
	  
	  GeometryReader { proxy in
		canvas(viewSize: proxy.size)
		  .onAppear { initializeViewportIfNeeded(viewSize: proxy.size) }
		  .onChange(of: proxy.size) { _, newSize in
			initializeViewportIfNeeded(viewSize: newSize, force: true)
		  }
	  }
	  .padding(.horizontal, isMaximized ? 0 : 4)
	  .padding(.bottom, isMaximized ? 0 : 6)
	}
	.padding(.top, isMaximized ? 0 : 10)
	.background(theme.appGrayBackground.opacity(0.35))
  }
  
  var header: some View {
	HStack {
	  Text(LocalizationSupport.localized("Board"))
		.font(.system(size: 13, weight: .bold))
		.foregroundStyle(theme.appPrimaryText)
	  
	  Spacer()
	  
	  Button("Clear") {
		activeStroke.removeAll()
		onClear()
	  }
	  .font(.system(size: 12, weight: .semibold))
	  .foregroundStyle(theme.appPink)
	  
	  if isCompact {
		Button {
		  activeStroke.removeAll()
		  lastMoveDragTranslation = .zero
		  isMoveMode.toggle()
		} label: {
		  PlatformIcon(
			systemName: "hand.raised.fill",
			size: 14,
			weight: .semibold,
			color: isMoveMode ? theme.white : theme.appPrimaryText
		  )
		  .frame(width: 28, height: 28)
		  .background(isMoveMode ? theme.appPink : Color.clear)
		  .clipShape(Circle())
		}
		.buttonStyle(.plain)
		.padding(.leading, 4)
		
		Button {
		  isMaximized.toggle()
		} label: {
		  PlatformIcon(
			systemName: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
			size: 14,
			weight: .semibold,
			color: theme.appPrimaryText
		  )
		  .frame(width: 28, height: 28)
		}
		.buttonStyle(.plain)
		.padding(.leading, 4)
	  }
	}
	.padding(.horizontal, 16)
  }
  
  @ViewBuilder
  func canvas(viewSize: CGSize) -> some View {
	ZStack {
	  theme.appCardBackground
	  
	  if visibleStrokes.isEmpty {
		VStack(spacing: 8) {
		  PlatformIcon(systemName: "pencil", size: 22, weight: .semibold, color: theme.appSecondaryText)
		  Text(LocalizationSupport.localized("Use your finger to write or sketch."))
			.font(.system(size: 12))
			.foregroundStyle(theme.appSecondaryText)
		}
	  }
	  
	  ForEach(visibleStrokes.indices, id: \.self) { index in
		Path { path in
		  let points = visibleStrokes[index].map { logicalToView($0, viewSize: viewSize) }
		  guard let first = points.first else { return }
		  path.move(to: first)
		  for point in points.dropFirst() {
			path.addLine(to: point)
		  }
		}
		.stroke(theme.appPrimaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
	  }
	  
      if let peerViewport, !isCompact {
		let rect = logicalRectToView(peerViewport, viewSize: viewSize)
		Rectangle()
		  .stroke(theme.appPink.opacity(0.55), lineWidth: 2)
		  .frame(width: max(0, rect.width), height: max(0, rect.height))
		  .position(x: rect.midX, y: rect.midY)
		  .allowsHitTesting(false)
	  }
	}
	.id(revision)
	.environment(\.layoutDirection, .leftToRight)
	.clipShape(RoundedRectangle(cornerRadius: isMaximized ? 0 : 14, style: .continuous))
	.overlay {
	  if !isMaximized {
		RoundedRectangle(cornerRadius: 14, style: .continuous)
		  .stroke(theme.appBorder, lineWidth: 1)
	  }
	}
	.overlay(gestureLayer(viewSize: viewSize))
  }
  
  @ViewBuilder
	func gestureLayer(viewSize: CGSize) -> some View {
#if canImport(UIKit) && !os(Android)
	BoardGestureLayer(
	  allowPanZoom: usesScrollableViewport(viewSize: viewSize),
	  isMoveMode: isMoveMode,
	  onDrawBegin: { viewPoint in
		let logical = viewToLogical(viewPoint, viewSize: viewSize)
		activeStroke = [logical]
	  },
	  onDrawChanged: { viewPoint in
		let logical = viewToLogical(viewPoint, viewSize: viewSize)
		activeStroke = activeStroke + [logical]
	  },
	  onDrawEnded: {
		let completed = activeStroke
		activeStroke.removeAll()
		guard !completed.isEmpty else { return }
		onStrokeFinished(completed)
	  },
	  onDrawCancelled: {
		activeStroke.removeAll()
	  },
	  onPan: { translation in
		applyPan(translation: translation, viewSize: viewSize)
	  },
	  onPinch: { scale, center in
		applyPinch(scale: scale, center: center, viewSize: viewSize)
	  }
	)
#else
	Rectangle()
	  .fill(.clear)
	  .gesture(
		DragGesture(minimumDistance: 0)
		  .onChanged { value in
			if isMoveMode {
			  let delta = CGSize(
				width: value.translation.width - lastMoveDragTranslation.width,
				height: value.translation.height - lastMoveDragTranslation.height
			  )
			  lastMoveDragTranslation = value.translation
			  applyPan(translation: delta, viewSize: viewSize)
			  return
			}
			
			let clamped = CGPoint(
			  x: min(max(value.location.x, 0), viewSize.width),
			  y: min(max(value.location.y, 0), viewSize.height)
			)
			let logical = viewToLogical(clamped, viewSize: viewSize)
			if activeStroke.isEmpty {
			  activeStroke = [logical]
			} else {
			  activeStroke = activeStroke + [logical]
			}
		  }
		  .onEnded { _ in
			lastMoveDragTranslation = .zero
			guard !isMoveMode else { return }
			
			let completed = activeStroke
			activeStroke.removeAll()
			guard !completed.isEmpty else { return }
			onStrokeFinished(completed)
		  }
	  )
#endif
  }
  
  // MARK: - Coordinate conversion
  
  func logicalToView(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
	guard viewport.width > 0, viewport.height > 0 else { return .zero }
	return CGPoint(
	  x: (point.x - viewport.origin.x) * viewSize.width / viewport.width,
	  y: (point.y - viewport.origin.y) * viewSize.height / viewport.height
	)
  }
  
  func viewToLogical(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
	guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
	return CGPoint(
	  x: viewport.origin.x + point.x * viewport.width / viewSize.width,
	  y: viewport.origin.y + point.y * viewport.height / viewSize.height
	)
  }
  
  func logicalRectToView(_ rect: CGRect, viewSize: CGSize) -> CGRect {
	let topLeft = logicalToView(rect.origin, viewSize: viewSize)
	let bottomRight = logicalToView(CGPoint(x: rect.maxX, y: rect.maxY), viewSize: viewSize)
	return CGRect(
	  x: topLeft.x,
	  y: topLeft.y,
	  width: bottomRight.x - topLeft.x,
	  height: bottomRight.y - topLeft.y
	)
  }
  
  // MARK: - Viewport management
  
  func initializeViewportIfNeeded(viewSize: CGSize, force: Bool = false) {
	guard viewSize.width > 0, viewSize.height > 0 else { return }
	if viewportInitialized && !force { return }
	viewportInitialized = true
	
	let logical = Self.logicalSize
	let bounds = logicalBounds
	let viewAspect = viewSize.width / viewSize.height
	let boardAspect = logical.width / logical.height
	
	let viewportSize: CGSize
	if usesScrollableViewport(viewSize: viewSize) {
	  // Keep the visible board window smaller than the full board on both axes
	  // so move mode can pan vertically as well as horizontally.
	  let moveModeScale: CGFloat = 0.45
	  if viewAspect > boardAspect {
		viewportSize = CGSize(
		  width: logical.width * moveModeScale,
		  height: logical.width * moveModeScale / viewAspect
		)
	  } else {
		viewportSize = CGSize(
		  width: logical.height * moveModeScale * viewAspect,
		  height: logical.height * moveModeScale
		)
	  }
	} else {
	  // iPad / regular size class: show full board letterboxed.
	  if viewAspect > boardAspect {
		viewportSize = CGSize(width: logical.height * viewAspect, height: logical.height)
	  } else {
		viewportSize = CGSize(width: logical.width, height: logical.width / viewAspect)
	  }
	}
	
	let viewportOriginY: CGFloat = usesScrollableViewport(viewSize: viewSize)
	  ? bounds.minY
	  : (logical.height - viewportSize.height) / 2
	viewport = CGRect(
	  x: usesScrollableViewport(viewSize: viewSize)
		? bounds.midX - viewportSize.width / 2
		: (logical.width - viewportSize.width) / 2,
	  y: viewportOriginY,
	  width: viewportSize.width,
	  height: viewportSize.height
	)
	onViewportChanged(viewport)
  }
  
  func applyPan(translation: CGSize, viewSize: CGSize) {
	guard usesScrollableViewport(viewSize: viewSize), viewSize.width > 0, viewSize.height > 0 else { return }
	let dxLogical = -translation.width * viewport.width / viewSize.width
	let dyLogical = -translation.height * viewport.height / viewSize.height
	let proposed = CGRect(
	  x: viewport.origin.x + dxLogical,
	  y: viewport.origin.y + dyLogical,
	  width: viewport.width,
	  height: viewport.height
	)
	viewport = clampedViewport(proposed)
	onViewportChanged(viewport)
  }
  
  func applyPinch(scale: CGFloat, center: CGPoint, viewSize: CGSize) {
	guard usesScrollableViewport(viewSize: viewSize), viewSize.width > 0, viewSize.height > 0 else { return }
	let logical = Self.logicalSize
	let currentZoom = logical.width / viewport.width
	let targetZoom = max(Self.minZoom, min(Self.maxZoom, currentZoom * scale))
	let newWidth = logical.width / targetZoom
	let newHeight = newWidth * (viewport.height / viewport.width)
	
	let focusLogical = viewToLogical(center, viewSize: viewSize)
	let fractionX = (focusLogical.x - viewport.origin.x) / max(viewport.width, 0.001)
	let fractionY = (focusLogical.y - viewport.origin.y) / max(viewport.height, 0.001)
	
	let proposed = CGRect(
	  x: focusLogical.x - fractionX * newWidth,
	  y: focusLogical.y - fractionY * newHeight,
	  width: newWidth,
	  height: newHeight
	)
	viewport = clampedViewport(proposed)
	onViewportChanged(viewport)
  }
  
  func clampedViewport(_ rect: CGRect) -> CGRect {
	let bounds = logicalBounds
	var r = rect
	let maxX = max(bounds.minX, bounds.maxX - r.width)
	let maxY = max(bounds.minY, bounds.maxY - r.height)
	r.origin.x = min(max(r.origin.x, bounds.minX), maxX)
	r.origin.y = min(max(r.origin.y, bounds.minY), maxY)
	return r
  }
}

#if canImport(UIKit) && !os(Android)
private struct BoardGestureLayer: UIViewRepresentable {
  let allowPanZoom: Bool
  let isMoveMode: Bool
  let onDrawBegin: (CGPoint) -> Void
  let onDrawChanged: (CGPoint) -> Void
  let onDrawEnded: () -> Void
  let onDrawCancelled: () -> Void
  let onPan: (CGSize) -> Void
  let onPinch: (CGFloat, CGPoint) -> Void
  
  func makeCoordinator() -> Coordinator {
	Coordinator(
	  onDrawBegin: onDrawBegin,
	  onDrawChanged: onDrawChanged,
	  onDrawEnded: onDrawEnded,
	  onDrawCancelled: onDrawCancelled,
	  onPan: onPan,
	  onPinch: onPinch
	)
  }
  
  func makeUIView(context: Context) -> UIView {
	let view = BoardGestureUIView()
	view.backgroundColor = .clear
	view.isMultipleTouchEnabled = true
	view.coordinator = context.coordinator
	
	let drawPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDraw(_:)))
	drawPan.minimumNumberOfTouches = 1
	drawPan.maximumNumberOfTouches = 1
	drawPan.delegate = context.coordinator
	view.addGestureRecognizer(drawPan)
	context.coordinator.drawRecognizer = drawPan
	
	let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
	twoFingerPan.minimumNumberOfTouches = 2
	twoFingerPan.maximumNumberOfTouches = 2
	twoFingerPan.delegate = context.coordinator
	view.addGestureRecognizer(twoFingerPan)
	context.coordinator.panRecognizer = twoFingerPan
	
	let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
	pinch.delegate = context.coordinator
	view.addGestureRecognizer(pinch)
	context.coordinator.pinchRecognizer = pinch
	
	return view
  }
  
  func updateUIView(_ uiView: UIView, context: Context) {
	context.coordinator.allowPanZoom = allowPanZoom
	context.coordinator.isMoveMode = isMoveMode
	context.coordinator.onDrawBegin = onDrawBegin
	context.coordinator.onDrawChanged = onDrawChanged
	context.coordinator.onDrawEnded = onDrawEnded
	context.coordinator.onDrawCancelled = onDrawCancelled
	context.coordinator.onPan = onPan
	context.coordinator.onPinch = onPinch
	context.coordinator.panRecognizer?.isEnabled = allowPanZoom
	context.coordinator.pinchRecognizer?.isEnabled = allowPanZoom
  }
  
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
	var allowPanZoom: Bool = true
	var isMoveMode: Bool = false
	var onDrawBegin: (CGPoint) -> Void
	var onDrawChanged: (CGPoint) -> Void
	var onDrawEnded: () -> Void
	var onDrawCancelled: () -> Void
	var onPan: (CGSize) -> Void
	var onPinch: (CGFloat, CGPoint) -> Void
	weak var drawRecognizer: UIPanGestureRecognizer?
	weak var panRecognizer: UIPanGestureRecognizer?
	weak var pinchRecognizer: UIPinchGestureRecognizer?
	
	init(
	  onDrawBegin: @escaping (CGPoint) -> Void,
	  onDrawChanged: @escaping (CGPoint) -> Void,
	  onDrawEnded: @escaping () -> Void,
	  onDrawCancelled: @escaping () -> Void,
	  onPan: @escaping (CGSize) -> Void,
	  onPinch: @escaping (CGFloat, CGPoint) -> Void
	) {
	  self.onDrawBegin = onDrawBegin
	  self.onDrawChanged = onDrawChanged
	  self.onDrawEnded = onDrawEnded
	  self.onDrawCancelled = onDrawCancelled
	  self.onPan = onPan
	  self.onPinch = onPinch
	}
	
	@objc func handleDraw(_ gesture: UIPanGestureRecognizer) {
	  guard let view = gesture.view else { return }
	  if isMoveMode {
		switch gesture.state {
		  case .began:
			onDrawCancelled()
			gesture.setTranslation(.zero, in: view)
		  case .changed:
			guard allowPanZoom else { return }
			let translation = gesture.translation(in: view)
			logger.info("translation x: \(translation.x), y: \(translation.y)")
			onPan(CGSize(width: translation.x, height: translation.y))
			gesture.setTranslation(.zero, in: view)
		  default:
			break
		}
		return
	  }
	  
	  let point = gesture.location(in: view)
	  switch gesture.state {
		case .began:
		  onDrawBegin(point)
		case .changed:
		  onDrawChanged(point)
		case .ended:
		  onDrawEnded()
		case .cancelled, .failed:
		  onDrawCancelled()
		default:
		  break
	  }
	}
	
	@objc func handlePan(_ gesture: UIPanGestureRecognizer) {
	  guard allowPanZoom, let view = gesture.view else { return }
	  switch gesture.state {
		case .changed:
		  let translation = gesture.translation(in: view)
		  onPan(CGSize(width: translation.x, height: translation.y))
		  gesture.setTranslation(.zero, in: view)
		default:
		  break
	  }
	}
	
	@objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
	  guard allowPanZoom, let view = gesture.view else { return }
	  switch gesture.state {
		case .changed:
		  let center = gesture.location(in: view)
		  onPinch(gesture.scale, center)
		  gesture.scale = 1.0
		default:
		  break
	  }
	}
	
	func gestureRecognizer(
	  _ gestureRecognizer: UIGestureRecognizer,
	  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
	) -> Bool {
	  // Allow 2-finger pan and pinch to fire together; keep draw exclusive.
	  if gestureRecognizer === drawRecognizer || other === drawRecognizer {
		return false
	  }
	  return true
	}
  }
}

private final class BoardGestureUIView: UIView {
  weak var coordinator: BoardGestureLayer.Coordinator?
}
#endif
