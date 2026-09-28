import QtQuick
import "Paths.js" as Paths

// Reads folders for the Music Library with short-lived `find` processes
// (PLAN §2.5): only the chosen folder and its subfolders, symlinks never
// followed or shown, hidden entries skipped, only readable audio files by
// extension, and resource limits. Listing: 5,000 entries, 5 s. Search
// index: depth 8, 20,000 files, 10 s, collected once per window session.
QtObject {
  id: root

  readonly property int maxEntries: 5000
  readonly property int maxSearchFiles: 20000

  property var listCallback: null
  property var searchCallback: null

  property Finder lister: Finder {
    timeoutMs: 5000
    onFinished: (tag, records, status, errors) => {
      var cb = root.listCallback
      root.listCallback = null
      if (cb) cb(root.parseListing(tag, records, status, errors))
    }
  }

  property Finder searcher: Finder {
    timeoutMs: 10000
    onFinished: (tag, records, status, errors) => {
      var cb = root.searchCallback
      root.searchCallback = null
      if (!cb) return
      var files = []
      var truncated = false
      for (var i = 0; i < records.length; i++) {
        if (!Paths.isAudioName(records[i])) continue
        if (files.length >= root.maxSearchFiles) { truncated = true; break }
        files.push(records[i])
      }
      cb({ status: status, files: files, truncated: truncated })
    }
  }

  // callback({ status, folders:[name], files:[name], total, truncated })
  // status: "ok", "missing", "permission", "notFolder", "timedOut", "failed".
  // mode "library": folders and audio files. "chooser": folders only,
  // including symlinked folders (a library folder may itself be a link).
  function list(dir, mode, callback) {
    listCallback = callback
    lister.run(mode, ["-H", dir, "-mindepth", "0", "-maxdepth", "1",
                      "(", "-readable", "-printf", "r", "-o", "-printf", "-", ")",
                      "-printf", "%d\\t%y\\t%Y\\t%f\\0"])
  }

  function cancel() {
    listCallback = null
    lister.cancel()
    searchCallback = null
    searcher.cancel()
  }

  function parseListing(mode, records, status, errors) {
    var out = { status: "ok", folders: [], files: [], total: 0, truncated: false }
    if (status === "timedOut") { out.status = "timedOut"; return out }
    var self = null
    for (var i = 0; i < records.length; i++) {
      var r = records[i]
      var f = r.slice(1).split("\t")
      if (f.length < 4) continue
      var rec = { readable: r.charAt(0) === "r", depth: f[0], type: f[1], target: f[2], name: f.slice(3).join("\t") }
      if (rec.depth === "0") { self = rec; continue }
      if (Paths.isHiddenName(rec.name)) continue
      if (mode === "chooser") {
        if (rec.type === "d" || (rec.type === "l" && rec.target === "d")) out.folders.push(rec.name)
        continue
      }
      if (rec.type === "d") out.folders.push(rec.name)
      else if (rec.type === "f" && rec.readable && Paths.isAudioName(rec.name)) out.files.push(rec.name)
    }
    if (!self) {
      out.status = /Permission denied/.test(errors) ? "permission" : "missing"
      return out
    }
    if (self.type !== "d") { out.status = "notFolder"; return out }
    if (!self.readable || /Permission denied/.test(errors) && records.length <= 1) { out.status = "permission"; return out }
    if (status === "failed" && records.length <= 1) { out.status = "failed"; return out }
    out.folders.sort(Paths.naturalCompare)
    out.files.sort(Paths.naturalCompare)
    out.total = out.folders.length + out.files.length
    if (out.total > root.maxEntries) {
      out.truncated = true
      if (out.folders.length >= root.maxEntries) {
        out.folders = out.folders.slice(0, root.maxEntries)
        out.files = []
      } else {
        out.files = out.files.slice(0, root.maxEntries - out.folders.length)
      }
    }
    return out
  }

  // callback({ status, files:[relative path], truncated })
  function collect(libraryRoot, callback) {
    searchCallback = callback
    searcher.run("search", ["-H", libraryRoot, "-mindepth", "1", "-maxdepth", "8",
                            "(", "-name", ".*", "-prune", ")", "-o",
                            "(", "-type", "f", "-readable", "-printf", "%P\\0", ")"])
  }
}
