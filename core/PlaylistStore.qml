import QtQuick
import Quickshell

// The user's playlists, saved in $XDG_DATA_HOME/vinyl/playlists.json
// (default ~/.local/share/vinyl/playlists.json). The parsed data lives in a
// WorkerScript; this object keeps a summary and runs loads and saves one at
// a time.
//
// Storage rule: the data folder may be a symlink (dotfile setups) but must
// resolve to a folder owned by the user that others can't write to. Below
// it, vinyl/ and playlists.json must not be symlinks, must be the user's,
// and must be 0700 / 0600. A playlists.json with other permissions can be
// read but not written. Nothing is created until the first change.
//
// Before every save the file is read again; if it no longer matches what
// Vinyl last read or wrote, the change is not saved: the file is reloaded
// and the user is asked to repeat the change.
QtObject {
  id: root

  required property PrivateFiles files

  readonly property string dataHome: {
    var x = Quickshell.env("XDG_DATA_HOME") || ""
    return x.charAt(0) === "/" ? x.replace(/\/+$/, "") : (Quickshell.env("HOME") || "") + "/.local/share"
  }
  readonly property string dir: dataHome + "/vinyl"
  readonly property string file: dir + "/playlists.json"
  readonly property int maxBytes: 16 * 1024 * 1024
  readonly property string emptyText: "{\n  \"version\": 1,\n  \"playlists\": []\n}\n"

  // "idle", "loading", "ready", "readOnly" (can't save), "unreadable"
  // (damaged, too large, or from a newer Vinyl), or "location" (the storage
  // rule refuses the folder or file).
  property string state: "idle"
  property string reason: ""
  property var playlists: []          // [{ id, name, count }]
  // "changed" after a save was refused because the file changed on disk.
  property string notice: ""
  readonly property bool canEdit: state === "ready"

  // The file's text as last read or written; null when there is no file.
  property var lastKnownText: null

  // ---------------------------------------------------------------- worker
  property int seq: 0
  property var pending: ({})

  property WorkerScript worker: WorkerScript {
    source: "playlist-worker.mjs"
    onMessage: (msg) => {
      var cb = root.pending[msg.seq]
      delete root.pending[msg.seq]
      if (msg.summary) root.playlists = msg.summary
      if (cb) cb(msg)
    }
  }

  function ask(message, callback) {
    message.seq = ++seq
    pending[message.seq] = callback
    worker.sendMessage(message)
  }

  // ---------------------------------------------------------------- task queue
  property var tasks: []
  property bool busy: false

  function schedule(task) {
    tasks.push(task)
    pump()
  }

  function pump() {
    if (busy || tasks.length === 0) return
    busy = true
    var task = tasks.shift()
    task(function() {
      root.busy = false
      Qt.callLater(root.pump)
    })
  }

  // ---------------------------------------------------------------- load
  function unreadableReason(error) {
    if (error === "newer") return "It was saved by a newer version of Vinyl."
    if (error === "tooLarge") return "It is larger than 16 MB."
    return "It is damaged or not a Vinyl playlists file."
  }

  // (Re)loads the file; called whenever the library window opens.
  function load() {
    schedule(function(next) {
      if (root.state === "idle" || root.state === "location" || root.state === "failed") root.state = "loading"
      root.checkLocation(function(ok, why, fileMode) {
        if (!ok) { root.state = "location"; root.reason = why; next(); return }
        root.files.readPrivate(root.file, root.maxBytes, false, function(r) {
          if (r.state === "absent") {
            root.lastKnownText = null
            root.ask({ op: "load", text: null }, function() { root.state = "ready"; root.reason = ""; next() })
          } else if (r.state === "tooLarge") {
            root.state = "unreadable"; root.reason = root.unreadableReason("tooLarge"); next()
          } else if (r.state !== "ok") {
            root.state = r.state === "refused" ? "location" : "unreadable"
            root.reason = r.reason || "It can't be read."
            next()
          } else {
            root.ask({ op: "load", text: r.text }, function(msg) {
              if (!msg.ok) {
                root.state = "unreadable"; root.reason = root.unreadableReason(msg.error)
              } else {
                root.lastKnownText = r.text
                root.state = r.mode === "600" ? "ready" : "readOnly"
                root.reason = r.mode === "600" ? ""
                  : "Its permissions are " + r.mode + ", so Vinyl won't change it. Run chmod 600 on it to allow saving."
              }
              next()
            })
          }
        })
      })
    })
  }

  // callback(ok, reason, fileMode)
  function checkLocation(callback) {
    if (root.dataHome.charAt(0) !== "/") { callback(false, "Vinyl couldn't find your data folder."); return }
    // The data folder itself may be a symlink: resolve it.
    files.inspect([root.dataHome], function(base) {
      var b = base ? base[root.dataHome] : null
      if (!b || b.type !== "d") { callback(false, root.dataHome + " doesn't exist."); return }
      if (files.uid !== "" && b.uid !== files.uid) { callback(false, root.dataHome + " belongs to another user."); return }
      if ((parseInt(b.mode, 8) & 0o022) !== 0) { callback(false, "Others can write to " + root.dataHome + "."); return }
      files.inspect([root.dir, root.file], function(map) {
        if (!map) { callback(false, "Vinyl couldn't check " + root.dir + "."); return }
        var dp = files.dirProblem(map[root.dir])
        if (dp !== "" && dp !== "missing") { callback(false, root.dir + ": " + dp); return }
        var f = map[root.file]
        if (f && (f.type === "l" || f.type !== "f" || (files.uid !== "" && f.uid !== files.uid))) {
          callback(false, root.file + ": " + files.fileProblem(f)); return
        }
        callback(true, "", f ? f.mode : "")
      })
    }, true)
  }

  // ---------------------------------------------------------------- entries
  // callback(entries | null)
  function entries(id, callback) {
    ask({ op: "entries", id: id }, function(msg) { callback(msg.entries) })
  }

  // ---------------------------------------------------------------- edits
  // edit: { kind: create|add|remove|move|rename|delete, ... }.
  // callback({ ok, message, id, entries })
  function edit(change, callback) {
    schedule(function(next) {
      function done(result) { callback(result); next() }
      if (root.state !== "ready") {
        done({ ok: false, message: root.state === "readOnly" ? "Vinyl can't save changes to your playlists. " + root.reason
                                                              : "Your playlists can't be changed right now." })
        return
      }
      root.ask({ op: "edit", edit: change }, function(msg) {
        if (!msg.ok) { done({ ok: false, message: msg.error || "" }); return }
        root.save(msg.text, function(saved, why) {
          if (!saved) { done({ ok: false, message: why }); return }
          root.notice = ""
          done({ ok: true, message: msg.message, id: msg.id, entries: msg.entries })
        })
      })
    })
  }

  // Conflict check, then a private atomic write. On any failure the worker
  // goes back to what is on disk. callback(ok, reason)
  function save(text, callback) {
    files.readPrivate(root.file, root.maxBytes, false, function(r) {
      var disk = r.state === "absent" ? null : (r.state === "ok" ? r.text : undefined)
      if (disk === undefined || disk !== root.lastKnownText) {
        // Changed (or unreadable) since Vinyl read it: don't overwrite.
        if (disk === undefined) {
          root.state = "unreadable"
          root.reason = r.state === "tooLarge" ? root.unreadableReason("tooLarge") : (r.reason || root.unreadableReason("malformed"))
          callback(false, "Your playlists file changed outside Vinyl and can't be read now. Nothing was saved.")
          return
        }
        root.ask({ op: "revert", text: disk }, function(msg) {
          if (!msg.ok) {
            root.state = "unreadable"; root.reason = root.unreadableReason(msg.error)
          } else {
            root.lastKnownText = disk
            root.notice = "changed"
          }
          callback(false, "Your playlists changed outside Vinyl, so Vinyl reloaded them. Please repeat your change.")
        })
        return
      }
      files.ensureDir(root.dir, function(ok, why) {
        if (!ok) {
          root.ask({ op: "revert", text: root.lastKnownText }, function() {})
          root.state = "location"; root.reason = why
          callback(false, "Vinyl can't save your playlists. " + why)
          return
        }
        files.writePrivate(root.file, text, root.emptyText, function(ok2, why2) {
          if (!ok2) {
            root.ask({ op: "revert", text: root.lastKnownText }, function() {})
            callback(false, "Vinyl couldn't save your playlists. " + why2)
            return
          }
          root.lastKnownText = text
          root.ask({ op: "accept", text: text }, function() {})
          callback(true, "")
        })
      })
    })
  }

  // ---------------------------------------------------------------- start fresh
  // Only after the user confirmed. Keeps the old file as a dated backup
  // first; if that fails, nothing is reset. callback(ok, message)
  function startFresh(callback) {
    schedule(function(next) {
      function done(ok, message) { callback(ok, message); next() }
      if (root.state !== "unreadable") { done(false, ""); return }
      var backup = root.file + ".bak-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd-HHmmss")
      files.copyPrivate(root.file, backup, function(ok, why) {
        if (!ok) { done(false, "Vinyl couldn't keep a backup, so nothing was reset. " + why); return }
        files.writePrivate(root.file, root.emptyText, root.emptyText, function(ok2, why2) {
          if (!ok2) { done(false, "The backup was kept, but Vinyl couldn't start fresh. " + why2); return }
          root.lastKnownText = root.emptyText
          root.ask({ op: "load", text: root.emptyText }, function() {
            root.state = "ready"; root.reason = ""
            done(true, "Started fresh. The old file was kept as " + backup.slice(backup.lastIndexOf("/") + 1) + ".")
          })
        })
      })
    })
  }
}
