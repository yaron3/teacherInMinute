import SwiftUI
#if !os(Android)
import LiveKit
#endif

// The lesson's frame on the brand design — what surrounds the chat, the board
// and the question's photos. `ChatSessionView` keeps the state and decides which
// pane shows; this puts the toggle above it and the clock, the people and the
// mascot below.

extension ChatSessionView {

  // MARK: Frame

  /// The panes' common frame: the toggle on top, the panel the pane sits in,
  /// and the bottom bar overlapping the panel's lower edge.
  func sessionFrame<Content: View>(
    showsBottomBar: Bool = true,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(spacing: 0) {
      sessionTopBar

      sessionTypePicker

      sessionConditionNotice

      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(theme.accentBackground)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.bottom, 6)
      }

      ZStack(alignment: .bottom) {
        sessionPanel(leavesRoomForBar: showsBottomBar)

        VStack(spacing: 0) {
          content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          if showsBottomBar {
            sessionBottomBar
          }
        }
      }
    }
    .background {
      BrandScreenBackground(streaks: .session)
    }
  }

  /// The dark panel with its dot grid. It runs off both sides of the screen, so
  /// only its top and bottom edges are drawn; the bar below overlaps its lower
  /// 24pt, and the strip beneath that is left to the background.
  func sessionPanel(leavesRoomForBar: Bool) -> some View {
    VStack(spacing: 0) {
      ZStack {
        theme.brandPanelBackground
        DotGrid(origin: CGPoint(x: 6, y: 7))
          .fill(theme.brandPanelDot)
          .environment(\.layoutDirection, .leftToRight)
      }
      .overlay(alignment: .top) {
        Rectangle().fill(theme.brandControlBorder).frame(height: 1)
      }
      .overlay(alignment: .bottom) {
        Rectangle().fill(theme.brandControlBorder).frame(height: 1)
      }
      .frame(maxHeight: .infinity)

      if leavesRoomForBar {
        Color.clear.frame(height: 48)
      }
    }
  }

  // MARK: Top

  var sessionToggleItems: [SessionToggleItem] {
    var items = [
      SessionToggleItem(
        id: .CHAT,
        title: viewModel.chatTabTitle,
        iconName: "session-chat",
        showsBadge: viewModel.hasUnreadChat
      ),
      SessionToggleItem(
        id: .BOARD,
        title: viewModel.boardTabTitle,
        iconName: "session-chalkboard",
        showsBadge: viewModel.hasUnreadBoard
      ),
    ]
    if !viewModel.questionPhotoUrls.isEmpty {
      items.append(
        SessionToggleItem(
          id: .IMAGES,
          title: viewModel.imagesTabTitle,
          iconName: "home-camera",
          showsBadge: false
        )
      )
    }
    return items
  }

  var sessionTopBar: some View {
    SessionTopBar(
      items: sessionToggleItems,
      selected: selectedTab,
      closeAccessibilityLabel: viewModel.endLabel,
      onSelect: { tab in selectSessionTab(tab) },
      onClose: { requestEndSession() }
    )
  }

  // MARK: Bottom

  var sessionBottomBar: some View {
    SessionBottomBar(
      media: SessionMediaControl(
        label: viewModel.mediaLabel,
        value: mediaValueText,
        actions: mediaActions,
        isExpanded: $isMediaPillExpanded,
        onPickType: { isSessionTypePickerVisible.toggle() }
      ),
      people: SessionPeople(identities: sessionIdentities, showsBadges: hasAudio),
      mascotMessage: mascotMessage,
      timer: SessionTimer(
        timeText: viewModel.sessionTimeText(at: sessionFrozenDate ?? displayDate),
        label: viewModel.sessionTimeLabel
      ),
      // Three 24pt buttons stand taller than the button they replace.
      extraHeight: isMediaPillExpanded && !mediaActions.isEmpty ? 54 : 0
    )
  }

  var mediaValueText: String {
    if hasVideo { return viewModel.videoSessionTypeLabel }
    if hasAudio { return viewModel.audioSessionTypeLabel }
    return viewModel.textSessionTypeLabel
  }

  /// The pill that grows from the media button: this side's microphone and
  /// camera, and a close. A text lesson has neither, only the picker.
  var mediaActions: [SessionMediaAction] {
    guard hasAudio else { return [] }
    let cameraAction: SessionMediaAction
    if hasVideo {
      cameraAction = SessionMediaAction(
        id: "camera",
        iconName: viewModel.isCameraOff ? "session-video-off" : "session-video",
        isOn: !viewModel.isCameraOff,
        accessibilityIdentifier: "session_camera_toggle",
        action: { viewModel.toggleCamera() }
      )
    } else {
      // Not on yet: asking is the same as choosing Video in the picker.
      cameraAction = SessionMediaAction(
        id: "camera",
        iconName: "session-video-off",
        isOn: false,
        accessibilityIdentifier: "session_media_video",
        action: { requestConversationType(ConversationType.video.rawValue) }
      )
    }
    return [
      SessionMediaAction(
        id: "mic",
        iconName: viewModel.isMicMuted ? "session-mic-off" : "session-mic",
        isOn: !viewModel.isMicMuted,
        accessibilityIdentifier: "session_mic_toggle",
        action: { viewModel.toggleMicrophone() }
      ),
      cameraAction,
      SessionMediaAction(
        id: "close",
        iconName: "session-close",
        isOn: true,
        accessibilityIdentifier: "session_media_close",
        action: { isMediaPillExpanded = false }
      ),
    ]
  }

  /// The student, then the teacher, whoever is looking. Each shows what their
  /// microphone and camera are doing — this side's from the device, the other
  /// side's from what they have told the session.
  var sessionIdentities: [SessionIdentity] {
    let peerIsLive = viewModel.peerSecondsToReconnect(at: displayDate) == nil
    // A video lesson that started without its camera has none to show.
    let ownState = MediaDeviceState(
      micMuted: viewModel.isMicMuted,
      cameraOff: viewModel.isCameraOff || didFallBackToAudioOnly
    )
    let own = SessionIdentity(
      id: "own",
      imageURL: viewModel.currentUserImageURL,
      name: viewModel.youLabel,
      subtitle: isStudent ? viewModel.studentRoleLabel : viewModel.teacherRoleLabel,
      isLive: true,
      badges: statusBadges(for: ownState, prefix: "own")
    )
    let peer = SessionIdentity(
      id: "peer",
      imageURL: viewModel.participantImageURL,
      name: participantName,
      subtitle: isStudent ? viewModel.teacherRoleLabel : viewModel.studentRoleLabel,
      isLive: peerIsLive,
      badges: statusBadges(for: peerMediaState ?? MediaDeviceState(), prefix: "peer")
    )
    return isStudent ? [own, peer] : [peer, own]
  }

  /// A video lesson shows the camera, and a muted microphone beside it; an
  /// audio lesson shows the microphone.
  func statusBadges(for state: MediaDeviceState, prefix: String) -> [SessionStatusBadge] {
    if hasVideo {
      var badges = [
        SessionStatusBadge(id: "\(prefix)-camera", kind: state.cameraOff ? .videoOff : .video)
      ]
      if state.micMuted {
        badges.append(SessionStatusBadge(id: "\(prefix)-mic", kind: .micOff))
      }
      return badges
    }
    if hasAudio {
      return [SessionStatusBadge(id: "\(prefix)-mic", kind: state.micMuted ? .micOff : .mic)]
    }
    return []
  }

  /// What the mascot says, if anything: that this side is being waited on, or
  /// that there is something on the board to look at.
  var mascotMessage: String? {
    if peerAwaitedPermission != nil || isPeerFinishingSetup {
      return viewModel.waitingForPeerText
    }
    if selectedTab == .CHAT && viewModel.hasUnreadBoard {
      return viewModel.lookAtBoardNotice
    }
    return nil
  }

  // MARK: Panes

  /// The question the lesson is about, at the top of the chat.
  var originalQuestionCard: some View {
    HStack(alignment: .top, spacing: 10) {
      PlatformIcon(systemName: "pin.fill", size: 12, weight: .bold, color: theme.warning)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.originalQuestionLabel)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(theme.warning)
        FormulaAwareText(
          text: viewModel.originalQuestion,
          textColor: theme.onDarkFill,
          font: .system(size: 13, weight: .medium),
          lineSpacing: 3,
          formulaMinWidth: 160,
          formulaMaxWidth: 260
        )
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(theme.brandModalBackground)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
  }

  /// The board, with the camera panel floating over it in a video lesson.
  var boardLayout: some View {
    sessionFrame {
      whiteboard
        .overlay(alignment: .top) {
          if hasVideo {
            sessionVideoPanel
              .padding(.top, 56)
          }
        }
    }
  }

  var imagesLayout: some View {
    sessionFrame {
      questionImagesGallery
    }
  }

  // MARK: Video

  /// Both cameras side by side in a card the board can be worked under, which
  /// is dragged by its grip.
  var sessionVideoPanel: some View {
    VStack(spacing: 6) {
      Image("session-grip", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.brandActionBackground)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)

      HStack(spacing: 16) {
        remoteVideoTile
        ownVideoTile
      }
    }
    .padding(21)
    .background(theme.brandModalBackground)
    .clipShape(RoundedRectangle(cornerRadius: 17))
    .overlay {
      RoundedRectangle(cornerRadius: 17)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
    .offset(teacherPreviewOffset)
    .gesture(
      DragGesture()
        .onChanged { value in
          teacherPreviewOffset = CGSize(
            width: teacherPreviewAccumOffset.width + value.translation.width,
            height: teacherPreviewAccumOffset.height + value.translation.height
          )
        }
        .onEnded { _ in
          teacherPreviewAccumOffset = teacherPreviewOffset
        }
    )
#if !os(Android)
    .id(liveKitRevision)
#endif
    .accessibilityIdentifier("session_video_panel")
  }

  var videoTileSize: CGSize { CGSize(width: 141, height: 90) }

  @ViewBuilder
  var remoteVideoTile: some View {
#if !os(Android)
    let remoteTrack = viewModel.remoteCameraVideoTrack
    videoTile {
      if let remoteTrack {
        SwiftUIVideoView(remoteTrack, layoutMode: .fill)
          .id(ObjectIdentifier(remoteTrack))
      } else {
        videoPlaceholder(icon: "video.fill", text: viewModel.waitingForVideoText)
      }
    }
#else
    videoTile {
      AndroidVideoFeed(
        isStudent: false,
        isCameraOff: viewModel.isCameraOff,
        theme: theme,
        waitingForVideoText: viewModel.waitingForVideoText
      )
    }
#endif
  }

  @ViewBuilder
  var ownVideoTile: some View {
#if !os(Android)
    let localTrack = viewModel.localCameraVideoTrack
    videoTile {
      if let localTrack, !viewModel.isCameraOff {
        SwiftUIVideoView(localTrack, layoutMode: .fill, mirrorMode: .mirror)
          .id(ObjectIdentifier(localTrack))
      } else {
        PlatformIcon(
          systemName: viewModel.isCameraOff ? "video.slash.fill" : "video.fill",
          size: 22,
          weight: .semibold,
          color: theme.onDarkFill
        )
      }
    }
#else
    videoTile {
      AndroidSelfVideoPreview(isCameraOff: viewModel.isCameraOff, theme: theme, size: videoTileSize)
    }
#endif
  }

  func videoTile<Tile: View>(@ViewBuilder content: () -> Tile) -> some View {
    ZStack {
      theme.videoBackground
      content()
    }
    .frame(width: videoTileSize.width, height: videoTileSize.height)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(theme.brandCardBorder, lineWidth: 1.5)
    }
  }
}
