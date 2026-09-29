import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import "BarDisplay.js" as BarDisplay

// Real audio data for the bar's Spectrum and Pulse Dots modes (owner
// decision 2026-09-28), read only from the selected player's own PipeWire
// output stream: never the speaker mix, never another application.
//
//   Pulse Dots: Quickshell's PwNodePeakMonitor on that stream (in-process,
//     no helper), giving the signal's peak level.
//   Spectrum: cava (an optional package) reading that stream, giving
//     frequency bands. Without cava, Spectrum reports "noCava" and nothing
//     moves.
//
// Nothing is sampled unless a bar is showing a visualization and the player
// is playing: output streams aren't bound, the peak monitor is off, and
// cava isn't running. Pausing, stopping, losing the stream, or the player
// quitting stops sampling and drops every level to zero.
QtObject {
  id: root

  required property PrivateFiles files
  property var player: null
  // Vinyl's own player: its mpv's process id (instead of `player`).
  property string processId: ""
  property string trackTitle: ""
  property bool playing: false
  // A bar is currently showing a visualization.
  property bool viewed: false
  property string mode: BarDisplay.TRACK_INFO
  // Private runtime folder (0700) that holds cava's config file.
  property string folder: ""
  property string cavaBinary: "/usr/bin/cava"
  readonly property int bandCount: 10

  readonly property bool wantPeaks: viewed && playing && mode === BarDisplay.PULSE_DOTS
  readonly property bool wantBands: viewed && playing && mode === BarDisplay.SPECTRUM
  readonly property bool wantStream: wantPeaks || wantBands

  // What the current visualization can show: "idle" (nothing wanted),
  // "live", "noStream" (the player's stream isn't found), "noCava", or
  // "failed" (cava kept exiting).
  readonly property string status: {
    if (wantPeaks) return stream ? "live" : "noStream"
    if (!wantBands) return "idle"
    if (cavaState === "missing") return "noCava"
    if (cavaFailed) return "failed"
    return stream ? "live" : "noStream"
  }

  // ---------------------------------------------------------------- the player's stream
  // Output streams (applications playing audio), bound only while needed so
  // their properties (application name, process id, serial) can be read.
  readonly property var outputStreams: wantStream && Pipewire.ready
    ? Pipewire.nodes.values.filter(function(n) { return n && n.isStream && !n.isSink }) : []
  property PwObjectTracker tracker: PwObjectTracker { objects: root.outputStreams }

  readonly property var playerIds: processId !== "" ? { names: [], pid: processId } : identify(player)
  readonly property var stream: pickStream(outputStreams, playerIds, trackTitle)

  // The names and process id the player is known by on D-Bus: "mpv" from
  // org.mpris.MediaPlayer2.mpv, and 1234 from ….mpv.instance1234 (added by
  // mpv-mpris and others when several instances run).
  function identify(p) {
    var ids = { names: [], pid: "" }
    if (!p) return ids
    function add(v) {
      var s = String(v || "").toLowerCase().trim()
      if (s !== "" && ids.names.indexOf(s) === -1) ids.names.push(s)
    }
    var bus = String(p.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "")
    var m = /^(.*)\.instance_?(\d+)$/.exec(bus)
    if (m) { ids.pid = m[2]; bus = m[1] }
    add(bus)
    add(bus.split(".").pop())
    var entry = String(p.desktopEntry || "").replace(/\.desktop$/, "")
    add(entry)
    add(entry.split(".").pop())
    var identity = String(p.identity || "")
    add(identity)
    add(identity.split(/\s+/)[0])
    return ids
  }

  // The player's stream: by process id when known, otherwise by name
  // (binary, application name, node name). With several streams of the
  // same player, the one whose media name mentions the track wins.
  function pickStream(streams, ids, title) {
    if (ids.names.length === 0 && ids.pid === "") return null
    var matches = []
    for (var i = 0; i < streams.length; i++) {
      var n = streams[i]
      if (!n || !n.ready) continue
      var props = n.properties || {}
      if (ids.pid !== "") {
        if (String(props["application.process.id"] || "") === ids.pid) matches.push(n)
        continue
      }
      var keys = [props["application.process.binary"], props["application.name"], props["node.name"], n.name]
      for (var k = 0; k < keys.length; k++) {
        if (ids.names.indexOf(String(keys[k] || "").toLowerCase()) !== -1) { matches.push(n); break }
      }
    }
    if (matches.length <= 1) return matches.length ? matches[0] : null
    var t = title.toLowerCase()
    for (var j = 0; t !== "" && j < matches.length; j++) {
      if (String((matches[j].properties || {})["media.name"] || "").toLowerCase().indexOf(t) !== -1) return matches[j]
    }
    return matches[0]
  }

  // ---------------------------------------------------------------- Pulse Dots
  // The peak level on a meter scale (the top 48 dB mapped to 0…1), rising
  // at once and falling over 300 ms. `echo1` and `echo2` are the level about
  // 70 and 140 ms earlier, so a peak ripples outward across the dots.
  property real level: 0
  property real echo1: 0
  property real echo2: 0
  property real lastPeakAt: 0
  property real lastShiftAt: 0
  property real lastCommitAt: 0
  property real pendingLevel: 0

  property PwNodePeakMonitor peakMonitor: PwNodePeakMonitor {
    node: root.wantPeaks ? root.stream : null
    enabled: root.wantPeaks && root.stream !== null
    onPeakChanged: root.takePeak(peak)
  }

  function meter(peak) {
    var p = Number(peak)
    if (!isFinite(p) || p <= 0) return 0
    var db = 20 * Math.log(Math.min(p, 1)) / Math.LN10
    return Math.max(0, Math.min(1, 1 + db / 48))
  }

  function takePeak(peak) {
    if (!wantPeaks || !stream) return
    var now = Date.now()
    pendingLevel = Math.max(pendingLevel, meter(peak))
    // At most ~30 updates a second reach the bar.
    if (now - lastCommitAt < 33) return
    var dt = lastPeakAt > 0 ? now - lastPeakAt : 0
    lastPeakAt = now
    lastCommitAt = now
    level = Math.max(pendingLevel, level - dt / 300)
    pendingLevel = 0
    if (now - lastShiftAt >= 70) {
      echo2 = echo1
      echo1 = level
      lastShiftAt = now
    }
  }

  function resetPeaks() {
    level = 0; echo1 = 0; echo2 = 0
    lastPeakAt = 0; lastShiftAt = 0; lastCommitAt = 0; pendingLevel = 0
  }

  onWantPeaksChanged: resetPeaks()
  onStreamChanged: resetPeaks()

  // ---------------------------------------------------------------- Spectrum
  // cava's bands, 0…1, low to high frequencies.
  property var bands: zeros()
  // "unknown", "checking", "available", or "missing".
  property string cavaState: "unknown"
  property bool cavaFailed: false
  property int cavaFailures: 0
  property var cavaProc: null
  property string cavaSource: ""        // object.serial the running cava reads
  property int cavaRun: 0               // bumped on every start and stop

  readonly property string configPath: folder !== "" ? folder + "/cava.conf" : ""
  // The stream's serial, digits only (it goes into cava's config file).
  readonly property string bandSource: {
    if (!wantBands || !stream || !stream.ready) return ""
    var serial = String((stream.properties || {})["object.serial"] || "")
    return /^\d+$/.test(serial) ? serial : ""
  }
  readonly property string wantedSource: cavaState === "available" && !cavaFailed && configPath !== "" ? bandSource : ""

  function zeros() {
    var z = []
    for (var i = 0; i < bandCount; i++) z.push(0)
    return z
  }

  // Whether cava is installed: `cava -v` either starts or fails to start.
  // Checked when Spectrum is chosen, so a newly installed cava is found
  // without a restart.
  property Process cavaProbe: Process {
    property bool didStart: false
    command: [root.cavaBinary, "-v"]
    onStarted: didStart = true
    onRunningChanged: if (!running) root.cavaState = didStart ? "available" : "missing"
  }

  function checkCava() {
    if (cavaProbe.running) return
    cavaFailed = false
    cavaFailures = 0
    cavaState = "checking"
    cavaProbe.didStart = false
    cavaProbe.running = true
  }

  onModeChanged: if (mode === BarDisplay.SPECTRUM) checkCava()
  onBandSourceChanged: { cavaFailed = false; cavaFailures = 0 }
  onWantedSourceChanged: syncCava()
  Component.onCompleted: if (mode === BarDisplay.SPECTRUM) checkCava()
  Component.onDestruction: stopCava()

  property Component cavaComponent: Component {
    Process {
      id: proc
      property bool didStart: false
      stdout: SplitParser { onRead: (line) => root.takeBands(line, proc) }
      onStarted: didStart = true
      onExited: (code, status) => root.cavaExited(proc)
      // A binary that can't be started emits no `exited` (cava was removed
      // since the last check).
      onRunningChanged: if (!running && !didStart) root.cavaMissing(proc)
    }
  }

  function cavaMissing(proc) {
    if (proc !== cavaProc) return
    stopCava()
    cavaState = "missing"
  }

  function syncCava() {
    if (wantedSource === cavaSource) return
    stopCava()
    if (wantedSource !== "") startCava(wantedSource)
  }

  function startCava(source) {
    var run = ++cavaRun
    cavaSource = source
    files.ensureDir(folder, function(dirOk) {
      if (run !== root.cavaRun) return
      if (!dirOk) { root.giveUp(); return }
      files.writePrivate(root.configPath, root.cavaConfig(source), "\n", function(written) {
        if (run !== root.cavaRun) return
        if (!written) { root.giveUp(); return }
        var proc = root.cavaComponent.createObject(root, { command: [root.cavaBinary, "-p", root.configPath] })
        root.cavaProc = proc
        proc.running = true
      })
    })
  }

  function stopCava() {
    cavaRun++
    cavaSource = ""
    var proc = cavaProc
    cavaProc = null
    if (proc) {
      proc.running = false
      proc.destroy()
    }
    bands = zeros()
  }

  function giveUp() {
    stopCava()
    cavaFailed = true
  }

  // cava quit on its own (stream gone, error): retry twice, 2 s apart.
  function cavaExited(proc) {
    if (proc !== cavaProc) return
    stopCava()
    if (++cavaFailures >= 3) { cavaFailed = true; return }
    retryTimer.restart()
  }

  property Timer retryTimer: Timer {
    interval: 2000
    onTriggered: root.syncCava()
  }

  function takeBands(line, proc) {
    if (proc !== cavaProc) return
    var frame = parseFrame(line)
    if (!frame) return
    bands = frame
    cavaFailures = 0
  }

  // One cava frame, "12;40;…;" (values 0–100), as `bandCount` levels 0…1;
  // null for anything else. cava may put a terminal-title escape before its
  // first frame; that is stripped.
  function parseFrame(line) {
    var parts = String(line).replace(/\x1b\][^\x07]*\x07/g, "").split(";")
    var out = []
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] === "") continue
      var v = Number(parts[i])
      if (!isFinite(v)) return null
      out.push(Math.max(0, Math.min(1, v / 100)))
    }
    return out.length === bandCount ? out : null
  }

  function cavaConfig(source) {
    return [
      "# Written by Vinyl for the bar's Spectrum; replaced as needed.",
      "[general]",
      "framerate = 30",
      "bars = " + bandCount,
      "autosens = 1",
      "sleep_timer = 0",
      "lower_cutoff_freq = 50",
      "higher_cutoff_freq = 12000",
      "[input]",
      "method = pipewire",
      "source = " + source,
      "[output]",
      "method = raw",
      "raw_target = /dev/stdout",
      "data_format = ascii",
      "ascii_max_range = 100",
      "bar_delimiter = 59",
      "frame_delimiter = 10",
      "channels = mono",
      "mono_option = average",
      "[smoothing]",
      "noise_reduction = 70",
      ""
    ].join("\n")
  }
}
