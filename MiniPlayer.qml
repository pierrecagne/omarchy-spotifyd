import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// Spotify mini-player for the bar. Playback runs in spotifyd (or the desktop
// client) and is steered from any Spotify app over Spotify Connect; this only
// reads and drives the player's MPRIS interface: track title in the bar, and a
// popup with artwork, seek, transport, shuffle, repeat and volume. No Web API,
// so no login and no rate limits.
BarWidget {
  id: root
  moduleName: "io.github.pierrecagne.spotifyd"

  readonly property string playerMatch: setting("player", "spotify")
  readonly property int maxTitleWidth: setting("maxTitleWidth", 240)

  // First matching player, preferring one that is playing (e.g. spotifyd and
  // the desktop client both running).
  readonly property var player: {
    var list = Mpris.players ? Mpris.players.values : []
    var first = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p || String(p.dbusName || "").toLowerCase().indexOf(playerMatch.toLowerCase()) === -1) continue
      if (p.isPlaying) return p
      if (!first) first = p
    }
    return first
  }
  readonly property bool hasTrack: player !== null && (player.trackTitle || "") !== ""
  readonly property bool playing: player !== null && player.isPlaying
  readonly property string title: hasTrack ? player.trackTitle : ""
  readonly property string artist: {
    if (!hasTrack) return ""
    // trackArtist(s) come back as a single string; the raw metadata keeps
    // every artist of a collaboration.
    var names = player.metadata ? player.metadata["xesam:artist"] : null
    if (names && typeof names !== "string" && names.length) return Array.from(names).join(", ")
    return player.trackArtist || ""
  }
  readonly property string album: hasTrack ? (player.trackAlbum || "") : ""
  readonly property string artUrl: hasTrack ? (player.trackArtUrl || "") : ""

  readonly property var glyph: ({
    spotify: String.fromCodePoint(0xF04C7),
    play: String.fromCodePoint(0xF040A),
    pause: String.fromCodePoint(0xF03E4),
    previous: String.fromCodePoint(0xF04AE),
    next: String.fromCodePoint(0xF04AD),
    shuffle: String.fromCodePoint(0xF049D),
    repeat: String.fromCodePoint(0xF0456),
    repeatOnce: String.fromCodePoint(0xF0458),
    volumeHigh: String.fromCodePoint(0xF057E),
    volumeMedium: String.fromCodePoint(0xF0580),
    volumeLow: String.fromCodePoint(0xF057F),
    volumeMute: String.fromCodePoint(0xF075F)
  })

  property bool popupOpen: false
  // Volume to restore when unmuting from the speaker icon.
  property real volumeBeforeMute: 0.5

  function close() { popupOpen = false }
  function togglePopup() { popupOpen = !popupOpen }

  // Every monitor has its own copy of the widget; IPC toggles the one on the
  // focused monitor.
  function togglePopupOnFocusedScreen() {
    var screen = root.QsWindow.window ? root.QsWindow.window.screen : null
    var focused = Hyprland.focusedMonitor
    if (screen && focused && screen.name !== focused.name) return
    togglePopup()
  }

  function playPause() { if (player && player.canTogglePlaying) player.togglePlaying() }
  function next() { if (player && player.canGoNext) player.next() }
  function previous() { if (player && player.canGoPrevious) player.previous() }

  function toggleShuffle() {
    if (player && player.shuffleSupported) player.shuffle = !player.shuffle
  }

  // Same cycle as the Spotify apps: off, whole context, current track.
  function cycleRepeat() {
    if (!player || !player.loopSupported) return
    if (player.loopState === MprisLoopState.None) player.loopState = MprisLoopState.Playlist
    else if (player.loopState === MprisLoopState.Playlist) player.loopState = MprisLoopState.Track
    else player.loopState = MprisLoopState.None
  }

  function changeVolume(delta) {
    if (player && player.volumeSupported)
      player.volume = Math.max(0, Math.min(1, Math.round((player.volume + delta) * 100) / 100))
  }

  function toggleMute() {
    if (!player || !player.volumeSupported) return
    if (player.volume > 0.001) {
      volumeBeforeMute = player.volume
      player.volume = 0
    } else {
      player.volume = volumeBeforeMute > 0.001 ? volumeBeforeMute : 0.5
    }
  }

  function formatTime(seconds) {
    var s = Math.max(0, Math.floor(Number(seconds) || 0))
    var m = Math.floor(s / 60)
    s = s % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  readonly property string tooltip: {
    if (!player) return "No Spotify player running"
    if (!hasTrack) return "Nothing playing"
    return title + (artist ? " — " + artist : "")
  }

  readonly property color barColor: {
    var fg = bar ? bar.barForeground : Color.foreground
    return playing ? fg : Qt.darker(fg, 1.5)
  }
  readonly property bool titleShown: hasTrack && maxTitleWidth > 0 && !vertical
  readonly property real sidePadding: Style.space(7)

  // Computed by hand rather than from a Row: the title is hidden while
  // nothing plays, and a Row ignores hidden children.
  implicitWidth: vertical ? barSize
    : sidePadding * 2 + icon.implicitWidth + (titleShown ? Style.space(6) + titleText.width : 0)
  implicitHeight: barSize

  // Playback calls act once on the shared player, so they are handled here
  // rather than broadcast to every monitor's widget.
  IpcHandler {
    target: "io.github.pierrecagne.spotifyd"
    function toggle(): void { root.broadcast("togglePopupOnFocusedScreen") }
    function playPause(): void { root.playPause() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function volumeUp(): void { root.changeVolume(0.05) }
    function volumeDown(): void { root.changeVolume(-0.05) }
    function toggleMute(): void { root.toggleMute() }
    function toggleShuffle(): void { root.toggleShuffle() }
    function cycleRepeat(): void { root.cycleRepeat() }
    function status(): string {
      return JSON.stringify({
        player: root.player ? root.player.dbusName : "",
        playing: root.playing,
        title: root.title,
        artist: root.artist,
        position: root.player ? root.player.position : 0,
        length: root.player ? root.player.length : 0,
        volume: root.player ? root.player.volume : 0,
        shuffle: root.player ? root.player.shuffle : false,
        loopState: root.player ? root.player.loopState : 0
      })
    }
  }

  Text {
    id: icon
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    x: root.vertical ? (parent.width - implicitWidth) / 2 : root.sidePadding
    text: root.glyph.spotify
    color: root.barColor
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    Behavior on color {
      enabled: !root.bar || root.bar.foregroundAnimationEnabled
      ColorAnimation { duration: 160 }
    }
  }

  Text {
    id: titleText
    textFormat: Text.PlainText
    visible: root.titleShown
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: icon.right
    anchors.leftMargin: Style.space(6)
    width: Math.min(implicitWidth, root.maxTitleWidth)
    elide: Text.ElideRight
    text: root.title
    color: root.barColor
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) root.playPause()
      else root.togglePopup()
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // MPRIS position does not tick on its own; nudge it while it is on screen.
  Timer {
    running: root.popupOpen && root.playing
    interval: 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(12)

      Row {
        spacing: Style.space(12)
        width: parent.width

        BorderSurface {
          id: artwork
          width: Style.space(88)
          height: Style.space(88)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            id: cover
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.artUrl
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: !cover.visible
            text: root.glyph.spotify
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)
          width: parent.width - artwork.width - parent.spacing

          Text {
            textFormat: Text.PlainText
            text: root.hasTrack ? root.title : "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: root.hasTrack ? root.artist
              : (root.player ? "Pick this computer in any Spotify app" : "No Spotify player running")
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.album
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: root.hasTrack

        PanelSlider {
          id: seek
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: Math.max(1, root.player ? root.player.length : 1)
          value: root.player ? root.player.position : 0
          step: 10
          enabled: root.player !== null && root.player.canSeek
          onReleased: function(value) {
            if (root.player && root.player.canSeek) root.player.position = value
          }
        }

        Item {
          width: parent.width
          height: elapsed.implicitHeight

          Text {
            id: elapsed
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: root.formatTime(seek.liveValue)
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: root.formatTime(root.player ? root.player.length : 0)
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(8)
        visible: root.hasTrack

        Button {
          iconText: root.glyph.shuffle
          tooltipText: root.player && root.player.shuffle ? "Shuffle on" : "Shuffle off"
          foreground: root.player && root.player.shuffle ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.8)
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player !== null && root.player.shuffleSupported
          onClicked: root.toggleShuffle()
        }

        Button {
          iconText: root.glyph.previous
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player !== null && root.player.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.previous()
        }

        Button {
          iconText: root.playing ? root.glyph.pause : root.glyph.play
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.player !== null && root.player.canTogglePlaying
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.playPause()
        }

        Button {
          iconText: root.glyph.next
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player !== null && root.player.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.next()
        }

        Button {
          readonly property int loop: root.player ? root.player.loopState : MprisLoopState.None
          iconText: loop === MprisLoopState.Track ? root.glyph.repeatOnce : root.glyph.repeat
          tooltipText: loop === MprisLoopState.Track ? "Repeat track"
            : loop === MprisLoopState.Playlist ? "Repeat" : "Repeat off"
          foreground: loop === MprisLoopState.None ? Qt.darker(root.bar.foreground, 1.8) : root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player !== null && root.player.loopSupported
          onClicked: root.cycleRepeat()
        }
      }

      Item {
        width: parent.width
        height: volume.implicitHeight
        visible: root.hasTrack && root.player.volumeSupported

        Text {
          id: volumeIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(22)
          textFormat: Text.PlainText
          readonly property real level: root.player ? root.player.volume : 0
          text: level <= 0.001 ? root.glyph.volumeMute
            : level < 0.34 ? root.glyph.volumeLow
            : level < 0.67 ? root.glyph.volumeMedium : root.glyph.volumeHigh
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.icon

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMute()
          }
        }

        PanelSlider {
          id: volume
          anchors.left: volumeIcon.right
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.player ? root.player.volume : 0
          onMoved: function(value) { if (root.player) root.player.volume = value }
          onRightClicked: root.toggleMute()
        }
      }
    }
  }
}
