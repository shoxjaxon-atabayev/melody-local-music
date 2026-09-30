import QtQuick
import Quickshell
import qs.Commons

// What Melody runs, checked by the files it runs (`find -H`, no shell), and a
// one-click install of whatever is missing:
//   mpv        plays the music
//   mpv-mpris  media keys, Omarchy's media controls, and cover art
//   cava       the Spectrum bar display
// Install opens Omarchy's floating terminal (as Omarchy's own system update
// does) running `omarchy-pkg-add` for the missing packages; sudo asks for
// the password there. The terminal is detached, so the install is followed
// through a marker file in the private runtime folder: the terminal's shell
// creates it empty when it starts and writes to it when it exits, also when
// its window is closed. Meanwhile the packages are checked every second.
// The install is over when they are all there, when the shell has exited,
// or when the terminal hasn't started within 20 seconds.
QtObject {
  id: root

  // The paths the player code runs.
  property string mpvBinary: ""
  property string mprisScript: ""
  property string cavaBinary: ""

  readonly property var packages: [
    { name: "mpv", path: mpvBinary },
    { name: "mpv-mpris", path: mprisScript },
    { name: "cava", path: cavaBinary }
  ].filter(function(p) { return p.path !== "" })

  // Package names not installed, in the order above. Kept from the last
  // check that worked; valid once `checked`.
  property var missing: []
  property bool checked: false
  // "idle", "installing", or "failed" (the terminal closed, or didn't
  // open, with packages still missing).
  property string installState: "idle"
  readonly property bool installing: installState === "installing"

  // Everything is installed after an install from here.
  signal installed()

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property int startTimeoutMs: 20000

  property string marker: ""
  property bool markerSeen: false
  property double launchedAt: 0

  function check() {
    var paths = packages.map(function(p) { return p.path })
    if (marker !== "") paths.push(marker)
    finder.run("check", ["-H"].concat(paths).concat(["-maxdepth", "0", "-printf", "%s\\t%p\\0"]))
  }

  function install() {
    if (installing || missing.length === 0) return
    // The marker's path goes into the terminal's command line: plain path
    // characters only.
    var m = runtimeDir + "/melody-install-" + Date.now()
    if (runtimeDir === "" || !/^\/[A-Za-z0-9._\/-]+$/.test(m)) {
      installState = "failed"
      return
    }
    marker = m
    markerSeen = false
    launchedAt = Date.now()
    installState = "installing"
    var q = Util.shellQuote(m)
    var command = "trap " + Util.shellQuote("echo done > " + q) + " EXIT; : > " + q
      + "; echo " + Util.shellQuote("Installing " + missing.join(", ") + " for Melody…")
      + "; omarchy-pkg-add " + missing.join(" ")
    Util.execArgv([omarchyPath + "/bin/omarchy-launch-floating-terminal-with-presentation", command])
  }

  function finishInstall(state) {
    installState = state
    if (marker !== "") Quickshell.execDetached(["/usr/bin/rm", "-f", "--", marker])
    marker = ""
    if (state === "idle") installed()
  }

  property Finder finder: Finder {
    timeoutMs: 5000
    onFinished: (tag, records, status, errors) => {
      if (status !== "ok") return
      var found = {}
      for (var i = 0; i < records.length; i++) {
        var tab = records[i].indexOf("\t")
        if (tab > 0) found[records[i].slice(tab + 1)] = Number(records[i].slice(0, tab))
      }
      root.missing = root.packages.filter(function(p) { return found[p.path] === undefined })
        .map(function(p) { return p.name })
      root.checked = true
      if (!root.installing) return
      if (found[root.marker] !== undefined) root.markerSeen = true
      if (root.missing.length === 0) root.finishInstall("idle")
      else if (found[root.marker] > 0) root.finishInstall("failed")
      else if (!root.markerSeen && Date.now() - root.launchedAt > root.startTimeoutMs) root.finishInstall("failed")
    }
  }

  property Timer poll: Timer {
    interval: 1000
    repeat: true
    running: root.installing
    onTriggered: root.check()
  }

  Component.onCompleted: check()
}
