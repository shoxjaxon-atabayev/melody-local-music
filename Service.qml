import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "core"
import "core/Metadata.js" as Metadata
import "core/Paths.js" as Paths

// Vinyl's shared state. The shell creates one instance for all monitors; bar
// widgets reach it through `bar.shell.serviceFor(id)`.
//
// It picks one MPRIS player, exposes its track as sanitized properties, and
// sends playback commands to that player only, when it supports them. It
// also owns the Music Library window, the user's playlists, and Vinyl's
// session queue.
//
// Player policy (predictable, sticky):
//   - skip playerctld (a proxy that mirrors other players) and web browsers;
//   - a playing player wins; the current choice is kept while it still
//     plays; otherwise the most recently playing one, then local music
//     players (mpv, MPD, …) before others;
//   - with nothing playing, keep the current choice while it exists, else
//     the most recently playing, else one with track metadata;
//   - when the chosen player disappears, fall back by the same rules, or go
//     idle — never keep showing its old metadata;
//   - a player the Music Library starts playback on becomes the choice.
Item {
  id: root

  // Injected by the shell (capability-scoped to this plugin).
  property var shell: null
  property var manifest: null
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "community.shoxjaxon.vinyl"

  // Open popovers across monitors; position polling runs only while > 0.
  property int openPopovers: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  property MprisPlayer player: null
  property string lastPlayingKey: ""

  // ---------------------------------------------------------------- track (sanitized)
  readonly property bool hasPlayer: player !== null
  readonly property bool isPlaying: hasPlayer && player.isPlaying
  readonly property string title: hasPlayer ? Metadata.plainText(player.trackTitle, 300) : ""
  readonly property string artist: hasPlayer ? Metadata.plainText(player.trackArtist, 300) : ""
  readonly property string album: hasPlayer ? Metadata.plainText(player.trackAlbum, 300) : ""
  readonly property string artUrl: hasPlayer ? Metadata.localArtUrl(player.trackArtUrl) : ""
  readonly property bool hasTrack: hasPlayer
    && (title !== "" || artist !== "" || player.playbackState !== MprisPlaybackState.Stopped)
  readonly property string playerName: hasPlayer
    ? (Metadata.plainText(player.identity, 64) || Metadata.plainText(player.desktopEntry, 64) || "Music player")
    : ""
  // The local file the player is on (from xesam:url), or "".
  readonly property string playingPath: hasPlayer && player.metadata
    ? Paths.pathFromUrl(player.metadata["xesam:url"]) : ""

  readonly property real length: hasTrack && player.lengthSupported && isFinite(player.length) && player.length > 0
    ? player.length : 0
  readonly property real position: {
    if (!hasTrack || !player.positionSupported) return 0
    var p = Number(player.position)
    if (!isFinite(p) || p < 0) return 0
    return length > 0 ? Math.min(p, length) : p
  }

  readonly property bool shuffle: hasPlayer && player.shuffleSupported && player.shuffle
  readonly property bool repeatOne: hasPlayer && player.loopSupported
    && player.loopState === MprisLoopState.Track
  // The player's own setting repeats the whole list (e.g. mpv loop-playlist).
  readonly property bool loopsWholeList: hasPlayer && player.loopSupported
    && player.loopState === MprisLoopState.Playlist

  // ---------------------------------------------------------------- capabilities
  readonly property bool canControl: hasPlayer && player.canControl
  readonly property bool canTogglePlaying: canControl && hasTrack
    && (player.isPlaying ? player.canPause : player.canPlay)
  readonly property bool canGoNext: canControl && player.canGoNext
  readonly property bool canGoPrevious: canControl && player.canGoPrevious
  readonly property bool canSeek: canControl && hasTrack && player.canSeek && player.positionSupported && length > 0
  readonly property bool canShuffle: canControl && player.shuffleSupported
  readonly property bool canRepeat: canControl && player.loopSupported

  // ---------------------------------------------------------------- commands
  // Sent only to the selected player, only when it supports them. The UI
  // follows the player's reported state, never assumes success.
  function togglePlaying() { if (canTogglePlaying) player.togglePlaying() }
  function next() { if (canGoNext) player.next() }
  function previous() { if (canGoPrevious) player.previous() }
  function seek(seconds) {
    if (!canSeek) return
    var s = Number(seconds)
    if (!isFinite(s)) return
    player.position = Math.max(0, Math.min(length, s))
  }
  function setShuffle(on) { if (canShuffle) player.shuffle = !!on }
  function setRepeatOne(on) { if (canRepeat) player.loopState = on ? MprisLoopState.Track : MprisLoopState.None }

  // ---------------------------------------------------------------- policy
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

  // Library playback supports mpv (with mpv-mpris) only in this version.
  function isMpv(p) {
    return /\bmpv\b/.test(describe(p))
  }

  function isEligible(p) {
    return !!p && !isProxy(p) && !isBrowser(p)
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

  onPlayersChanged: scheduleRefresh()
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
      function onPostTrackChanged() {
        if (root.pendingStart && modelData === root.pendingStart.player) root.pendingStart.changed = true
        root.scheduleRefresh()
      }
      function onIdentityChanged() { root.scheduleRefresh() }
    }
  }

  // MPRIS does not stream position changes; Quickshell recomputes
  // `position` when `positionChanged` is emitted. Refresh once when a card
  // opens, then tick once per second only while a card is visible and the
  // player is playing, so nothing runs while the card is closed or paused.
  onOpenPopoversChanged: if (openPopovers > 0 && player) player.positionChanged()

  Timer {
    interval: 1000
    repeat: true
    running: root.openPopovers > 0 && root.isPlaying && root.player !== null
      && root.player.positionSupported
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // ---------------------------------------------------------------- library folder
  // Stored on Vinyl's own entry in shell.json, through the shell's scoped
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
  readonly property string savedLibraryRoot: ownEntry && typeof ownEntry.libraryFolder === "string"
    ? Paths.normalizedAbsolute(ownEntry.libraryFolder) : ""
  property string libraryRoot: ""
  onSavedLibraryRootChanged: if (savedLibraryRoot !== "") libraryRoot = savedLibraryRoot
  Component.onDestruction: files.tasks = []

  function setLibraryRoot(path) {
    var p = Paths.normalizedAbsolute(path)
    if (p === "") return false
    libraryRoot = p
    if (shell && typeof shell.updateEntryInline === "function" && ownEntry) {
      var settings = {}
      for (var k in ownEntry) if (k !== "id") settings[k] = ownEntry[k]
      settings.libraryFolder = p
      shell.updateEntryInline(pluginId, settings)
    }
    return true
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

  // ---------------------------------------------------------------- playlists
  property PrivateFiles files: PrivateFiles {}
  property PlaylistStore store: PlaylistStore { files: root.files }

  // ---------------------------------------------------------------- session queue (PLAN §2.6)
  // { paths: [...], source: { kind: "folder"|"search"|"playlist", id, name } }
  property var queue: null
  property string queueError: ""
  property bool queueStarting: false
  property var pendingStart: null
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string queueDir: runtimeDir + "/vinyl"
  readonly property string queueFile: queueDir + "/queue.m3u"
  readonly property string emptyQueue: "#EXTM3U\n"

  // The player library playback goes to: the selected one if it is mpv,
  // else any running mpv; it must accept commands.
  readonly property var libraryPlayer: {
    if (player && isMpv(player) && player.canControl) return player
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (isEligible(p) && isMpv(p) && p.canControl) return p
    }
    return null
  }

  onLibraryPlayerChanged: if (libraryPlayer && queueError === "noPlayer") queueError = ""

  readonly property int queueIndex: queue && playingPath !== "" ? queue.paths.indexOf(playingPath) : -1
  onPlayingPathChanged: {
    // The player moved to something that is not in Vinyl's queue: the queue
    // was replaced elsewhere, so stop treating it as Vinyl's.
    if (queue && !queueStarting && playingPath !== "" && queue.paths.indexOf(playingPath) === -1) queue = null
  }

  property PathValidator queueValidator: PathValidator {}

  function shuffled(list) {
    var a = list.slice()
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1))
      var t = a[i]; a[i] = a[j]; a[j] = t
    }
    return a
  }

  // Plays `paths` (already in queue order: the chosen track first) through
  // the library player. Every path is checked again first; missing or
  // invalid ones are skipped, each file is queued once, at most 1,000.
  function playFromLibrary(paths, source) {
    var p = libraryPlayer
    if (!p) { queueError = "noPlayer"; return }
    if (queueStarting) return
    queueError = ""
    queueStarting = true
    queueValidator.validate(libraryRoot, paths, function(statuses) {
      var ok = [], seen = {}
      for (var i = 0; i < paths.length; i++) {
        if (statuses[i] !== "ok" || seen[paths[i]]) continue
        seen[paths[i]] = true
        ok.push(paths[i])
      }
      if (ok.length === 0) { root.failStart("None of these tracks can be played."); return }
      if (ok.length > 1000) ok = ok.slice(0, 1000)
      var restoreShuffle = p.shuffleSupported && p.shuffle
      if (restoreShuffle) ok = [ok[0]].concat(root.shuffled(ok.slice(1)))
      root.files.ensureDir(root.queueDir, function(dirOk, why) {
        if (!dirOk) { root.failStart("Vinyl can't write its queue file. " + why); return }
        root.files.writePrivate(root.queueFile, root.emptyQueue + ok.join("\n") + "\n", root.emptyQueue, function(written, why2) {
          if (!written) { root.failStart("Vinyl can't write its queue file. " + why2); return }
          if (!p || root.players.indexOf(p) === -1) { root.failStart("The player quit."); return }
          // The player would otherwise reorder the list Vinyl already arranged.
          if (restoreShuffle) p.shuffle = false
          root.pendingStart = { player: p, paths: ok, source: source, restoreShuffle: restoreShuffle,
                                before: root.urlPathOf(p), changed: false, started: Date.now() }
          p.openUri(Paths.fileUrl(root.queueFile))
          confirmTimer.restart()
        })
      })
    })
  }

  function urlPathOf(p) {
    return p && p.metadata ? Paths.pathFromUrl(p.metadata["xesam:url"]) : ""
  }

  function failStart(message) {
    queueStarting = false
    queueError = message
  }

  // Confirms within about 3 s that the player is on the first queued file.
  Timer {
    id: confirmTimer
    interval: 100
    repeat: true
    onTriggered: {
      var s = root.pendingStart
      if (!s) { stop(); return }
      var gone = root.players.indexOf(s.player) === -1
      var now = gone ? "" : root.urlPathOf(s.player)
      var confirmed = !gone && now === s.paths[0] && (s.before !== s.paths[0] || s.changed)
      if (!confirmed && !gone && Date.now() - s.started < 3000) return
      stop()
      root.pendingStart = null
      if (!gone && s.restoreShuffle) s.player.shuffle = true
      if (confirmed) {
        root.queue = { paths: s.paths, source: s.source }
        root.lastPlayingKey = root.playerKey(s.player)
        root.player = s.player
        root.queueError = ""
      } else {
        root.queueError = "The player couldn't open “" + Paths.displayName(Paths.baseName(s.paths[0])) + "”."
      }
      root.queueStarting = false
      // The player has read the list; leave no paths behind.
      root.files.writePrivate(root.queueFile, root.emptyQueue, root.emptyQueue, function() {})
    }
  }
}
