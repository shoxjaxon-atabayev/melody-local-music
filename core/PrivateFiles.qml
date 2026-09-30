import QtQuick
import Quickshell
import Quickshell.Io

// Private files for Melody's own data (the playlists file and the temporary
// queue file). Quickshell's FileView writes atomically but cannot set file
// modes and would write through a symlink, so every operation here:
//   - inspects the path first with `find -P` (never follows a symlink) and
//     refuses symlinks, other file types, files owned by someone else, and
//     files that are not mode 0600 (folders: 0700);
//   - creates a missing folder with `mkdir -m 0700` (private from creation);
//   - creates a missing file with placeholder content, makes it 0600 with
//     `chmod 0600`, and only then writes the real content (FileView keeps
//     the mode of an existing file on its atomic replace).
// mkdir and chmod run with fixed arguments and no shell. Operations run one
// at a time, in order.
QtObject {
  id: root

  property string uid: ""
  property var tasks: []
  property bool active: false

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""

  // ---------------------------------------------------------------- task queue
  function schedule(task) {
    tasks.push(task)
    pump()
  }

  function pump() {
    if (active || tasks.length === 0) return
    active = true
    var task = tasks.shift()
    task(function() {
      active = false
      Qt.callLater(root.pump)
    })
  }

  // ---------------------------------------------------------------- inspection
  // callback(map path -> { type, uid, mode, size }); missing paths are absent.
  property var statCallback: null

  property Finder finder: Finder {
    timeoutMs: 5000
    onFinished: (tag, records, status, errors) => {
      var cb = root.statCallback
      root.statCallback = null
      var map = {}
      for (var i = 0; i < records.length; i++) {
        var f = records[i].split("\t")
        if (f.length < 5) continue
        map[f.slice(4).join("\t")] = { type: f[0], uid: f[1], mode: f[2], size: Number(f[3]) }
      }
      if (cb) cb(status === "ok" ? map : null)
    }
  }

  // `follow`: resolve a symlink at the given paths themselves (find -H);
  // otherwise never follow one (find -P).
  function stat(paths, callback, follow) {
    statCallback = callback
    finder.run("stat", [follow ? "-H" : "-P"].concat(paths)
      .concat(["-maxdepth", "0", "-printf", "%y\\t%U\\t%m\\t%s\\t%p\\0"]))
  }

  function withUid(callback) {
    if (uid !== "") { callback(); return }
    if (runtimeDir === "") { callback(); return }
    stat([runtimeDir], function(map) {
      var info = map ? map[runtimeDir] : null
      // $XDG_RUNTIME_DIR is owned by the user (XDG spec).
      if (info) root.uid = info.uid
      callback()
    })
  }

  // ---------------------------------------------------------------- helper processes
  property var helperCallback: null

  property Process helper: Process {
    onExited: (code, status) => {
      var cb = root.helperCallback
      root.helperCallback = null
      if (cb) cb(code === 0)
    }
  }

  function runHelper(command, callback) {
    helperCallback = callback
    helper.command = command
    helper.running = true
  }

  // ---------------------------------------------------------------- file views
  property Component viewComponent: Component {
    FileView {
      property var done: null
      printErrors: false
      atomicWrites: true
      onSaved: if (done) done(true, "")
      onSaveFailed: (error) => { if (done) done(false, FileViewError.toString(error)) }
      onLoaded: if (done) done(true, "")
      onLoadFailed: (error) => { if (done) done(false, FileViewError.toString(error)) }
    }
  }

  // A fresh view per operation: FileView skips writing text equal to what
  // it last held, so a reused view could silently drop a write.
  function writeText(path, text, callback) {
    var view = viewComponent.createObject(root, { path: path })
    view.done = function(ok, why) {
      view.done = null
      Qt.callLater(function() { view.destroy() })
      callback(ok, why)
    }
    view.setText(text)
  }

  function writeData(path, data, callback) {
    var view = viewComponent.createObject(root, { path: path })
    view.done = function(ok, why) {
      view.done = null
      Qt.callLater(function() { view.destroy() })
      callback(ok, why)
    }
    view.setData(data)
  }

  function readFile(path, asBytes, callback) {
    var view = viewComponent.createObject(root, { path: path, blockLoading: false })
    view.done = function(ok, why) {
      view.done = null
      var result = ok ? (asBytes ? view.data() : view.text()) : null
      Qt.callLater(function() { view.destroy() })
      callback(ok, result, why)
    }
    view.reload()
  }

  // ---------------------------------------------------------------- checks
  function dirProblem(info) {
    if (!info) return "missing"
    if (info.type === "l") return "It is a symbolic link."
    if (info.type !== "d") return "It is not a folder."
    if (uid !== "" && info.uid !== uid) return "It belongs to another user."
    if (info.mode !== "700") return "Its permissions are " + info.mode + ", not 700."
    return ""
  }

  function fileProblem(info) {
    if (!info) return "missing"
    if (info.type === "l") return "It is a symbolic link."
    if (info.type !== "f") return "It is not a regular file."
    if (uid !== "" && info.uid !== uid) return "It belongs to another user."
    if (info.mode !== "600") return "Its permissions are " + info.mode + ", not 600."
    return ""
  }

  // ---------------------------------------------------------------- public API
  // callback(ok, reason). Creates `dir` (0700) if missing; refuses anything
  // that is not a private, real folder owned by the user.
  function ensureDir(dir, callback) {
    schedule(function(next) {
      root.withUid(function() {
        root.stat([dir], function(map) {
          if (!map) { callback(false, "Couldn't check " + dir + "."); next(); return }
          var problem = root.dirProblem(map[dir])
          if (problem === "") { callback(true, ""); next(); return }
          if (problem !== "missing") { callback(false, dir + ": " + problem); next(); return }
          root.runHelper(["/usr/bin/mkdir", "-m", "0700", "--", dir], function() {
            root.stat([dir], function(map2) {
              var p2 = map2 ? root.dirProblem(map2[dir]) : "missing"
              callback(p2 === "", p2 === "" ? "" : "Couldn't create " + dir + ".")
              next()
            })
          })
        })
      })
    })
  }

  // callback(ok, reason). Writes `text` to `path` (inside a folder already
  // checked by ensureDir), creating the file private if needed.
  function writePrivate(path, text, placeholder, callback) {
    schedule(function(next) {
      root.withUid(function() {
        root.stat([path], function(map) {
          if (!map) { callback(false, "Couldn't check " + path + "."); next(); return }
          var problem = root.fileProblem(map[path])
          if (problem !== "" && problem !== "missing") {
            callback(false, path + ": " + problem); next(); return
          }
          function writeReal() {
            root.writeText(path, text, function(ok, why) {
              callback(ok, ok ? "" : "Couldn't save " + path + " (" + why + ").")
              next()
            })
          }
          if (problem === "") { writeReal(); return }
          // New file: placeholder first, then 0600, then the real content.
          root.writeText(path, placeholder, function(ok, why) {
            if (!ok) { callback(false, "Couldn't create " + path + " (" + why + ")."); next(); return }
            root.runHelper(["/usr/bin/chmod", "0600", "--", path], function() {
              root.stat([path], function(map2) {
                var p2 = map2 ? root.fileProblem(map2[path]) : "missing"
                if (p2 !== "") { callback(false, path + ": " + p2); next(); return }
                writeReal()
              })
            })
          })
        })
      })
    })
  }

  // callback(result) with result.state: "absent", "ok" (result.text or
  // result.data), "tooLarge", "refused" (result.reason), or "failed".
  function readPrivate(path, maxBytes, asBytes, callback) {
    schedule(function(next) {
      root.withUid(function() {
        root.stat([path], function(map) {
          if (!map) { callback({ state: "failed", reason: "Couldn't check " + path + "." }); next(); return }
          var info = map[path]
          if (!info) { callback({ state: "absent" }); next(); return }
          if (info.type === "l" || info.type !== "f" || (root.uid !== "" && info.uid !== root.uid)) {
            callback({ state: "refused", reason: root.fileProblem(info) }); next(); return
          }
          if (maxBytes > 0 && info.size > maxBytes) {
            callback({ state: "tooLarge", size: info.size, mode: info.mode }); next(); return
          }
          root.readFile(path, asBytes, function(ok, result, why) {
            if (!ok) callback({ state: "failed", reason: why, mode: info.mode })
            else callback({ state: "ok", text: asBytes ? null : result, data: asBytes ? result : null,
                            mode: info.mode, size: info.size })
            next()
          })
        })
      })
    })
  }

  // callback(map) — info for several paths (see stat()); `follow` resolves
  // a symlink at the paths themselves.
  function inspect(paths, callback, follow) {
    schedule(function(next) {
      root.withUid(function() {
        root.stat(paths, function(map) { callback(map); next() }, follow)
      })
    })
  }

  // Copy `from` to a new private file `to` (never replacing one), byte for
  // byte. callback(ok, reason).
  function copyPrivate(from, to, callback) {
    readPrivate(from, 0, true, function(result) {
      if (result.state !== "ok") { callback(false, "Couldn't read " + from + "."); return }
      root.schedule(function(next) {
        root.stat([to], function(map) {
          if (!map || map[to]) { callback(false, to + " already exists."); next(); return }
          root.writeText(to, "\n", function(ok) {
            if (!ok) { callback(false, "Couldn't create " + to + "."); next(); return }
            root.runHelper(["/usr/bin/chmod", "0600", "--", to], function() {
              root.stat([to], function(map2) {
                var p2 = map2 ? root.fileProblem(map2[to]) : "missing"
                if (p2 !== "") { callback(false, to + ": " + p2); next(); return }
                root.writeData(to, result.data, function(ok2, why) {
                  callback(ok2, ok2 ? "" : "Couldn't write " + to + " (" + why + ").")
                  next()
                })
              })
            })
          })
        })
      })
    })
  }
}
