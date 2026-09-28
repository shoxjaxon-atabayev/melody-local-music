import QtQuick
import "Paths.js" as Paths

// Checks paths (playlist entries, queue tracks) against the library rules:
// text checks first (inside the root, normalized, no hidden folders,
// allowlisted extension, no line breaks), then one `find -P` over every
// folder level and file below the root, which never follows a symlink.
// Statuses: "ok", "missing", "outside" (not in this library), "symlink",
// "notfile", "unreadable", "invalid", "timedOut".
QtObject {
  id: root

  property int timeoutMs: 5000

  property var job: null     // { root, paths, checks, callback }

  property Finder finder: Finder {
    timeoutMs: root.timeoutMs
    onFinished: (tag, records, status, errors) => root.finish(records, status)
  }

  // callback(statuses): an array parallel to `paths`.
  function validate(libraryRoot, paths, callback) {
    var checks = [], starts = {}, stdin = []
    for (var i = 0; i < paths.length; i++) {
      var c = libraryRoot ? Paths.precheck(libraryRoot, paths[i]) : { status: "outside" }
      checks.push(c)
      if (c.status !== "pending") continue
      for (var a = 0; a < c.ancestors.length; a++) {
        if (!starts[c.ancestors[a]]) { starts[c.ancestors[a]] = true; stdin.push(c.ancestors[a]) }
      }
      if (!starts[paths[i]]) { starts[paths[i]] = true; stdin.push(paths[i]) }
    }
    job = { paths: paths, checks: checks, callback: callback }
    if (stdin.length === 0) { finish([], "ok"); return }
    finder.run("validate", ["-P", "-files0-from", "-", "-maxdepth", "0",
                            "(", "-readable", "-printf", "r", "-o", "-printf", "-", ")",
                            "-printf", "%y\\t%p\\0"], stdin)
  }

  function cancel() {
    job = null
    finder.cancel()
  }

  function finish(records, status) {
    var j = job
    job = null
    if (!j) return
    var info = {}
    for (var i = 0; i < records.length; i++) {
      var r = records[i]
      var tab = r.indexOf("\t")
      if (tab < 2) continue
      info[r.slice(tab + 1)] = { readable: r.charAt(0) === "r", type: r.charAt(1) }
    }
    var out = []
    for (var k = 0; k < j.paths.length; k++) {
      var c = j.checks[k]
      var st = c.status
      if (st === "pending") {
        if (status !== "ok") st = status === "timedOut" ? "timedOut" : "missing"
        else {
          st = "ok"
          for (var a = 0; a < c.ancestors.length && st === "ok"; a++) {
            var d = info[c.ancestors[a]]
            if (!d) st = "missing"
            else if (d.type === "l") st = "symlink"
            else if (d.type !== "d") st = "missing"
          }
          if (st === "ok") {
            var f = info[j.paths[k]]
            if (!f) st = "missing"
            else if (f.type === "l") st = "symlink"
            else if (f.type !== "f") st = "notfile"
            else if (!f.readable) st = "unreadable"
          }
        }
      }
      out.push(st)
    }
    j.callback(out)
  }
}
