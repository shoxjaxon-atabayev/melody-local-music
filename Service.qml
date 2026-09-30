import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import "core"
import "core/BarDisplay.js" as BarDisplay
import "core/Metadata.js" as Metadata
import "core/Paths.js" as Paths

// Melody's shared state. The shell creates one instance for all monitors; bar
// widgets reach it through `bar.shell.serviceFor(id)`.
//
// Music from the library plays in Melody's own player (core/Engine.qml): no
// player needs to be started by hand, and no player window opens. The bar
// and the mini-player show that player, or another local MPRIS player while
// it is the one playing. They get sanitized properties and send commands to
// whichever of the two they show, only when it supports them. The service
// also owns the Music Library window, the user's playlists, the bar display
// mode, and the audio levels behind the bar's visualizations.
//
// What is shown (predictable, sticky):
//   - Melody's player while it plays;
//   - otherwise another player that is playing (see below);
//   - otherwise Melody's player if it has a track (paused, or restored after
//     a restart), unless another player was the last one playing.
// Other players: skip playerctld (a proxy that mirrors other players), web
// browsers, and Melody's own mpv (seen over MPRIS through mpv-mpris). A
// playing player wins; the current choice is kept while it still plays;
// otherwise the most recently playing one, then local music players (mpv,
// MPD, …) before others. With nothing playing, keep the current choice while
// it exists, else the most recently playing, else one with track metadata.
// When the chosen player disappears, fall back by the same rules, or go
// idle — never keep showing its old metadata.
Item {
  id: root

  // Injected by the shell (capability-scoped to this plugin).
  property var shell: null
  property var manifest: null
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "community.shoxjaxon.melody"

  // Open popovers across monitors; position polling runs only while > 0.
  property int openPopovers: 0

  // ---------------------------------------------------------------- files, playlists, player
  property PrivateFiles files: PrivateFiles {}
  property PlaylistStore store: PlaylistStore { files: root.files }

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string queueDir: runtimeDir !== "" ? runtimeDir + "/melody" : ""

  property Engine engine: Engine {
    files: root.files
    runtimeFolder: root.queueDir
    dataFolder: root.store.dir
  }

  readonly property string engineKey: "melody"

  // ---------------------------------------------------------------- other players
  readonly property var players: Mpris.players ? Mpris.players.values : []
  property MprisPlayer player: null
  property string lastPlayingKey: ""

  // Melody's own mpv on D-Bus (mpv-mpris), found by its process id.
  property string engineBusName: ""
  property int busLookups: 0

  // ---------------------------------------------------------------- what is shown
  // Melody's own queue counts once it can be checked against the music
  // folder: always when it came from the library this session, and a
  // restored session only while a folder is set. Without one it can be
  // neither checked nor played, so first-run setup comes first.
  readonly property bool engineShown: engine.hasTrack && (engine.trusted || libraryRoot !== "")
  readonly property bool usingEngine: engineShown && (engine.isPlaying
    || !(player && player.isPlaying) && !(player && lastPlayingKey !== "" && lastPlayingKey === playerKey(player)))

  readonly property bool isPlaying: usingEngine ? engine.isPlaying : player !== null && player.isPlaying
  readonly property string title: usingEngine ? Metadata.plainText(engine.tags.title, 300)
    : player ? Metadata.plainText(player.trackTitle, 300) : ""
  readonly property string artist: usingEngine ? Metadata.plainText(engine.tags.artist, 300)
    : player ? Metadata.plainText(player.trackArtist, 300) : ""
  // The title as shown: without a leading copy of the artist
  // ("Tame Impala - Let It Happen" -> "Let It Happen"). `title` stays as
  // the player reports it.
  readonly property string displayTitle: BarDisplay.cleanTitle(artist, title)
  readonly property string album: usingEngine ? Metadata.plainText(engine.tags.album, 300)
    : player ? Metadata.plainText(player.trackAlbum, 300) : ""
  readonly property string artUrl: usingEngine ? engineArtUrl
    : player ? Metadata.artUrl(player.trackArtUrl) : ""
  readonly property bool hasTrack: usingEngine || player !== null
    && (title !== "" || artist !== "" || player.playbackState !== MprisPlaybackState.Stopped)
  readonly property string playerName: usingEngine ? "Melody"
    : player ? (Metadata.plainText(player.identity, 64) || Metadata.plainText(player.desktopEntry, 64) || "Music player")
    : ""
  // The local file being played (from xesam:url for other players), or "".
  readonly property string playingPath: usingEngine ? engine.path
    : player && player.metadata ? Paths.pathFromUrl(player.metadata["xesam:url"]) : ""

  readonly property real length: usingEngine ? engine.length
    : hasTrack && player.lengthSupported && isFinite(player.length) && player.length > 0 ? player.length : 0
  readonly property real position: {
    if (usingEngine) return engine.position
    if (!hasTrack || !player.positionSupported) return 0
    var p = Number(player.position)
    if (!isFinite(p) || p < 0) return 0
    return length > 0 ? Math.min(p, length) : p
  }

  readonly property bool shuffle: usingEngine ? engine.shuffle : player !== null && player.shuffleSupported && player.shuffle
  readonly property bool repeatOne: usingEngine ? engine.repeatOne
    : player !== null && player.loopSupported && player.loopState === MprisLoopState.Track

  // Cover art of Melody's track, as mpv-mpris reports it (when installed):
  // the image embedded in the file, or a cover image next to it
  // (cover.jpg, front.png, Folder.jpg, …).
  readonly property var engineTwin: {
    if (engineBusName === "") return null
    for (var i = 0; i < players.length; i++)
      if (players[i] && String(players[i].dbusName) === engineBusName) return players[i]
    return null
  }
  readonly property string engineArtUrl: engineTwin && urlPathOf(engineTwin) === engine.path && engine.path !== ""
    ? Metadata.artUrl(engineTwin.trackArtUrl) : ""

  // ---------------------------------------------------------------- capabilities
  readonly property bool canControl: usingEngine || player !== null && player.canControl
  readonly property bool canTogglePlaying: usingEngine ? engine.hasTrack
    : canControl && hasTrack && (player.isPlaying ? player.canPause : player.canPlay)
  readonly property bool canGoNext: usingEngine ? engine.canGoNext : canControl && player.canGoNext
  readonly property bool canGoPrevious: usingEngine ? engine.canGoPrevious : canControl && player.canGoPrevious
  readonly property bool canSeek: usingEngine ? engine.canSeek
    : canControl && hasTrack && player.canSeek && player.positionSupported && length > 0
  readonly property bool canShuffle: usingEngine || canControl && player.shuffleSupported
  readonly property bool canRepeat: usingEngine || canControl && player.loopSupported

  // ---------------------------------------------------------------- commands
  // Sent only to what is shown, only when it supports them. The UI follows
  // the reported state, never assumes success.
  function togglePlaying() {
    if (usingEngine) {
      // A restored queue is checked against the library first.
      if (!engine.trusted && !engine.live) checkSession(true)
      else engine.togglePlaying()
    } else if (canTogglePlaying) {
      player.togglePlaying()
    }
  }
  function next() {
    if (usingEngine) engine.next()
    else if (canGoNext) player.next()
  }
  function previous() {
    if (usingEngine) engine.previous()
    else if (canGoPrevious) player.previous()
  }
  function seek(seconds) {
    if (usingEngine) { engine.seek(seconds); return }
    if (!canSeek) return
    var s = Number(seconds)
    if (!isFinite(s)) return
    player.position = Math.max(0, Math.min(length, s))
  }
  function setShuffle(on) {
    if (usingEngine) engine.setShuffle(on)
    else if (canShuffle) player.shuffle = !!on
  }
  function setRepeatOne(on) {
    if (usingEngine) engine.setRepeatOne(on)
    else if (canRepeat) player.loopState = on ? MprisLoopState.Track : MprisLoopState.None
  }

  // ---------------------------------------------------------------- other players: policy
  function playerKey(p) {
    if (!p) return ""
    return String(p.dbusName || p.desktopEntry || p.identity || "")
  }

  function describe(p) {
    return [p.dbusName, p.desktopEntry, p.identity].join(" ").toLowerCase()
  }

  function isProxy(p) {
    return /\bplayerctld\b/.test(describe(p))
  }

  function isBrowser(p) {
    return /\b(firefox|zen|librewolf|floorp|waterfox|mullvadbrowser|torbrowser|chromium|chrome|brave|vivaldi|opera|edge|epiphany|falkon|qutebrowser|midori|thorium|helium|yandex|plasma-browser-integration)\b/
      .test(describe(p))
  }

  function isLocalMusicPlayer(p) {
    return /\b(mpv|mpd|mopidy|strawberry|rhythmbox|lollypop|amberol|elisa|audacious|clementine|quodlibet|cmus|deadbeef|g4music|gapless|tauon|musikcube|kew|termusic)\b/
      .test(describe(p))
  }

  function isMpv(p) {
    return /\bmpv\b/.test(describe(p))
  }

  function urlPathOf(p) {
    return p && p.metadata ? Paths.pathFromUrl(p.metadata["xesam:url"]) : ""
  }

  // Melody's own mpv, by its bus name once known; until then (a moment after
  // it starts), an mpv with no file yet or on the same file as Melody.
  function isEngineTwin(p) {
    if (!p || engine.pid === "") return false
    if (engineBusName !== "") return String(p.dbusName) === engineBusName
    var url = urlPathOf(p)
    return isMpv(p) && (url === "" || url === engine.path)
  }

  function isEligible(p) {
    return !!p && !isProxy(p) && !isBrowser(p) && !isEngineTwin(p)
  }

  function hasMetadata(p) {
    return !!(p.trackTitle || p.trackArtist || p.trackAlbum)
  }

  function findByKey(list, key) {
    if (!key) return null
    for (var i = 0; i < list.length; i++)
      if (playerKey(list[i]) === key) return list[i]
    return null
  }

  function localFirst(list) {
    var local = list.filter(isLocalMusicPlayer)
    return local.length ? local[0] : list[0]
  }

  function choosePlayer() {
    var list = players.filter(isEligible)
    if (list.length === 0) return null
    var current = player && list.indexOf(player) !== -1 ? player : null

    var playing = list.filter(function(p) { return p.isPlaying })
    if (playing.length) {
      if (current && current.isPlaying) return current
      return findByKey(playing, lastPlayingKey) || localFirst(playing)
    }

    if (current) return current
    var recent = findByKey(list, lastPlayingKey)
    if (recent) return recent
    var withMetadata = list.filter(hasMetadata)
    return localFirst(withMetadata.length ? withMetadata : list)
  }

  function refresh() {
    var next = choosePlayer()
    if (next !== player) player = next
  }

  function scheduleRefresh() {
    Qt.callLater(root.refresh)
  }

  onPlayersChanged: {
    scheduleRefresh()
    if (engine.pid !== "" && engineBusName === "") busTimer.restart()
  }
  onEngineBusNameChanged: scheduleRefresh()
  Component.onCompleted: refresh()

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData

      function onIsPlayingChanged() {
        if (modelData.isPlaying && root.isEligible(modelData))
          root.lastPlayingKey = root.playerKey(modelData)
        root.scheduleRefresh()
      }
      function onPlaybackStateChanged() { root.scheduleRefresh() }
      function onPostTrackChanged() { root.scheduleRefresh() }
      function onIdentityChanged() { root.scheduleRefresh() }
    }
  }

  Connections {
    target: root.engine
    function onIsPlayingChanged() {
      if (!root.engine.isPlaying) return
      root.lastPlayingKey = root.engineKey
      root.queueError = ""
    }
    function onPathChanged() { root.scheduleRefresh() }
    function onPidChanged() {
      root.engineBusName = ""
      root.busLookups = 0
      if (root.engine.pid !== "") busTimer.restart()
    }
  }

  // Which bus name belongs to Melody's mpv: `busctl --user list` shows each
  // name's process id. Fixed arguments, no shell; at most a few times per
  // mpv start (mpv-mpris registers a moment after mpv starts).
  Timer {
    id: busTimer
    interval: 300
    onTriggered: {
      if (root.engine.pid === "" || root.engineBusName !== "" || busLookup.running || root.busLookups >= 5) return
      root.busLookups++
      busLookup.pid = root.engine.pid
      busLookup.running = true
    }
  }

  Process {
    id: busLookup
    property string pid: ""
    command: ["/usr/bin/busctl", "--user", "--no-pager", "--json=short", "list"]
    stdout: StdioCollector { id: busNames }
    onExited: (code, status) => {
      if (pid !== root.engine.pid) return
      var list
      try { list = JSON.parse(busNames.text) } catch (e) { list = null }
      if (Array.isArray(list)) {
        for (var i = 0; i < list.length; i++) {
          var e = list[i]
          if (e && String(e.pid) === pid && /^org\.mpris\.MediaPlayer2\./.test(String(e.name))) {
            root.engineBusName = String(e.name)
            return
          }
        }
      }
      if (root.busLookups < 5) busTimer.restart()
    }
  }

  // MPRIS does not stream position changes; Quickshell recomputes
  // `position` when `positionChanged` is emitted. Refresh once when a card
  // opens, then tick once per second only while a card is visible and the
  // player is playing, so nothing runs while the card is closed or paused.
  // (Melody's own player keeps its position itself.)
  onOpenPopoversChanged: {
    if (openPopovers > 0 && player && !usingEngine) player.positionChanged()
    // A card opening with nothing playing checks again, so packages
    // installed or removed elsewhere count.
    if (openPopovers > 0 && !hasTrack && !requirements.installing) requirements.check()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.openPopovers > 0 && !root.usingEngine && root.isPlaying && root.player !== null
      && root.player.positionSupported
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // ---------------------------------------------------------------- settings
  // Stored on Melody's own entry in shell.json, through the shell's scoped
  // settings API (never by editing the file directly).
  readonly property var ownEntry: {
    var config = shell && shell.barConfig ? shell.barConfig : null
    var layout = config && config.layout ? config.layout : null
    if (!layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var list = layout[sections[s]] || []
      for (var i = 0; i < list.length; i++)
        if (list[i] && String(list[i].id) === pluginId) return list[i]
    }
    return null
  }

  // The shell replaces the whole entry, so every other saved key is copied.
  // False when there is no entry to save on (the widget isn't in the bar).
  function saveSettings(changes) {
    if (!shell || typeof shell.updateEntryInline !== "function" || !ownEntry) return false
    var settings = {}
    for (var k in ownEntry) if (k !== "id") settings[k] = ownEntry[k]
    for (var c in changes) settings[c] = changes[c]
    shell.updateEntryInline(pluginId, settings)
    return true
  }

  // ---------------------------------------------------------------- library folder
  readonly property string savedLibraryRoot: ownEntry && typeof ownEntry.libraryFolder === "string"
    ? Paths.normalizedAbsolute(ownEntry.libraryFolder) : ""
  property string libraryRoot: ""
  onSavedLibraryRootChanged: if (savedLibraryRoot !== "") libraryRoot = savedLibraryRoot
  Component.onDestruction: files.tasks = []

  function setLibraryRoot(path) {
    var p = Paths.normalizedAbsolute(path)
    if (p === "") return false
    libraryRoot = p
    saveSettings({ libraryFolder: p })
    return true
  }

  // What the Library window last found in the library folder: "unset",
  // "unknown" (not scanned yet), "ok", "empty" (no audio files anywhere in
  // it), or the scan's error ("missing", "notFolder", "permission",
  // "timedOut", "failed").
  property string libraryStatus: "unset"
  onLibraryRootChanged: libraryStatus = libraryRoot === "" ? "unset" : "unknown"
  // No folder yet, or the chosen one has nothing to play or can't be read.
  readonly property bool needsLibrarySetup: libraryRoot === ""
    || ["empty", "missing", "notFolder", "permission"].indexOf(libraryStatus) !== -1

  // ---------------------------------------------------------------- setup
  // What Melody runs, and its one-click install (core/Requirements.qml).
  property Requirements requirements: Requirements {
    mpvBinary: root.engine.mpvBinary
    mprisScript: root.engine.mprisScript
    cavaBinary: root.audio.cavaBinary
    // A cava found missing earlier is looked for again.
    onInstalled: if (root.displayMode === BarDisplay.SPECTRUM) root.audio.checkCava()
  }

  // The mini-player shows the setup steps in place of the player: install
  // what's missing, then choose the music folder. While nothing is shown,
  // or while mpv is missing and Melody's own player is the one shown (it
  // can't play without it); another player that plays keeps the card.
  readonly property bool mpvMissing: requirements.missing.indexOf("mpv") !== -1
  readonly property bool needsSetup: !hasTrack && needsLibrarySetup
    || mpvMissing && (!hasTrack || usingEngine)

  // Playback found mpv missing: the setup card offers to install it.
  Connections {
    target: root.engine
    function onMpvMissingChanged() {
      if (root.engine.mpvMissing && !root.requirements.installing) root.requirements.check()
    }
  }

  // ---------------------------------------------------------------- bar display
  // "trackInfo" (the default), "spectrum", or "pulseDots". A missing or
  // unknown saved value means Track Info. A choice applies at once; it is
  // also kept for this session when there is no entry to save it on.
  readonly property string savedDisplayMode: BarDisplay.normalizeMode(ownEntry ? ownEntry.displayMode : undefined)
  property string chosenDisplayMode: ""
  readonly property string displayMode: chosenDisplayMode !== "" ? chosenDisplayMode : savedDisplayMode
  onSavedDisplayModeChanged: chosenDisplayMode = ""

  function setDisplayMode(mode) {
    if (BarDisplay.normalizeMode(mode) !== mode) return false
    chosenDisplayMode = mode
    if (mode !== savedDisplayMode) saveSettings({ displayMode: mode })
    // Choosing Spectrum again finds a cava installed since the last check.
    if (mode === BarDisplay.SPECTRUM && (audio.cavaState !== "available" || audio.cavaFailed)) audio.checkCava()
    return true
  }

  // What Track Info shows: "artistTitle" (the default), "title", or
  // "artist". Saved and applied like the display mode.
  readonly property string savedTrackLabel: BarDisplay.normalizeLabel(ownEntry ? ownEntry.trackLabel : undefined)
  property string chosenTrackLabel: ""
  readonly property string trackLabel: chosenTrackLabel !== "" ? chosenTrackLabel : savedTrackLabel
  onSavedTrackLabelChanged: chosenTrackLabel = ""

  function setTrackLabel(label) {
    if (BarDisplay.normalizeLabel(label) !== label) return false
    chosenTrackLabel = label
    if (label !== savedTrackLabel) saveSettings({ trackLabel: label })
    return true
  }

  // Bar widgets currently drawing a visualization; audio is sampled only
  // while > 0 and the player is playing.
  property int audioViewers: 0

  property AudioLevels audio: AudioLevels {
    files: root.files
    player: root.usingEngine ? null : root.player
    processId: root.usingEngine ? root.engine.pid : ""
    clientName: root.engine.clientName
    trackTitle: root.title
    playing: root.hasTrack && root.isPlaying
    viewed: root.audioViewers > 0
    mode: root.displayMode
    folder: root.queueDir
  }

  // ---------------------------------------------------------------- library window
  property bool libraryOpen: false
  property bool libraryLoaded: false
  property string libraryScreen: ""

  // Opened by the shell (panel summon / keyboard shortcut) or directly.
  function showLibrary() {
    libraryScreen = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    libraryLoaded = true
    if (!libraryOpen) {
      libraryOpen = true
      store.load()
    }
  }

  function closeLibrary() {
    if (!libraryOpen) return
    libraryOpen = false
  }

  // Set by the setup card's Choose Music Folder: the library opens on its
  // folder chooser instead of the list.
  property bool chooserRequested: false

  function chooseLibraryFolder() {
    chooserRequested = true
    openLibrary()
  }

  // From the mini-player: through the shell when possible, so its panel
  // state (and a keyboard toggle) stays in sync; directly otherwise.
  function openLibrary() {
    if (shell && typeof shell.summon === "function" && shell.summon(pluginId, "{}")) {
      summonFallback.restart()
      return
    }
    showLibrary()
  }

  Timer {
    id: summonFallback
    interval: 500
    onTriggered: if (!root.libraryOpen) root.showLibrary()
  }

  LazyLoader {
    active: root.libraryLoaded

    LibraryWindow {
      service: root
      open: root.libraryOpen
      onCloseRequested: root.closeLibrary()
    }
  }

  // ---------------------------------------------------------------- playing from the library (PLAN §2.6)
  // Melody's queue as the library shows it: { paths, source: { kind, id, name } }.
  readonly property var queue: engine.hasTrack ? { paths: engine.paths, source: engine.source || { kind: "library", id: "", name: "Library" } } : null
  readonly property int queueIndex: usingEngine && engine.hasTrack ? engine.index : -1
  property string queueError: ""
  property bool queueStarting: false
  // What went wrong with library playback, for the library's notice.
  readonly property string playbackError: queueError !== "" ? queueError : engine.error

  property PathValidator queueValidator: PathValidator {}

  // Plays `paths` (in queue order) from `paths[start]`. Every path is checked
  // again first; missing or invalid ones are skipped, each file is queued
  // once, at most 1,000 (from the chosen track on, when there are more).
  function playFromLibrary(paths, start, source) {
    if (queueStarting || paths.length === 0) return
    var chosen = paths[Math.max(0, Math.min(paths.length - 1, start))]
    queueError = ""
    queueStarting = true
    queueValidator.validate(libraryRoot, paths, function(statuses) {
      root.queueStarting = false
      var ok = [], seen = {}, at = -1
      for (var i = 0; i < paths.length; i++) {
        if (statuses[i] !== "ok" || seen[paths[i]]) continue
        seen[paths[i]] = true
        if (paths[i] === chosen) at = ok.length
        ok.push(paths[i])
      }
      if (at < 0) {
        root.queueError = ok.length ? "“" + Paths.displayName(Paths.trackTitle(Paths.baseName(chosen))) + "” can't be played."
                                    : "None of these tracks can be played."
        return
      }
      if (ok.length > root.engine.maxQueue) {
        ok = ok.slice(at, at + root.engine.maxQueue)
        at = 0
      }
      root.lastPlayingKey = root.engineKey
      root.engine.play(ok, at, source)
    })
  }

  // ---------------------------------------------------------------- the restored session
  // After a restart the saved queue is checked against the library rules
  // (as every queue is), then loaded into Melody's player, paused where it
  // was — so media keys work at once and play resumes right there. Tracks
  // that are gone are dropped; if the current one is gone, the queue is.
  property bool sessionPending: true
  readonly property bool sessionReady: engine.restored && libraryRoot !== ""
  onSessionReadyChanged: if (sessionReady && sessionPending) checkSession(false)

  function checkSession(play) {
    sessionPending = false
    if (!engine.hasTrack || engine.trusted || engine.loading) {
      if (play) engine.togglePlaying()
      return
    }
    var list = engine.paths.slice()
    var current = engine.path
    queueValidator.validate(libraryRoot, list, function(statuses) {
      // Something else started meanwhile: leave it.
      if (root.engine.trusted || root.engine.path !== current) return
      var ok = [], seen = {}
      for (var i = 0; i < list.length; i++) {
        if (statuses[i] !== "ok" || seen[list[i]]) continue
        seen[list[i]] = true
        ok.push(list[i])
      }
      var at = ok.indexOf(current)
      if (at < 0) {
        if (play) root.queueError = "“" + Paths.displayName(Paths.trackTitle(Paths.baseName(current))) + "” is no longer in your library."
        root.engine.forget()
        return
      }
      root.engine.adopt(ok, at)
      if (play) root.engine.togglePlaying()
      else root.engine.warmUp()
    })
  }
}
