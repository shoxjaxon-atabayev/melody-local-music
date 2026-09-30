import QtQuick
import Quickshell.Io

// Melody's own player (owner decision 2026-09-29). Melody plays music itself:
// one headless mpv that it starts when there is something to play and
// controls over mpv's JSON IPC socket in Melody's private runtime folder.
// Nothing needs to be started by hand, and no player window ever opens:
// no video (cover art is never shown as a picture), no terminal, and none
// of the user's mpv configuration or scripts, so mpv.conf can't change how
// Melody plays. mpv-mpris is loaded when installed, so media keys and
// Omarchy's media controls reach Melody too.
//
// The queue, the current track, its position, shuffle, and repeat are saved
// in session.json next to the playlists file (private, 0700/0600): on every
// pause, seek, and track change, and every 5 s while playing. After a
// restart the saved track is shown paused at its saved position; once the
// service has checked the saved paths, the queue is loaded into mpv paused,
// so play resumes exactly there.
//
// Two states: cold (no mpv, or it quit: the saved queue is shown and
// controls act on it) and live (mpv has the queue loaded). mpv's state is
// taken only from its own notifications, never assumed. Every load gets a
// generation number; a newer load turns older callbacks into no-ops.
QtObject {
  id: root

  required property PrivateFiles files
  // $XDG_RUNTIME_DIR/melody (0700): the IPC socket and the temporary queue file.
  property string runtimeFolder: ""
  // $XDG_DATA_HOME/melody (0700): the saved session.
  property string dataFolder: ""
  property string mpvBinary: "/usr/bin/mpv"
  // mpv-mpris; mpv carries on without it when it isn't installed.
  property string mprisScript: "/usr/lib/mpv-mpris/mpris.so"
  // Extra mpv options (the development harness adds --ao=null).
  property var extraArgs: []

  readonly property int maxQueue: 1000
  // The name mpv plays under (PipeWire application and node name); the bar's
  // visualizations find Melody's audio stream by it.
  readonly property string clientName: "Melody"
  readonly property string socketPath: runtimeFolder + "/mpv.sock"
  readonly property string listFile: runtimeFolder + "/queue.m3u"
  readonly property string emptyList: "#EXTM3U\n"
  readonly property string sessionFile: dataFolder + "/session.json"
  readonly property int sessionMaxBytes: 4 * 1024 * 1024

  // ---------------------------------------------------------------- queue state
  property var paths: []            // the queue, in play order
  property var original: []         // the order before shuffling; [] when not shuffled
  property int index: -1
  property var source: null         // { kind: "library"|"search"|"playlist", id, name }
  property real position: 0
  property real length: 0
  property var tags: ({})           // { title, artist, album }: the file's own tags (untrusted)
  property bool paused: true
  property bool shuffle: false
  property bool repeatOne: false
  // The queue's paths passed the library checks in this session (tracks
  // from the library always do; a restored session after the service's
  // check). Only a trusted queue is ever loaded into mpv.
  property bool trusted: false

  readonly property string path: index >= 0 && index < paths.length ? String(paths[index]) : ""
  readonly property bool hasTrack: path !== ""
  // mpv is connected and playing (or paused on) this queue.
  readonly property bool live: ready && loaded
  readonly property bool isPlaying: live && !paused
  readonly property string pid: ready && proc.processId !== undefined && proc.processId !== null
    ? String(proc.processId) : ""

  readonly property bool canGoNext: hasTrack && index < paths.length - 1
  readonly property bool canGoPrevious: hasTrack && index > 0
  readonly property bool canSeek: hasTrack && length > 0

  // Why playback couldn't start or stopped ("" when fine); `mpvMissing`
  // when mpv itself isn't installed.
  property string error: ""
  property bool mpvMissing: false

  // The saved session has been read (or there was none).
  property bool restored: false

  // ---------------------------------------------------------------- mpv state
  property bool ready: false        // connected, properties observed
  property bool loaded: false       // a file of this queue has loaded
  property bool loading: false
  property bool starting: false
  property bool procStarted: false
  property int generation: 0
  // Set by an end-of-file or failed file, cleared when the next one starts:
  // mpv going idle after it means the queue ran out.
  property bool naturalEnd: false
  // mpv's playlist notifications are applied only once mpv holds this
  // queue (never its idle state, nor the steps of a reorder).
  property bool acceptPlaylist: false
  // Applied when the first file of a load is in: { index, position, play }.
  property var pendingStart: null
  property var waiters: []

  // ---------------------------------------------------------------- commands
  // A new queue from the library, already checked; plays list[start].
  function play(list, start, src) {
    var order = list.slice()
    var at = Math.max(0, Math.min(order.length - 1, start))
    var before = []
    if (shuffle && order.length > 1) {
      before = order.slice()
      var first = order[at]
      order.splice(at, 1)
      order = [first].concat(shuffled(order))
      at = 0
    }
    paths = order
    original = before
    index = at
    source = src
    trusted = true
    resetTrack()
    load(true, 0)
    saveSoon()
  }

  function togglePlaying() {
    if (!hasTrack) return
    if (live) {
      send(["set_property", "pause", !paused])
    } else if (loading) {
      if (pendingStart) pendingStart.play = !pendingStart.play
    } else if (trusted) {
      load(true, position)
    }
  }

  function next() { step(1) }
  function previous() { step(-1) }

  function step(delta) {
    if (delta > 0 ? !canGoNext : !canGoPrevious) return
    if (live) {
      send([delta > 0 ? "playlist-next" : "playlist-prev"])
      return
    }
    if (loading) return
    index += delta
    resetTrack()
    if (trusted) load(false, 0)
    saveSoon()
  }

  function seek(seconds) {
    if (!canSeek) return
    var s = Number(seconds)
    if (!isFinite(s)) return
    s = Math.max(0, Math.min(length, s))
    position = s
    if (live) send(["seek", s, "absolute"])
    else if (loading && pendingStart) pendingStart.position = s
    saveSoon()
  }

  function setRepeatOne(on) {
    repeatOne = !!on
    if (ready) send(["set_property", "loop-file", repeatOne ? "inf" : "no"])
    saveSoon()
  }

  // Shuffle keeps the current track playing: on, the rest of the queue is
  // shuffled after it; off, the queue goes back to its original order.
  function setShuffle(on) {
    on = !!on
    if (on === shuffle) return
    shuffle = on
    if (!hasTrack || loading) { original = []; saveSoon(); return }
    var current = path
    if (on) {
      var rest = paths.slice()
      rest.splice(index, 1)
      original = paths.slice()
      reorder([current].concat(shuffled(rest)), 0)
    } else {
      var back = original
      original = []
      var at = back.indexOf(current)
      if (at >= 0 && back.length === paths.length) reorder(back, at)
    }
    saveSoon()
  }

  // After the service's check of a restored queue: keep only `list`.
  function adopt(list, at) {
    paths = list
    index = at
    if (shuffle) original = original.filter(function(p) { return list.indexOf(p) !== -1 })
    trusted = true
    saveSoon()
  }

  // Load the (trusted) queue into mpv, paused at the saved position.
  function warmUp() {
    if (hasTrack && trusted && !live && !loading) load(false, position)
  }

  // Forget the queue (the saved one failed the check, or the queue ran out).
  function forget() {
    generation++
    paths = []
    original = []
    index = -1
    source = null
    trusted = false
    loading = false
    loaded = false
    pendingStart = null
    paused = true
    resetTrack()
    if (ready) send(["playlist-clear"])
    saveSoon()
  }

  function resetTrack() {
    position = 0
    length = 0
    tags = ({})
  }

  function shuffled(list) {
    var a = list.slice()
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1))
      var t = a[i]; a[i] = a[j]; a[j] = t
    }
    return a
  }

  // ---------------------------------------------------------------- loading
  function load(play, startPosition) {
    var gen = ++generation
    var list = paths.slice()
    var at = index
    loading = true
    loaded = false
    acceptPlaylist = false
    naturalEnd = false
    error = ""
    pendingStart = { index: at, position: startPosition > 0 ? startPosition : 0, play: play }
    loadTimeout.restart()
    ensureRunning(function(ok, why) {
      if (gen !== root.generation) return
      if (!ok) { root.loadFailed(why); return }
      root.writeList(list, function(written, why2) {
        if (gen !== root.generation) return
        if (!written) { root.loadFailed(why2); return }
        // Playing from the start: unpause once the new queue is in (never
        // the old track). Otherwise pause first and seek when the file has
        // loaded, so nothing plays from 0.
        var start = root.pendingStart
        var fromStart = !!start && start.play && start.position === 0
        if (!fromStart) root.send(["set_property", "pause", true])
        root.send(["set_property", "loop-file", root.repeatOne ? "inf" : "no"])
        root.send(["set_property", "playlist-start", at])
        root.send(["loadlist", root.listFile, "replace"], function(reply) {
          root.send(["set_property", "playlist-start", "auto"])
          root.clearList()
          if (gen !== root.generation) return
          if (reply.error !== "success") { root.loadFailed("mpv couldn't open the queue."); return }
          if (fromStart && root.pendingStart && root.pendingStart.play) root.send(["set_property", "pause", false])
          root.acceptPlaylist = true
          root.resync()
        })
      })
    })
  }

  function loadFailed(why) {
    loadTimeout.stop()
    loading = false
    loaded = false
    pendingStart = null
    paused = true
    error = why || "Melody couldn't start playback."
  }

  property Timer loadTimeout: Timer {
    interval: 10000
    onTriggered: if (root.loading) root.loadFailed("mpv didn't respond in time.")
  }

  // The queue goes to mpv through a private M3U file, emptied as soon as
  // mpv has read it.
  function writeList(list, callback) {
    files.ensureDir(runtimeFolder, function(dirOk, why) {
      if (!dirOk) { callback(false, "Melody can't write its queue file. " + why); return }
      root.files.writePrivate(root.listFile, root.emptyList + list.join("\n") + "\n", root.emptyList, function(ok, why2) {
        callback(ok, ok ? "" : "Melody can't write its queue file. " + why2)
      })
    })
  }

  function clearList() {
    files.writePrivate(listFile, emptyList, emptyList, function() {})
  }

  // Changes the queue order around the current track without interrupting
  // it: mpv drops every other entry, then gets the others before and after.
  function reorder(order, at) {
    paths = order
    index = at
    if (!live) return
    var gen = generation
    var before = order.slice(0, at)
    var after = order.slice(at + 1)
    acceptPlaylist = false
    send(["playlist-clear"])
    function done() {
      root.clearList()
      if (gen !== root.generation) return
      root.acceptPlaylist = true
      root.resync()
    }
    function insertBefore() {
      if (before.length === 0) { done(); return }
      root.writeList(before, function(ok) {
        if (!ok || gen !== root.generation) { done(); return }
        root.send(["loadlist", root.listFile, "insert-at", 0], done)
      })
    }
    if (after.length === 0) { insertBefore(); return }
    writeList(after, function(ok) {
      if (!ok || gen !== root.generation) { done(); return }
      root.send(["loadlist", root.listFile, "append"], insertBefore)
    })
  }

  // Reads mpv's queue state again once it holds this queue: a notification
  // can arrive before the command's reply, while it is still ignored.
  function resync() {
    var gen = generation
    function take(name) {
      root.send(["get_property", name], function(r) {
        if (r.error === "success" && gen === root.generation && root.acceptPlaylist) root.takeProperty(name, r.data)
      })
    }
    take("playlist")
    take("playlist-pos")
    take("pause")
  }

  // ---------------------------------------------------------------- the mpv process
  // setpriv (util-linux) has the kernel stop mpv when the shell goes away,
  // even when it is killed, so no mpv is ever left playing on its own.
  function mpvCommand() {
    var args = ["/usr/bin/setpriv", "--pdeathsig", "TERM", "--", mpvBinary,
      "--no-config",                  // none of the user's mpv.conf, input.conf, or scripts
      "--idle=yes",
      "--no-terminal",
      "--vid=no",                     // audio only: never a window, not even for cover art
      "--force-window=no",
      "--audio-display=no",
      "--ytdl=no",                    // local files only, never online
      "--load-scripts=no",
      "--resume-playback=no",         // Melody keeps positions itself
      "--save-position-on-quit=no",
      "--audio-client-name=" + clientName,
      "--input-ipc-server=" + socketPath]
    if (mprisScript !== "") args.push("--script=" + mprisScript)
    return args.concat(extraArgs)
  }

  // callback(ok, reason) once mpv is connected.
  function ensureRunning(callback) {
    if (ready) { callback(true, ""); return }
    waiters.push(callback)
    if (starting) return
    starting = true
    files.ensureDir(runtimeFolder, function(ok, why) {
      if (!ok) { root.startFailed("Melody can't use its private runtime folder. " + why, false); return }
      root.quitStale(function() {
        root.procStarted = false
        root.proc.command = root.mpvCommand()
        root.proc.running = true
      })
    })
  }

  // An mpv left behind by a shell that didn't exit cleanly (a crash) still
  // listens on Melody's socket and may still be playing: ask it to quit
  // before starting a new one. `then` runs once nothing answers there.
  property Component probeComponent: Component { Socket {} }
  property var staleDone: null

  property Timer staleTimer: Timer {
    interval: 2000
    onTriggered: if (root.staleDone) root.staleDone()
  }

  function quitStale(then) {
    var s = probeComponent.createObject(root, { path: socketPath })
    var over = false
    function done() {
      if (over) return
      over = true
      root.staleDone = null
      root.staleTimer.stop()
      Qt.callLater(function() { s.destroy() })
      then()
    }
    staleDone = done
    staleTimer.restart()
    s.connectionStateChanged.connect(function() {
      if (s.connected) {
        s.write("{\"command\":[\"quit\"]}\n")
        s.flush()
      } else {
        done()
      }
    })
    s.error.connect(function() { if (!s.connected) done() })
    s.connected = true
  }

  function startFailed(why, missing) {
    starting = false
    connectTimer.stop()
    mpvMissing = !!missing
    var list = waiters
    waiters = []
    for (var i = 0; i < list.length; i++) list[i](false, why)
  }

  property Process proc: Process {
    onStarted: {
      root.procStarted = true
      root.mpvMissing = false
      root.connectTries = 0
      root.connectTimer.interval = 120
      root.connectTimer.restart()
    }
    onRunningChanged: {
      if (!running && root.starting && !root.procStarted) root.startFailed(root.missingText, true)
    }
    onExited: (code, status) => root.processGone(code)
  }

  readonly property string missingText: "Melody plays music with mpv, which isn't installed."

  // mpv quit or crashed: back to cold, keeping the queue and position, so
  // the next play starts mpv again and resumes there. (127: setpriv found
  // no mpv to run.)
  function processGone(code) {
    var wasStarting = starting && !ready
    connectTimer.stop()
    closeIpc()
    ready = false
    loaded = false
    acceptPlaylist = false
    paused = true
    if (wasStarting) {
      var missing = code === 127
      startFailed(missing ? missingText : "mpv stopped right after starting.", missing)
    }
    if (loading) loadFailed(mpvMissing ? missingText : "mpv stopped unexpectedly.")
    starting = false
    saveSoon()
  }

  // ---------------------------------------------------------------- IPC
  // Quickshell's Socket can't retry a failed connection, so each attempt
  // gets a fresh one (mpv creates its socket a moment after starting).
  property Component socketComponent: Component {
    Socket {
      parser: SplitParser {
        onRead: (line) => root.receive(line)
      }
    }
  }

  property var ipc: null
  property int connectTries: 0
  property int nextRequest: 1
  property var pending: ({})

  property Timer connectTimer: Timer {
    onTriggered: root.tryConnect()
  }

  function tryConnect() {
    if (!proc.running || ipc) return
    connectTries++
    var s = socketComponent.createObject(root, { path: socketPath })
    s.connectionStateChanged.connect(function() { root.socketStateChanged(s) })
    s.error.connect(function() { root.socketError(s) })
    s.connected = true
  }

  function socketStateChanged(s) {
    if (s.connected) {
      if (ipc) return
      ipc = s
      connectTimer.stop()
      connectedToMpv()
    } else if (s === ipc) {
      // mpv closed the connection: it is quitting; `exited` follows.
      closeIpc()
      ready = false
      loaded = false
    }
  }

  function socketError(s) {
    if (s === ipc) return
    Qt.callLater(function() { s.destroy() })
    if (!proc.running || ipc) return
    if (connectTries >= 60) {
      startFailed("Melody couldn't connect to mpv.", false)
      proc.running = false
      return
    }
    connectTimer.interval = 80
    connectTimer.restart()
  }

  function closeIpc() {
    var s = ipc
    ipc = null
    var calls = pending
    pending = ({})
    for (var id in calls) calls[id]({ error: "disconnected" })
    if (s) Qt.callLater(function() { s.destroy() })
  }

  readonly property var observed: ["pause", "playlist", "playlist-pos", "duration", "metadata", "idle-active", "loop-file"]

  function connectedToMpv() {
    for (var i = 0; i < observed.length; i++) send(["observe_property", i + 1, observed[i]])
    ready = true
    starting = false
    var list = waiters
    waiters = []
    for (var j = 0; j < list.length; j++) list[j](true, "")
  }

  function send(args, callback) {
    if (!ipc || !ipc.connected) {
      if (callback) callback({ error: "disconnected" })
      return
    }
    var id = nextRequest++
    if (callback) pending[id] = callback
    ipc.write(JSON.stringify({ command: args, request_id: id }) + "\n")
    ipc.flush()
  }

  function receive(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (!msg || typeof msg !== "object") return
    if (msg.event === undefined) {
      var cb = pending[msg.request_id]
      delete pending[msg.request_id]
      if (cb) cb(msg)
      return
    }
    switch (msg.event) {
    case "property-change": takeProperty(msg.name, msg.data); break
    case "start-file": naturalEnd = false; break
    case "end-file": if (msg.reason === "eof" || msg.reason === "error") naturalEnd = true; break
    case "file-loaded": fileLoaded(); break
    case "playback-restart": if (live) pollPosition(true); break
    }
  }

  function takeProperty(name, data) {
    switch (name) {
    case "pause":
      var p = data === true
      if (p === paused) return
      paused = p
      if (live) pollPosition(true)
      break
    case "playlist": if (acceptPlaylist) takePlaylist(data); break
    case "playlist-pos": if (acceptPlaylist) takePos(data); break
    case "duration":
      if (acceptPlaylist) length = typeof data === "number" && isFinite(data) && data > 0 ? data : 0
      break
    case "metadata": if (acceptPlaylist) tags = pickTags(data); break
    case "idle-active": if (data === true) wentIdle(); break
    case "loop-file":
      // Only mpv's answer for this queue (e.g. repeat set by a media key);
      // its idle default must not replace a restored setting.
      if (live) repeatOne = data === "inf" || data === "yes" || data === true || (typeof data === "number" && data > 0)
      break
    }
  }

  function takePlaylist(data) {
    if (!Array.isArray(data)) return
    var list = []
    for (var i = 0; i < data.length; i++) list.push(data[i] && data[i].filename !== undefined ? String(data[i].filename) : "")
    var same = list.length === paths.length
    for (var j = 0; same && j < list.length; j++) same = list[j] === paths[j]
    if (!same) paths = list
  }

  function takePos(data) {
    if (typeof data !== "number" || data < 0 || data === index) return
    index = data
    resetTrack()
    saveSoon()
  }

  function fileLoaded() {
    if (!acceptPlaylist) return
    loaded = true
    error = ""
    if (!loading) return
    loading = false
    loadTimeout.stop()
    var start = pendingStart
    pendingStart = null
    if (!start) return
    if (start.position > 0 && index === start.index) {
      position = start.position
      send(["seek", start.position, "absolute"])
    }
    // Play or pause as last asked (play/pause may be pressed while loading).
    send(["set_property", "pause", !start.play])
  }

  // mpv idles after the last file ends (or after every file failed): the
  // queue is over.
  function wentIdle() {
    if (!naturalEnd || !acceptPlaylist) return
    naturalEnd = false
    var failed = loading
    forget()
    if (failed) error = "None of these tracks could be played."
  }

  function pickTags(meta) {
    var out = { title: "", artist: "", album: "" }
    if (!meta || typeof meta !== "object") return out
    for (var k in meta) {
      var key = String(k).toLowerCase()
      if (key in out && out[key] === "") out[key] = String(meta[k]).slice(0, 1000)
    }
    return out
  }

  // ---------------------------------------------------------------- position
  // mpv doesn't stream the position; it is read once a second while
  // playing, and right after a pause or seek.
  property real lastSaveAt: 0

  property Timer tick: Timer {
    interval: 1000
    repeat: true
    running: root.isPlaying
    onTriggered: root.pollPosition(Date.now() - root.lastSaveAt >= 5000)
  }

  function pollPosition(thenSave) {
    send(["get_property", "time-pos"], function(r) {
      if (r.error === "success" && typeof r.data === "number" && isFinite(r.data) && r.data >= 0)
        root.position = root.length > 0 ? Math.min(r.data, root.length) : r.data
      if (thenSave) root.saveSoon()
    })
  }

  // ---------------------------------------------------------------- session file
  property bool saving: false
  property bool saveAgain: false
  property bool sessionOnDisk: false

  property Timer saveTimer: Timer {
    interval: 400
    onTriggered: root.saveNow()
  }

  function saveSoon() {
    if (restored && dataFolder !== "") saveTimer.restart()
  }

  function sessionText() {
    if (!hasTrack) return "{\n  \"version\": 1,\n  \"paths\": [],\n  \"index\": -1\n}\n"
    return JSON.stringify({
      version: 1, paths: paths, original: shuffle ? original : [], index: index,
      position: Math.round(position * 10) / 10, length: length, tags: tags, source: source,
      shuffle: shuffle, repeatOne: repeatOne
    }) + "\n"
  }

  function saveNow() {
    if (!restored || dataFolder === "") return
    if (saving) { saveAgain = true; return }
    // Nothing to keep and nothing saved before: don't create the file.
    if (!hasTrack && !sessionOnDisk) return
    saving = true
    lastSaveAt = Date.now()
    var text = sessionText()
    function done(ok) {
      root.saving = false
      if (ok) root.sessionOnDisk = true
      if (root.saveAgain) { root.saveAgain = false; root.saveNow() }
    }
    function fail(why) {
      console.warn("Melody: can't save the playback session: " + why)
      done(false)
    }
    // One look at the folder and the file (never through a symlink). Both
    // private: replace the file (atomic). Otherwise the careful path, which
    // creates the folder 0700 and the file 0600 — a plain write would
    // recreate a deleted folder with default permissions.
    files.inspect([dataFolder, sessionFile], function(map) {
      if (map && root.files.dirProblem(map[root.dataFolder]) === "" && root.files.fileProblem(map[root.sessionFile]) === "") {
        root.files.writeText(root.sessionFile, text, function(ok, why) { if (ok) done(true); else fail(why) })
        return
      }
      root.files.ensureDir(root.dataFolder, function(ok, why) {
        if (!ok) { fail(why); return }
        root.files.writePrivate(root.sessionFile, text, "{}\n", function(ok2, why2) { if (ok2) done(true); else fail(why2) })
      })
    })
  }

  function restore() {
    if (dataFolder === "") { restored = true; return }
    files.readPrivate(sessionFile, sessionMaxBytes, false, function(r) {
      if (r.state === "ok") {
        root.sessionOnDisk = true
        // Something started while the file was read: that wins.
        if (!root.hasTrack) root.applySession(r.text)
      } else if (r.state !== "absent") {
        console.warn("Melody: the saved playback session can't be read: " + (r.reason || r.state))
      }
      root.restored = true
    })
  }

  function strings(list, max) {
    if (!Array.isArray(list) || list.length > max) return null
    for (var i = 0; i < list.length; i++)
      if (typeof list[i] !== "string" || list[i].length === 0 || list[i].length > 4096) return null
    return list
  }

  // A damaged or unexpected file is ignored (and replaced on the next save).
  function applySession(text) {
    var s
    try { s = JSON.parse(text) } catch (e) { return }
    if (!s || s.version !== 1) return
    var list = strings(s.paths, maxQueue)
    if (!list || list.length === 0) return
    var at = s.index
    if (typeof at !== "number" || at % 1 !== 0 || at < 0 || at >= list.length) return
    var orig = strings(s.original || [], maxQueue) || []
    var src = s.source && typeof s.source === "object" && ["library", "search", "playlist"].indexOf(s.source.kind) !== -1
      ? { kind: s.source.kind, id: String(s.source.id || "").slice(0, 4096), name: String(s.source.name || "").slice(0, 300) }
      : { kind: "library", id: "", name: "Library" }
    var t = s.tags && typeof s.tags === "object" ? s.tags : {}
    paths = list
    index = at
    source = src
    shuffle = s.shuffle === true
    original = shuffle && orig.length === list.length ? orig : []
    repeatOne = s.repeatOne === true
    length = typeof s.length === "number" && isFinite(s.length) && s.length > 0 ? s.length : 0
    var pos = typeof s.position === "number" && isFinite(s.position) && s.position > 0 ? s.position : 0
    position = length > 0 ? Math.min(pos, length) : pos
    tags = { title: String(t.title || "").slice(0, 1000), artist: String(t.artist || "").slice(0, 1000),
             album: String(t.album || "").slice(0, 1000) }
    paused = true
    trusted = false
  }

  // After the service's bindings (the folders) are in place.
  Component.onCompleted: Qt.callLater(restore)

  // Quit mpv with the service (the Process kills it anyway).
  Component.onDestruction: {
    if (ipc && ipc.connected) {
      ipc.write("{\"command\":[\"quit\"]}\n")
      ipc.flush()
    }
  }
}
