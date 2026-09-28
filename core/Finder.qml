import QtQuick
import Quickshell.Io

// Runs one short-lived /usr/bin/find at a time: arguments passed directly
// (never through a shell), optional starting points on stdin, NUL-separated
// output, and a timeout. A newer request cancels the one in flight; its
// results are dropped. `finished(tag, records, status, errors)` reports
// status "ok", "timedOut", "cancelled", or "failed".
QtObject {
  id: root

  property int timeoutMs: 5000

  signal finished(string tag, var records, string status, string errors)

  readonly property bool busy: proc.running || pending !== null

  property var current: null     // { tag, args, stdin, timedOut, cancelled }
  property var pending: null

  function run(tag, args, stdinPaths) {
    var job = { tag: tag, args: args, stdin: stdinPaths || null, timedOut: false, cancelled: false }
    if (proc.running) {
      if (current) current.cancelled = true
      pending = job
      proc.running = false
      return
    }
    start(job)
  }

  function cancel() {
    pending = null
    if (proc.running) {
      if (current) current.cancelled = true
      proc.running = false
    }
  }

  function start(job) {
    current = job
    proc.command = ["/usr/bin/find"].concat(job.args)
    proc.stdinEnabled = job.stdin !== null
    proc.running = true
    timer.interval = timeoutMs
    timer.restart()
  }

  property Process proc: Process {
    stdout: StdioCollector { id: out }
    stderr: StdioCollector { id: err }
    onStarted: {
      var job = root.current
      if (job && job.stdin !== null) {
        write(job.stdin.join("\u0000") + (job.stdin.length ? "\u0000" : ""))
        stdinEnabled = false      // close stdin: find reads to end of input
      }
    }
    onExited: (code, status) => {
      timer.stop()
      var job = root.current
      root.current = null
      if (job && !job.cancelled) {
        var text = out.text
        var records = text.length ? text.split("\u0000") : []
        if (records.length && records[records.length - 1] === "") records.pop()
        var result = job.timedOut ? "timedOut" : (code === 0 || code === 1 ? "ok" : "failed")
        root.finished(job.tag, records, result, err.text)
      }
      if (root.pending) {
        var next = root.pending
        root.pending = null
        root.start(next)
      }
    }
  }

  property Timer timer: Timer {
    onTriggered: {
      if (!root.proc.running || !root.current) return
      root.current.timedOut = true
      root.proc.running = false
    }
  }
}
