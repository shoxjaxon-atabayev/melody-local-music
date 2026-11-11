
import QtQuick
import Quickshell.Io

// Runs one short-lived /usr/bin/find at a time.
// Output is consumed incrementally and bounded.
QtObject {
  id: root

  property int timeoutMs: 5000
  property int maxRecords: 100000
  property int maxOutputChars: 4 * 1024 * 1024
  property int maxErrorChars: 8192

  signal finished(string tag, var records, string status, string errors)

  readonly property bool busy: proc.running || pending !== null

  property var current: null
  property var pending: null

  function run(tag, args, stdinPaths) {
    var job = {
      tag: tag,
      args: args,
      stdin: stdinPaths || null,
      records: [],
      outputChars: 0,
      errors: "",
      timedOut: false,
      cancelled: false,
      outputLimited: false
    }

    if (proc.running) {
      if (current) current.cancelled = true
      pending = job
      stopCurrentProcess()
      return
    }

    start(job)
  }

  function cancel() {
    pending = null

    if (proc.running) {
      if (current) current.cancelled = true
      stopCurrentProcess()
    }
  }

  function stopCurrentProcess() {
    proc.running = false
    forceKillTimer.restart()
  }

  function acceptRecord(record) {
    var job = current
    if (!job || job.cancelled || job.outputLimited) return
    if (record.length === 0) return

    var nextChars = job.outputChars + record.length + 1

    if (job.records.length >= maxRecords || nextChars > maxOutputChars) {
      job.outputLimited = true
      stopCurrentProcess()
      return
    }

    job.records.push(record)
    job.outputChars = nextChars
  }

  function acceptError(line) {
    var job = current
    if (!job || job.cancelled) return

    var remaining = maxErrorChars - job.errors.length
    if (remaining <= 0) return

    job.errors += line.slice(0, remaining)
    if (job.errors.length < maxErrorChars) job.errors += "\n"
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
    stdout: SplitParser {
      splitMarker: "\u0000"
      onRead: data => root.acceptRecord(data)
    }

    stderr: SplitParser {
      splitMarker: "\n"
      onRead: data => root.acceptError(data)
    }

    onStarted: {
      var job = root.current
      if (job && job.stdin !== null) {
        write(job.stdin.join("\u0000") + (job.stdin.length ? "\u0000" : ""))
        stdinEnabled = false
      }
    }

    onExited: (code, status) => {
      timer.stop()
      forceKillTimer.stop()

      var job = root.current
      root.current = null

      if (job && !job.cancelled) {
        var result = job.outputLimited
          ? "failed"
          : (job.timedOut ? "timedOut" : (code === 0 || code === 1 ? "ok" : "failed"))

        var errors = job.outputLimited
          ? "find output exceeded the configured limit"
          : job.errors

        root.finished(
          job.tag,
          job.outputLimited ? [] : job.records,
          result,
          errors
        )
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
      root.stopCurrentProcess()
    }
  }

  property Timer forceKillTimer: Timer {
    interval: 250
    repeat: false

    onTriggered: {
      if (root.proc.running)
        root.proc.signal(9)
    }
  }
}
