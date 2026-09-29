import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "components"
import "library"
import "core"
import "core/Paths.js" as Paths

// Vinyl's Music Library window. A large card in Omarchy's panel conventions:
// the panels' layer namespace (no compositor animation), the theme's popup
// surface, border, and radius, Omarchy's fonts, spacing, controls, and
// system glyphs, a 140 ms fade, a brief keyboard-focus prime, and closing
// on Escape, the close button, or a click outside. Centered on the screen.
//
// Left: the library folder and the user's playlists. Right: the whole
// library as one list — every song in the chosen folder and its subfolders,
// in blocks headed by each folder's path — or a playlist, search results,
// or the folder chooser. Clicking a song plays it in Vinyl's own player,
// with the rest of the list queued after it; controls stay in the
// mini-player.
//
// Keys: ↑/↓ move, Enter plays (or opens a folder in the chooser),
// Backspace goes up a folder in the chooser, "/" searches, Space selects,
// Shift+↑/↓ extends the selection, Ctrl+A selects all, Alt+↑/↓ moves a track
// within a playlist, Delete removes it from the playlist, Escape closes a
// menu, clears the selection or the search, then closes the window.
PanelWindow {
  id: win

  required property var service
  property bool open: false

  signal closeRequested()

  readonly property Theme theme: Theme {}
  readonly property var store: service.store
  readonly property string libraryRoot: service.libraryRoot
  readonly property string home: Quickshell.env("HOME") || "/"

  // ---------------------------------------------------------------- view state
  property string section: "library"        // "library", "playlist", or "chooser"
  // Every song in the library: { root, groups: [{ folder, names }], files
  // (relative paths, in list order), truncated, status }. Kept while the
  // window is closed and refreshed on every open.
  property var libraryIndex: null
  property string indexStatus: "idle"       // "idle", "loading", "ready", or the scan's error
  property string chooserDir: ""
  property var chooserListing: null
  property string chooserStatus: "idle"
  property string query: ""
  property string playlistId: ""
  property var playlistEntries: []
  property var entryStatus: ({})            // path -> status
  property int cursorIndex: -1
  property int anchorIndex: -1
  property var selection: ({})              // path -> true
  property string naming: ""                // "", "sidebar", or "rename"
  property string nameError: ""
  property bool menuOpen: false
  property var menuTracks: []
  property string confirmKind: ""           // "", "delete", or "fresh"
  property string toast: ""
  property bool settingsOpen: false

  readonly property bool chooser: section === "chooser"
  readonly property bool searching: query.trim() !== "" && !chooser
  readonly property bool inPlaylist: section === "playlist" && !searching
  readonly property bool canEdit: store.canEdit
  readonly property int selectionCount: Object.keys(selection).length
  readonly property var currentPlaylist: {
    var list = store.playlists
    for (var i = 0; i < list.length; i++) if (list[i].id === playlistId) return list[i]
    return null
  }
  readonly property bool playlistEmpty: inPlaylist && currentPlaylist !== null && currentPlaylist.count === 0
  readonly property int trackCount: libraryIndex ? libraryIndex.files.length : 0

  // Full-card states instead of the list.
  readonly property string hero: {
    if (chooser) {
      if (chooserStatus === "loading" && !chooserListing) return "loading"
      if (chooserStatus === "missing" || chooserStatus === "notFolder") return "chooserMissing"
      if (chooserStatus === "permission") return "chooserPermission"
      if (chooserStatus === "timedOut") return "chooserTimedOut"
      return ""
    }
    if (libraryRoot === "") return "noFolder"
    if (inPlaylist) return playlistEmpty ? "emptyPlaylist" : ""
    if (!libraryIndex) {
      if (indexStatus === "missing" || indexStatus === "notFolder") return "missing"
      if (indexStatus === "permission") return "permission"
      if (indexStatus === "timedOut") return "timedOut"
      if (indexStatus === "failed") return "failed"
      return "loading"
    }
    if (libraryIndex.files.length === 0) return libraryIndex.status === "timedOut" ? "timedOut" : libraryIndex.status === "failed" ? "failed" : "emptyLibrary"
    return ""
  }

  // ---------------------------------------------------------------- rows
  function sectionHeader(label, count) { return { kind: "header", label: label, count: count } }

  // Headers and folder blocks' headings: part of the list, never a target.
  function isStatic(row) { return !row || row.kind === "header" || row.kind === "group" }

  function trackRow(path, number, location) {
    var name = Paths.baseName(path)
    return { kind: "track", path: path, name: Paths.displayName(name), title: Paths.trackTitle(name),
             ext: Paths.extension(name), number: number, location: location || "" }
  }

  function locationOf(path) {
    var rel = Paths.relativeTo(libraryRoot, Paths.dirName(path))
    if (rel === null) return Paths.dirName(path) === libraryRoot ? "" : Paths.displayName(Paths.dirName(path))
    return Paths.displayName(rel.split("/").join(" › "))
  }

  // A path for people: the home folder as "~".
  function shortPath(path) {
    var p = String(path)
    if (home !== "/" && (p === home || p.indexOf(home + "/") === 0)) p = "~" + p.slice(home.length)
    return Paths.displayName(p)
  }

  function thousands(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",") }

  // The whole library, built once per scan: a heading per folder (its path
  // below the library folder), then that folder's songs.
  readonly property var libraryRows: {
    var out = []
    if (!libraryIndex) return out
    var groups = libraryIndex.groups
    for (var g = 0; g < groups.length; g++) {
      var folder = groups[g].folder
      var names = groups[g].names
      out.push({ kind: "group", folder: folder, count: names.length,
                 label: folder === "" ? Paths.displayName(Paths.baseName(libraryIndex.root) || "/")
                                      : Paths.displayName(folder.split("/").join(" / ")) })
      var dir = folder === "" ? libraryIndex.root : Paths.join(libraryIndex.root, folder)
      for (var n = 0; n < names.length; n++)
        out.push(trackRow(Paths.join(dir, names[n]), Paths.trackNumber(names[n]), ""))
    }
    return out
  }

  readonly property var rows: {
    if (hero !== "") return []
    var out = []
    if (chooser) {
      var folders = chooserListing ? chooserListing.folders : []
      if (folders.length) out.push(sectionHeader("Folders", folders.length))
      for (var c = 0; c < folders.length; c++)
        out.push({ kind: "folder", name: Paths.displayName(folders[c]), path: Paths.join(chooserDir, folders[c]) })
      return out
    }
    if (searching) {
      var files = libraryIndex ? libraryIndex.files : []
      var q = query.trim().toLowerCase()
      var matches = []
      for (var s = 0; s < files.length; s++) if (files[s].toLowerCase().indexOf(q) !== -1) matches.push(files[s])
      out.push(sectionHeader("Results", matches.length))
      for (var m = 0; m < matches.length && m < 500; m++) {
        var p = Paths.join(libraryIndex.root, matches[m])
        out.push(trackRow(p, Paths.trackNumber(Paths.baseName(p)), locationOf(p)))
      }
      return out
    }
    if (inPlaylist) {
      var entries = playlistEntries
      out.push(sectionHeader("Tracks", entries.length))
      for (var e = 0; e < entries.length; e++) {
        var row = trackRow(entries[e], e + 1, locationOf(entries[e]))
        var st = entryStatus[entries[e]]
        if (st !== undefined && st !== "ok") {
          row.unavailable = true
          row.statusLabel = st === "outside" ? "Not in this library" : st === "timedOut" ? "Not checked" : "Missing"
        }
        row.entry = e
        out.push(row)
      }
      return out
    }
    return libraryRows
  }

  readonly property int resultCount: searching && rows.length ? rows[0].count : 0

  function trackRows() {
    return rows.filter(function(r) { return r.kind === "track" })
  }

  // A playlist shows its playing row only while that playlist is playing;
  // the library and search results show the playing file wherever it appears.
  function isPlayingRow(row) {
    if (row.kind !== "track" || row.path !== service.playingPath || row.path === "") return false
    if (!inPlaylist) return true
    var q = service.queue
    return !!q && q.source.kind === "playlist" && q.source.id === playlistId
  }

  // ---------------------------------------------------------------- data sources
  property FolderSource source: FolderSource {}
  property PathValidator validator: PathValidator {}

  // Lists every song in the library folder: the folder itself is checked
  // first, then collected (subfolders included; limits in FolderSource).
  // The previous list stays on screen until the new one is in.
  function scanLibrary() {
    if (libraryRoot === "") return
    var rootAtStart = libraryRoot
    if (libraryIndex && libraryIndex.root !== rootAtStart) libraryIndex = null
    indexStatus = "loading"
    source.list(rootAtStart, "library", function(result) {
      if (win.libraryRoot !== rootAtStart) return
      if (result.status !== "ok") {
        win.libraryIndex = null
        win.indexStatus = result.status
        // What the library folder holds also tells the bar whether to offer
        // setup ("Set up music library").
        win.service.libraryStatus = result.status
        return
      }
      win.source.collect(rootAtStart, function(found) {
        if (win.libraryRoot !== rootAtStart) return
        // Unchanged since the last open: keep the list as it is (no rebuild).
        if (!win.sameScan(win.libraryIndex, rootAtStart, found)) win.libraryIndex = win.buildIndex(rootAtStart, found)
        win.indexStatus = found.status === "ok" ? "ready" : found.status
        win.service.libraryStatus = win.libraryIndex.files.length ? "ok" : found.status === "ok" ? "empty" : found.status
      })
    })
  }

  function sameScan(current, rootPath, found) {
    if (!current || current.root !== rootPath || current.status !== found.status || current.truncated !== found.truncated) return false
    var a = current.found, b = found.files
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }

  // Songs grouped by folder: the library folder's own songs first, then
  // each folder in natural order, its songs in natural order.
  function buildIndex(rootPath, found) {
    var byFolder = {}
    var folders = []
    for (var i = 0; i < found.files.length; i++) {
      var rel = found.files[i]
      var slash = rel.lastIndexOf("/")
      var folder = slash > 0 ? rel.slice(0, slash) : ""
      if (!byFolder.hasOwnProperty(folder)) { byFolder[folder] = []; folders.push(folder) }
      byFolder[folder].push(rel.slice(slash + 1))
    }
    folders.sort(function(a, b) {
      if (a === "" || b === "") return a === b ? 0 : a === "" ? -1 : 1
      return Paths.naturalCompare(a, b)
    })
    var groups = [], files = []
    for (var f = 0; f < folders.length; f++) {
      var names = byFolder[folders[f]].sort(Paths.naturalCompare)
      groups.push({ folder: folders[f], names: names })
      for (var n = 0; n < names.length; n++) files.push(folders[f] === "" ? names[n] : folders[f] + "/" + names[n])
    }
    return { root: rootPath, groups: groups, files: files, truncated: found.truncated, status: found.status, found: found.files }
  }

  function listChooser(path) {
    chooserDir = path
    chooserStatus = "loading"
    source.list(path, "chooser", function(result) {
      if (win.chooserDir !== path) return
      win.chooserListing = result.status === "ok" ? result : null
      win.chooserStatus = result.status
    })
  }

  function refreshEntries(entries) {
    if (entries === null || entries === undefined) return
    playlistEntries = entries
    var id = playlistId
    validator.validate(libraryRoot, entries, function(statuses) {
      if (win.playlistId !== id) return
      var map = {}
      for (var i = 0; i < entries.length; i++) map[entries[i]] = statuses[i]
      win.entryStatus = map
    })
  }

  function loadPlaylist(id) {
    store.entries(id, function(entries) {
      if (win.playlistId !== id) return
      win.refreshEntries(entries || [])
    })
  }

  // ---------------------------------------------------------------- open / close
  onOpenChanged: {
    focusPrimeTimer.stop()
    focusPrimed = false
    if (open) {
      resetSession()
      beginFocusPrime()
      list.forceActiveFocus()
    } else {
      menuOpen = false
      settingsOpen = false
      confirmKind = ""
      naming = ""
      // Nothing keeps running while the window is closed.
      source.cancel()
      validator.cancel()
      if (indexStatus === "loading") indexStatus = libraryIndex ? "ready" : "idle"
    }
  }

  function resetSession() {
    section = "library"
    query = ""
    playlistId = ""
    playlistEntries = []
    entryStatus = ({})
    resetCursor()
    scanLibrary()
  }

  onLibraryRootChanged: {
    libraryIndex = null
    indexStatus = "idle"
    if (open) resetSession()
  }

  // ---------------------------------------------------------------- navigation
  function resetCursor() {
    cursorIndex = -1
    anchorIndex = -1
    selection = ({})
  }

  function openLibrary() {
    section = "library"
    query = ""
    naming = ""
    store.notice = ""
    resetCursor()
    if (libraryRoot !== "" && !libraryIndex && indexStatus !== "loading") scanLibrary()
  }

  function openPlaylist(id) {
    section = "playlist"
    playlistId = id
    query = ""
    naming = ""
    store.notice = ""
    playlistEntries = []
    entryStatus = ({})
    resetCursor()
    loadPlaylist(id)
  }

  function openChooser() {
    section = "chooser"
    query = ""
    naming = ""
    resetCursor()
    chooserListing = null
    listChooser(libraryRoot !== "" ? libraryRoot : home)
  }

  function useChooserFolder() {
    if (!service.setLibraryRoot(chooserDir)) return
    section = "library"
    resetSession()
  }

  // Called from a breadcrumb, which the path change destroys: keep the work
  // here, in the window's scope, not in the button's handler.
  function openCrumb(path) {
    resetCursor()
    listChooser(path)
  }

  readonly property var crumbs: {
    var out = []
    if (!chooser) return out
    var segs = chooserDir === "/" ? [] : chooserDir.split("/").slice(1)
    out.push({ label: "/", path: "/" })
    for (var i = 0; i < segs.length; i++)
      out.push({ label: Paths.displayName(segs[i]), path: "/" + segs.slice(0, i + 1).join("/") })
    return out
  }

  // What the list on screen is, as the queue's source.
  function currentSource() {
    if (searching) return { kind: "search", id: "", name: "Search results" }
    if (inPlaylist) return { kind: "playlist", id: playlistId, name: currentPlaylist ? currentPlaylist.name : "Playlist" }
    return { kind: "library", id: libraryRoot, name: Paths.baseName(libraryRoot) || "Music" }
  }

  function activate(row) {
    if (isStatic(row)) return
    if (row.kind === "folder") {
      resetCursor()
      listChooser(row.path)
      return
    }
    if (row.unavailable) {
      showToast("“" + row.title + "” can't be played (" + (row.statusLabel || "missing").toLowerCase() + ").")
      return
    }
    var src = currentSource()
    // The song already playing from this same list: keep it going (a
    // second click, or Enter again, never restarts it).
    var q = service.queue
    if (service.usingEngine && service.playingPath === row.path && q && q.source
        && q.source.kind === src.kind && q.source.id === src.id) {
      if (!service.isPlaying && !service.engine.loading && !service.queueStarting) service.togglePlaying()
      return
    }
    if (service.queueStarting) return
    // The library and search results: the whole list, from this song on
    // (previous goes back up the list), ending after the last one. A
    // playlist: only its tracks, from this one to the end, then from the
    // beginning up to the one before it.
    var tracks = trackRows()
    var start = 0
    for (var i = 0; i < tracks.length; i++) {
      if (tracks[i].path === row.path && (row.entry === undefined || tracks[i].entry === row.entry)) { start = i; break }
    }
    var ordered = inPlaylist ? tracks.slice(start).concat(tracks.slice(0, start)) : tracks
    var at = inPlaylist ? 0 : start
    var paths = [], first = 0
    for (var k = 0; k < ordered.length; k++) {
      if (ordered[k].unavailable) continue
      if (k === at) first = paths.length
      paths.push(ordered[k].path)
    }
    var limit = service.engine.maxQueue
    if (paths.length > limit) {
      paths = paths.slice(first, first + limit)
      first = 0
      showToast("Playing 1,000 tracks from here (the queue limit).")
    }
    service.playFromLibrary(paths, first, src)
  }

  function playFirst() {
    var tracks = trackRows().filter(function(t) { return !t.unavailable })
    if (tracks.length) activate(tracks[0])
  }

  function moveCursor(delta, extend) {
    var i = cursorIndex
    for (var step = 0; step < rows.length; step++) {
      i = Math.max(0, Math.min(rows.length - 1, i + delta))
      if (!isStatic(rows[i])) break
    }
    if (isStatic(rows[i])) return
    if (extend && rows[i].kind === "track" && canEdit) {
      if (anchorIndex < 0) anchorIndex = cursorIndex >= 0 ? cursorIndex : i
      setSelection(rangeKeys(anchorIndex, i))
    } else if (!extend) {
      anchorIndex = i
    }
    cursorIndex = i
    list.positionViewAtIndex(i, ListView.Contain)
  }

  // ---------------------------------------------------------------- selection
  // Selection only serves playlist edits, so it needs a writable store.
  function setSelection(keys) {
    var s = {}
    for (var i = 0; i < keys.length; i++) s[keys[i]] = true
    selection = s
  }

  function rangeKeys(a, b) {
    var out = []
    for (var i = Math.min(a, b); i <= Math.max(a, b); i++)
      if (rows[i] && rows[i].kind === "track") out.push(rows[i].path)
    return out
  }

  function toggleSelected(row) {
    var s = Object.assign({}, selection)
    if (s[row.path]) delete s[row.path]
    else s[row.path] = true
    selection = s
  }

  // Click: plain (which also plays the song) puts the cursor on a track and
  // clears the selection; Ctrl toggles a track, without playing it; Shift
  // selects a range.
  function pick(index, modifiers) {
    var row = rows[index]
    if (!row || row.kind !== "track") return
    if (!canEdit || chooser) modifiers = Qt.NoModifier
    if (modifiers & Qt.ControlModifier) {
      toggleSelected(row)
      anchorIndex = index
    } else if ((modifiers & Qt.ShiftModifier) && anchorIndex >= 0) {
      setSelection(rangeKeys(anchorIndex, index))
    } else {
      anchorIndex = index
      if (selectionCount) selection = ({})
    }
    cursorIndex = index
  }

  function selectAll() {
    if (canEdit && !chooser) setSelection(trackRows().map(function(r) { return r.path }))
  }

  function selectedPaths() {
    return trackRows().filter(function(r) { return selection[r.path] }).map(function(r) { return r.path })
  }

  // ---------------------------------------------------------------- playlist edits
  function edit(change, after) {
    store.edit(change, function(result) {
      if (result.message) win.showToast(result.message)
      if (result.ok && result.id === win.playlistId && result.entries) win.refreshEntries(result.entries)
      if (!result.ok && win.store.notice === "changed" && win.inPlaylist) win.loadPlaylist(win.playlistId)
      if (after) after(result)
    })
  }

  function addPaths(id, paths) {
    edit({ kind: "add", id: id, paths: paths }, function(result) {
      if (result.ok) win.selection = ({})
    })
  }

  function removePaths(paths) {
    if (!inPlaylist || paths.length === 0) return
    var id = playlistId
    edit({ kind: "remove", id: id, paths: paths }, function(result) {
      if (result.ok) win.resetCursor()
    })
  }

  function removeSelectedOrCursor() {
    if (selectionCount) removePaths(Object.keys(selection))
    else if (rows[cursorIndex] && rows[cursorIndex].kind === "track") removePaths([rows[cursorIndex].path])
  }

  // Alt+↑/↓: move the cursor's track; the cursor follows it.
  function moveEntry(delta) {
    var row = rows[cursorIndex]
    if (!inPlaylist || !canEdit || !row || row.kind !== "track") return
    var target = cursorIndex + delta
    if (!rows[target] || rows[target].kind !== "track") return
    edit({ kind: "move", id: playlistId, index: row.entry, delta: delta }, function(result) {
      if (!result.ok) return
      win.cursorIndex = target
      win.anchorIndex = target
      list.positionViewAtIndex(target, ListView.Contain)
    })
  }

  function startSidebarNaming() {
    if (!canEdit) return
    menuOpen = false
    naming = "sidebar"
    nameError = ""
    sideNameField.text = ""
    sideNameField.forceActiveFocus()
  }

  function commitSidebarName(text) {
    edit({ kind: "create", name: text }, function(result) {
      if (!result.ok) { win.nameError = result.message; return }
      win.naming = ""
      win.openPlaylist(result.id)
      list.forceActiveFocus()
    })
  }

  function startRename() {
    if (!currentPlaylist || !canEdit) return
    naming = "rename"
    nameError = ""
    renameField.text = currentPlaylist.name
    renameField.forceActiveFocus()
    renameField.selectAll()
  }

  function commitRename(text) {
    edit({ kind: "rename", id: playlistId, name: text }, function(result) {
      if (!result.ok) { win.nameError = result.message; return }
      win.naming = ""
      list.forceActiveFocus()
    })
  }

  function cancelNaming() {
    naming = ""
    nameError = ""
    list.forceActiveFocus()
  }

  function deletePlaylist() {
    confirmKind = ""
    var id = playlistId
    edit({ kind: "delete", id: id }, function(result) {
      if (result.ok) win.openLibrary()
      list.forceActiveFocus()
    })
  }

  function startFresh() {
    confirmKind = ""
    store.startFresh(function(ok, message) {
      if (message) win.showToast(message)
      list.forceActiveFocus()
    })
  }

  // The menu opens below `item` (or above it, near the bottom), right-aligned.
  function openMenu(paths, item) {
    if (paths.length === 0 || !canEdit) return
    menuTracks = paths
    var p = item.mapToItem(body, item.width, 0)
    menu.anchorRight = Math.min(body.width, p.x)
    menu.anchorTop = p.y + item.height + Style.spacing.xxs
    menu.anchorAbove = p.y - Style.spacing.xxs
    menuOpen = true
  }

  function openSettings() {
    menuOpen = false
    var p = settingsButton.mapToItem(body, settingsButton.width, 0)
    settings.anchorRight = Math.min(body.width, p.x)
    settings.anchorTop = p.y + settingsButton.height + Style.spacing.xxs
    settingsOpen = true
  }

  function closeSettings() {
    settingsOpen = false
    list.forceActiveFocus()
  }

  function rowAction(index, item) {
    var row = rows[index]
    if (!row || row.kind !== "track" || !canEdit) return
    if (inPlaylist) removePaths([row.path])
    else openMenu([row.path], item)
  }

  function showToast(text) {
    toast = text
    toastTimer.restart()
  }

  Timer {
    id: toastTimer
    interval: 3200
    onTriggered: win.toast = ""
  }

  // ---------------------------------------------------------------- notices
  // One notice at a time. What the user can't see otherwise comes first.
  readonly property string noticeKind: {
    if (chooser) return ""
    if (service.engine.mpvMissing) return "noPlayer"
    if (service.playbackError !== "") return "openFailed"
    if (store.notice === "changed") return "storeChanged"
    if (!inPlaylist && libraryIndex && libraryIndex.files.length > 0
        && (libraryIndex.truncated || libraryIndex.status === "timedOut")) return "limit"
    return ""
  }

  // ---------------------------------------------------------------- window
  // Centered on the screen it was opened on (no anchors); the bar's
  // reserved space is respected, so it never overlaps the bar.
  screen: {
    var name = service.libraryScreen
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    return Quickshell.screens.length ? Quickshell.screens[0] : null
  }
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  implicitWidth: card.width
  implicitHeight: card.height
  color: "transparent"
  visible: open || card.opacity > 0

  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay

  // Omarchy panel focus (KeyboardPanel): Exclusive for a moment once the
  // surface is mapped, then OnDemand; released the moment it closes.
  property bool focusPrimed: false
  WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None
    : focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }
  onBackingWindowVisibleChanged: beginFocusPrime()

  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (win.open) win.focusPrimed = true
  }

  // Outside-click dismissal, as in Vinyl's popover (Omarchy's KeyboardPanel
  // behavior): while open, every monitor gets a transparent, non-focusable
  // surface under the window that closes it on any click. It also keeps the
  // pointer over Vinyl's surfaces, so Hyprland doesn't hand keyboard focus
  // to the app underneath once the focus prime ends. The bar strip is cut
  // out so the bar keeps receiving its clicks.
  readonly property string barPosition: {
    var config = service.shell && service.shell.barConfig ? service.shell.barConfig : null
    var p = config && config.position ? String(config.position) : "top"
    return p === "bottom" || p === "left" || p === "right" ? p : "top"
  }
  readonly property bool horizontalBar: barPosition === "top" || barPosition === "bottom"
  readonly property int barThickness: horizontalBar ? Style.bar.sizeHorizontal : Style.bar.sizeVertical

  Variants {
    model: win.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: dismiss

        required property var modelData

        screen: modelData
        visible: win.open
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        WlrLayershell.namespace: "vinyl-library-dismiss"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {
          width: dismiss.width
          height: dismiss.height

          Region {
            intersection: Intersection.Subtract
            x: win.barPosition === "right" ? dismiss.width - win.barThickness : 0
            y: win.barPosition === "bottom" ? dismiss.height - win.barThickness : 0
            width: win.horizontalBar ? dismiss.width : win.barThickness
            height: win.horizontalBar ? win.barThickness : dismiss.height
          }
        }

        MouseArea {
          objectName: "dismissArea"
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: win.closeRequested()
        }
      }
    }
  }

  GlassSurface {
    id: card
    objectName: "card"
    theme: win.theme
    width: theme.px(820)
    height: theme.px(560)
    padding: theme.cardPadding
    // Omarchy's card transition: a 140 ms OutCubic fade on open and close.
    opacity: win.open ? 1 : 0

    Behavior on opacity {
      NumberAnimation { duration: theme.durPanel; easing.type: Easing.OutCubic }
    }

    FocusScope {
      id: body
      x: card.insetLeft
      y: card.insetTop
      width: card.width - card.insetLeft - card.insetRight
      height: card.height - card.insetTop - card.insetBottom
      focus: true
      enabled: win.open                    // no input during the fade-out

      Keys.onPressed: (event) => {
        if (confirm.handleKey(event) || menu.handleKey(event) || settings.handleKey(event)) {
          event.accepted = true
          return
        }
        var ctrl = event.modifiers & Qt.ControlModifier
        var shift = event.modifiers & Qt.ShiftModifier
        var alt = event.modifiers & Qt.AltModifier
        var typing = search.activeFocus
        if (event.key === Qt.Key_Escape) {
          if (win.naming !== "") win.cancelNaming()
          else if (win.selectionCount) win.selection = ({})
          else if (win.query !== "") { win.query = ""; win.resetCursor(); list.forceActiveFocus() }
          else win.closeRequested()
        } else if (win.naming !== "") {
          return
        } else if (event.key === Qt.Key_Slash && !typing && !win.chooser) {
          search.forceActiveFocus()
        } else if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && alt) {
          win.moveEntry(event.key === Qt.Key_Down ? 1 : -1)
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
          list.forceActiveFocus()
          win.moveCursor(event.key === Qt.Key_Down ? 1 : -1, shift)
        } else if (event.key === Qt.Key_Space && !typing) {
          var row = win.rows[win.cursorIndex]
          if (row && row.kind === "track" && win.canEdit && !win.chooser) {
            win.toggleSelected(row)
            win.anchorIndex = win.cursorIndex
          }
        } else if (event.key === Qt.Key_A && ctrl && !typing) {
          win.selectAll()
        } else if (event.key === Qt.Key_Delete && !typing && win.inPlaylist && win.canEdit) {
          win.removeSelectedOrCursor()
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !typing) {
          win.activate(win.rows[win.cursorIndex])
        } else if (event.key === Qt.Key_Backspace && !typing && win.chooser) {
          if (win.chooserDir !== "/") win.openCrumb(Paths.dirName(win.chooserDir))
        } else {
          return
        }
        event.accepted = true
      }

      // ------------------------------------------------------------ header
      Item {
        id: header
        width: parent.width
        height: Style.spacing.controlHeight

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: theme.px(8)

          VinylMark {
            theme: win.theme
            anchors.verticalCenter: parent.verticalCenter
            size: theme.px(18)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Vinyl"
            textFormat: Text.PlainText
            color: theme.textPrimary
            font.family: theme.fontFamily
            font.pixelSize: theme.fontLabel
            font.bold: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: win.chooser ? "Choose folder" : "Library"
            textFormat: Text.PlainText
            color: theme.textMuted
            font.family: theme.fontFamily
            font.pixelSize: theme.fontBody
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: -theme.px(4)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.lg

          TextField {
            id: search
            objectName: "search"
            anchors.verticalCenter: parent.verticalCenter
            width: theme.px(260)
            visible: !win.chooser && win.libraryRoot !== ""
            foreground: theme.textPrimary
            placeholderText: "Search this library"
            text: win.query
            onTextEdited: {
              win.query = text
              win.resetCursor()
            }
          }

          // Settings (the bar display mode); available in every state,
          // including an empty or unset library.
          IconButton {
            id: settingsButton
            objectName: "settingsButton"
            theme: win.theme
            anchors.verticalCenter: parent.verticalCenter
            iconName: "settings"
            text: "Settings"
            quiet: true
            diameter: theme.px(26)
            iconSize: Style.font.iconLarge
            onClicked: win.settingsOpen ? win.closeSettings() : win.openSettings()
          }

          IconButton {
            objectName: "closeButton"
            theme: win.theme
            anchors.verticalCenter: parent.verticalCenter
            iconName: "close"
            text: "Close"
            quiet: true
            diameter: theme.px(26)
            iconSize: Style.font.iconLarge
            onClicked: win.closeRequested()
          }
        }
      }

      // ------------------------------------------------------------ sidebar
      Flickable {
        id: sidebar
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.xl
        anchors.bottom: strip.top
        anchors.bottomMargin: Style.spacing.sm
        width: Style.space(180)
        contentHeight: sideColumn.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: sideColumn
          width: sidebar.width
          spacing: Style.spacing.xxs

          Item {
            width: parent.width
            height: Style.space(26)

            PanelSectionHeader {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.xs
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.spacing.xs
              foreground: theme.textPrimary
              text: "LIBRARY"
            }
          }

          SidebarItem {
            objectName: "side-music"
            width: parent.width
            theme: win.theme
            iconName: "folder"
            label: win.libraryRoot !== "" ? Paths.displayName(Paths.baseName(win.libraryRoot) || "/") : "Choose folder"
            current: win.section === "library" && !win.searching
            playing: !!win.service.queue && win.service.queue.source.kind !== "playlist" && win.service.queueIndex >= 0
            onClicked: win.libraryRoot !== "" ? win.openLibrary() : win.openChooser()
          }

          Item {
            width: parent.width
            height: Style.space(26) + Style.spacing.lg

            PanelSectionHeader {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.xs
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.spacing.xs
              foreground: theme.textPrimary
              text: win.store.state === "ready" || win.store.state === "readOnly"
                ? "PLAYLISTS  ·  " + win.store.playlists.length : "PLAYLISTS"
            }
          }

          Repeater {
            model: win.store.state === "ready" || win.store.state === "readOnly" ? win.store.playlists : []

            SidebarItem {
              required property var modelData
              objectName: "side-" + modelData.id
              width: sideColumn.width
              theme: win.theme
              iconName: "playlist"
              label: Paths.displayName(modelData.name)
              detail: String(modelData.count)
              current: win.inPlaylist && win.playlistId === modelData.id
              playing: !!win.service.queue && win.service.queue.source.kind === "playlist"
                && win.service.queue.source.id === modelData.id && win.service.queueIndex >= 0
              onClicked: win.openPlaylist(modelData.id)
            }
          }

          // Playlists can't be used: why, and (if damaged) "Start fresh".
          Column {
            objectName: "storeNotice"
            width: parent.width
            visible: win.store.state === "unreadable" || win.store.state === "location" || win.store.state === "readOnly"
            spacing: Style.spacing.sm
            leftPadding: Style.spacing.xs
            topPadding: Style.spacing.xs

            Text {
              width: parent.width - parent.leftPadding
              text: win.store.state === "unreadable" ? "Playlists couldn't be read"
                : win.store.state === "readOnly" ? "Playlists are read-only" : "Playlists can't be saved here"
              textFormat: Text.PlainText
              color: win.store.state === "readOnly" ? theme.textPrimary : Color.urgent
              font.family: theme.fontFamily
              font.pixelSize: theme.fontSmall
              font.bold: true
              wrapMode: Text.Wrap
            }

            Text {
              width: parent.width - parent.leftPadding
              text: Paths.displayName(win.store.reason)
              textFormat: Text.PlainText
              color: theme.textMuted
              font.family: theme.fontFamily
              font.pixelSize: theme.fontCaption
              wrapMode: Text.Wrap
            }

            Button {
              objectName: "startFresh"
              visible: win.store.state === "unreadable"
              text: "Start fresh…"
              bordered: true
              fontSize: Style.font.bodySmall
              foreground: theme.textPrimary
              onClicked: win.confirmKind = "fresh"
            }
          }

          Text {
            visible: win.store.state === "loading" || win.store.state === "idle"
            leftPadding: Style.spacing.xl
            text: "Loading…"
            textFormat: Text.PlainText
            color: theme.textMuted
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSmall
          }

          TextField {
            id: sideNameField
            objectName: "sideNameField"
            visible: win.naming === "sidebar"
            width: parent.width
            foreground: theme.textPrimary
            placeholderText: "Playlist name"
            Keys.onReturnPressed: win.commitSidebarName(text)
            Keys.onEnterPressed: win.commitSidebarName(text)
          }

          Text {
            visible: win.naming === "sidebar" && win.nameError !== ""
            width: parent.width
            leftPadding: Style.spacing.xs
            text: win.nameError
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSmall
            wrapMode: Text.Wrap
          }

          SidebarItem {
            objectName: "side-new"
            visible: win.naming !== "sidebar" && win.canEdit
            width: parent.width
            theme: win.theme
            iconName: "plus"
            label: "New playlist"
            quiet: true
            onClicked: win.startSidebarNaming()
          }
        }
      }

      PanelSeparator {
        id: divider
        anchors.top: sidebar.top
        anchors.bottom: sidebar.bottom
        x: sidebar.width + Style.spacing.xl
        width: 1
        foreground: theme.textPrimary
      }

      Item {
        id: main
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.xl
        anchors.bottom: strip.top
        anchors.bottomMargin: Style.spacing.sm
        x: divider.x + 1 + Style.spacing.xl
        width: body.width - x

        // ---------------------------------------------------------- location + actions
        Item {
          id: locationRow
          width: parent.width
          height: Style.spacing.controlHeight
          visible: win.libraryRoot !== "" || win.chooser

          Item {
            anchors.left: parent.left
            anchors.right: actions.left
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            clip: true

            // Selection summary.
            Item {
              anchors.fill: parent
              visible: win.selectionCount > 0

              Text {
                id: selectedCount
                anchors.verticalCenter: parent.verticalCenter
                text: win.selectionCount + " selected"
                textFormat: Text.PlainText
                color: theme.textPrimary
                font.family: theme.fontFamily
                font.pixelSize: theme.fontBody
                font.bold: true
              }

              Text {
                anchors.left: selectedCount.right
                anchors.leftMargin: Style.spacing.lg
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Ctrl-click adds · Shift-click selects a range"
                textFormat: Text.PlainText
                color: theme.textMuted
                font.family: theme.fontFamily
                font.pixelSize: theme.fontSmall
                elide: Text.ElideRight
              }
            }

            // Search summary.
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              visible: win.selectionCount === 0 && win.searching
              text: !win.libraryIndex ? "Searching…"
                : win.resultCount + (win.resultCount === 1 ? " result" : " results") + " for “" + Paths.displayName(win.query.trim()) + "”"
              textFormat: Text.PlainText
              color: theme.textSecondary
              font.family: theme.fontFamily
              font.pixelSize: theme.fontBody
              elide: Text.ElideRight
            }

            // Playlist title (or its rename field).
            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.lg
              visible: win.selectionCount === 0 && win.inPlaylist && win.naming !== "rename"

              Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "playlist"
                size: Style.font.iconLarge
                color: theme.textSecondary
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.currentPlaylist ? Paths.displayName(win.currentPlaylist.name) : ""
                textFormat: Text.PlainText
                color: theme.textPrimary
                font.family: theme.fontFamily
                font.pixelSize: theme.fontLabel
                font.bold: true
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Style.space(220))
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.currentPlaylist
                  ? win.currentPlaylist.count + (win.currentPlaylist.count === 1 ? " track" : " tracks") : ""
                textFormat: Text.PlainText
                color: theme.textMuted
                font.family: theme.fontFamily
                font.pixelSize: theme.fontSmall
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(parent.width, Style.space(260))
              visible: win.inPlaylist && win.naming === "rename"

              TextField {
                id: renameField
                objectName: "renameField"
                width: parent.width
                foreground: theme.textPrimary
                placeholderText: "Playlist name"
                Keys.onReturnPressed: win.commitRename(text)
                Keys.onEnterPressed: win.commitRename(text)
              }
            }

            // The library folder, as a path, and how many songs it holds.
            Item {
              objectName: "libraryPath"
              anchors.fill: parent
              visible: win.selectionCount === 0 && win.section === "library" && !win.searching && win.libraryRoot !== ""

              Icon {
                id: pathIcon
                anchors.verticalCenter: parent.verticalCenter
                name: "folder"
                size: Style.font.iconLarge
                color: theme.textSecondary
              }

              Text {
                id: pathText
                anchors.left: pathIcon.right
                anchors.leftMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - pathIcon.width - Style.spacing.sm
                  - (pathCount.visible ? pathCount.implicitWidth + Style.spacing.lg : 0))
                text: win.shortPath(win.libraryRoot)
                textFormat: Text.PlainText
                color: theme.textPrimary
                font.family: theme.fontFamily
                font.pixelSize: theme.fontBody
                font.bold: true
                elide: Text.ElideMiddle
              }

              Text {
                id: pathCount
                anchors.left: pathText.right
                anchors.leftMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                visible: !!win.libraryIndex && win.hero === ""
                text: win.thousands(win.trackCount) + (win.trackCount === 1 ? " song" : " songs")
                textFormat: Text.PlainText
                color: theme.textMuted
                font.family: theme.fontFamily
                font.pixelSize: theme.fontSmall
              }
            }

            // Breadcrumbs (the folder chooser).
            Row {
              id: crumbRow
              anchors.left: parent.left
              anchors.leftMargin: -Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0
              visible: win.selectionCount === 0 && win.chooser

              Repeater {
                model: win.crumbs

                Row {
                  required property var modelData
                  required property int index
                  anchors.verticalCenter: parent.verticalCenter

                  Icon {
                    visible: index > 0 && !(win.chooser && index === 1)
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron"
                    size: Style.font.iconLarge
                    color: theme.textMuted
                  }

                  Button {
                    objectName: "crumb" + index
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    foreground: index === win.crumbs.length - 1 ? theme.textPrimary : theme.textSecondary
                    onClicked: win.openCrumb(modelData.path)
                  }
                }
              }
            }
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            // With a selection.
            Button {
              objectName: "clearSelection"
              visible: win.selectionCount > 0
              text: "Clear"
              bordered: true
              foreground: theme.textPrimary
              onClicked: win.selection = ({})
            }

            Button {
              objectName: "removeFromPlaylist"
              visible: win.selectionCount > 0 && win.inPlaylist && win.canEdit
              text: "Remove from playlist"
              iconText: String.fromCodePoint(0xF0413)   // playlist-remove
              bordered: true
              foreground: theme.textPrimary
              onClicked: win.removePaths(Object.keys(win.selection))
            }

            Button {
              id: addButton
              objectName: "addToPlaylist"
              visible: win.selectionCount > 0 && !win.inPlaylist && win.canEdit
              text: "Add to playlist"
              iconText: String.fromCodePoint(0xF0412)   // playlist-plus
              bordered: true
              active: true
              foreground: theme.textPrimary
              onClicked: win.openMenu(win.selectedPaths(), addButton)
            }

            // A playlist.
            Button {
              objectName: "renamePlaylist"
              visible: win.selectionCount === 0 && win.inPlaylist && win.naming !== "rename" && win.canEdit
              text: "Rename"
              bordered: true
              foreground: theme.textPrimary
              onClicked: win.startRename()
            }

            Button {
              objectName: "deletePlaylist"
              visible: win.selectionCount === 0 && win.inPlaylist && win.naming !== "rename" && win.canEdit
              text: "Delete"
              bordered: true
              foreground: theme.textPrimary
              onClicked: win.confirmKind = "delete"
            }

            // Omarchy's Button has no disabled look: hidden when there is
            // nothing to play.
            Button {
              objectName: "playPlaylist"
              visible: win.selectionCount === 0 && win.inPlaylist && win.naming !== "rename" && !win.playlistEmpty
              text: "Play playlist"
              iconText: String.fromCodePoint(0xF040A)   // play
              bordered: true
              active: true
              foreground: theme.textPrimary
              onClicked: win.playFirst()
            }

            // The library.
            Button {
              objectName: "changeFolder"
              visible: win.selectionCount === 0 && win.section === "library" && !win.searching
              text: "Change folder"
              bordered: true
              foreground: theme.textPrimary
              onClicked: win.openChooser()
            }

            // The folder chooser.
            Button {
              objectName: "cancelChooser"
              // With no folder chosen yet, Cancel goes back to the welcome state.
              visible: win.chooser
              text: "Cancel"
              bordered: true
              foreground: theme.textPrimary
              onClicked: win.openLibrary()
            }

            Button {
              objectName: "useFolder"
              visible: win.chooser && win.chooserStatus === "ok"
              text: "Use this folder"
              bordered: true
              active: true
              foreground: theme.textPrimary
              onClicked: win.useChooserFolder()
            }
          }
        }

        // ---------------------------------------------------------- notices
        Notice {
          id: notice
          objectName: "notice"
          theme: win.theme
          anchors.top: locationRow.visible ? locationRow.bottom : parent.top
          anchors.topMargin: locationRow.visible ? Style.spacing.xl : 0
          width: parent.width
          visible: win.noticeKind !== "" && win.hero !== "noFolder"
          height: visible ? implicitHeight : 0
          error: win.noticeKind === "openFailed" || win.noticeKind === "noPlayer"
          title: ({
            noPlayer: "Vinyl needs mpv to play music",
            openFailed: Paths.displayName(win.service.playbackError),
            storeChanged: "Your playlists changed outside Vinyl",
            limit: win.libraryIndex && win.libraryIndex.status === "timedOut" ? "Only part of your library is listed"
              : "Showing the first 20,000 songs"
          })[win.noticeKind] || ""
          detail: ({
            noPlayer: "Install it, then click a song again.",
            openFailed: "Click a song to try again.",
            storeChanged: "Vinyl reloaded them. Please repeat your change.",
            limit: win.libraryIndex && win.libraryIndex.status === "timedOut"
              ? "Listing stopped after 10 seconds. Everything found so far can be played and searched."
              : "Vinyl lists up to 20,000 songs, 8 folder levels deep."
          })[win.noticeKind] || ""
          command: win.noticeKind === "noPlayer" ? "omarchy pkg add mpv" : ""
        }

        // ---------------------------------------------------------- list or state
        Item {
          id: content
          anchors.top: notice.visible ? notice.bottom : (locationRow.visible ? locationRow.bottom : parent.top)
          anchors.topMargin: notice.visible || locationRow.visible ? Style.spacing.xl : 0
          anchors.bottom: parent.bottom
          width: parent.width
          clip: true

          ListView {
            id: list
            objectName: "list"
            anchors.fill: parent
            visible: win.hero === ""
            model: win.rows
            boundsBehavior: Flickable.StopAtBounds
            // The window's cursor model handles the arrow keys.
            keyNavigationEnabled: false
            focus: true

            delegate: LibraryRow {
              id: rowDelegate
              required property var modelData
              required property int index
              width: ListView.view.width
              theme: win.theme
              row: modelData
              cursor: index === win.cursorIndex
              playing: win.isPlayingRow(modelData)
              selected: modelData.kind === "track" && !!win.selection[modelData.path]
              action: modelData.kind !== "track" || win.chooser || !win.canEdit ? "" : (win.inPlaylist ? "remove" : "add")
              onPicked: (modifiers) => win.pick(index, modifiers)
              // A plain click also clears a selection, like a plain click in Omarchy's lists.
              onActivated: { win.pick(index, Qt.NoModifier); win.cursorIndex = index; win.activate(modelData) }
              onActionRequested: win.rowAction(index, rowDelegate)
            }
          }

          EmptyState {
            anchors.fill: parent
            visible: win.hero !== ""
            theme: win.theme
            icon: ({ noFolder: "library", missing: "alert", permission: "folderLock", emptyLibrary: "musicOff",
                     timedOut: "timer", loading: "folder", failed: "alert", emptyPlaylist: "playlist",
                     chooserMissing: "alert", chooserPermission: "folderLock", chooserTimedOut: "timer" })[win.hero] || "folder"
            error: win.hero === "missing" || win.hero === "permission"
              || win.hero === "chooserMissing" || win.hero === "chooserPermission"
            title: ({
              noFolder: "Your music library is empty",
              emptyLibrary: "Your music library is empty",
              missing: "Music folder not found",
              permission: "Can’t open this folder",
              timedOut: "This folder is taking too long",
              loading: "Loading your music…",
              failed: "Couldn’t read this folder",
              emptyPlaylist: "This playlist is empty",
              chooserMissing: "This folder doesn’t exist",
              chooserPermission: "Can’t open this folder",
              chooserTimedOut: "This folder is taking too long"
            })[win.hero] || ""
            detail: ({
              noFolder: "Choose the folder where you keep your music. Vinyl lists every song in it, subfolders included, and plays them itself.",
              emptyLibrary: win.shortPath(win.libraryRoot) + " has no music Vinyl can play (mp3, flac, ogg, oga, opus, m4a, aac, wav, aif, aiff, wv, ape, wma, or mka), in it or in its subfolders. Choose another folder, or add music to this one and check again.",
              missing: win.shortPath(win.libraryRoot) + " was moved or deleted.",
              permission: "You don’t have permission to read " + win.shortPath(win.libraryRoot) + ".",
              timedOut: "Listing stopped after 10 seconds. Very large or slow folders can hit this limit.",
              emptyPlaylist: "Select tracks in your library, then choose Add to playlist.",
              chooserPermission: "You don’t have permission to read " + Paths.displayName(win.chooserDir) + "."
            })[win.hero] || ""
            primaryAction: ({ noFolder: "Choose Music Folder", emptyLibrary: "Choose Another Folder",
                              missing: "Choose folder", permission: "Choose folder", timedOut: "Try again",
                              failed: "Try again", emptyPlaylist: "Browse library",
                              chooserMissing: "Home", chooserPermission: "Home", chooserTimedOut: "Try again" })[win.hero] || ""
            secondaryAction: win.hero === "missing" ? "Try again" : win.hero === "emptyLibrary" ? "Check Again" : ""
            onPrimaryClicked: {
              var h = win.hero
              if (h === "timedOut" || h === "failed") win.scanLibrary()
              else if (h === "emptyPlaylist") win.openLibrary()
              else if (h === "chooserMissing" || h === "chooserPermission") win.listChooser(win.home)
              else if (h === "chooserTimedOut") win.listChooser(win.chooserDir)
              else win.openChooser()
            }
            onSecondaryClicked: win.scanLibrary()
          }
        }
      }

      // ------------------------------------------------------------ now playing
      NowPlayingStrip {
        id: strip
        objectName: "strip"
        theme: win.theme
        anchors.bottom: parent.bottom
        width: parent.width
        hasTrack: win.service.hasTrack
        title: win.service.title || Paths.trackTitle(Paths.baseName(win.service.playingPath)) || "Unknown track"
        subtitle: [win.service.artist, win.service.album].filter(function(x) { return x !== "" }).join("  ·  ")
        cover: win.service.artUrl
        position: win.service.queue && win.service.queueIndex >= 0
          ? Paths.displayName(win.service.queue.source.name) + "  ·  Track " + (win.service.queueIndex + 1)
            + " of " + win.service.queue.paths.length
          : ""
        player: win.service.hasTrack ? win.service.playerName : ""
        idleDetail: "Click a song to play it"
      }

      // ------------------------------------------------------------ short confirmation messages
      BorderSurface {
        objectName: "toast"
        visible: win.toast !== ""
        anchors.horizontalCenter: main.horizontalCenter
        anchors.bottom: strip.top
        anchors.bottomMargin: Style.spacing.xl
        width: Math.min(main.width, toastText.implicitWidth + Style.spacing.controlPaddingX * 2)
        height: toastText.implicitHeight + Style.spacing.controlPaddingY * 2
        radius: Math.min(Style.cornerRadius, height / 2)
        // Opaque, like Omarchy's in-panel ConfirmDialog, so rows never show through.
        color: Color.background
        borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)

        Text {
          id: toastText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, main.width - Style.spacing.controlPaddingX * 2)
          text: Paths.displayName(win.toast)
          textFormat: Text.PlainText
          color: theme.textPrimary
          font.family: theme.fontFamily
          font.pixelSize: theme.fontSmall
          elide: Text.ElideRight
        }
      }

      // ------------------------------------------------------------ add-to-playlist menu
      PlaylistMenu {
        id: menu
        anchors.fill: parent
        theme: win.theme
        playlists: win.store.playlists
        trackCount: win.menuTracks.length
        opened: win.menuOpen
        onChosen: (id) => {
          win.menuOpen = false
          win.addPaths(id, win.menuTracks)
          list.forceActiveFocus()
        }
        onCreateRequested: (name) => {
          win.edit({ kind: "create", name: name, paths: win.menuTracks }, function(result) {
            if (!result.ok) { menu.error = result.message; return }
            win.menuOpen = false
            win.selection = ({})
            list.forceActiveFocus()
          })
        }
        onCloseRequested: { win.menuOpen = false; list.forceActiveFocus() }
        onRestoreFocus: list.forceActiveFocus()
      }

      // ------------------------------------------------------------ settings
      SettingsMenu {
        id: settings
        anchors.fill: parent
        theme: win.theme
        service: win.service
        opened: win.settingsOpen
        onCloseRequested: win.closeSettings()
      }
    }

    // Omarchy's confirmation dialog, clipped to the card's corners.
    ClippingRectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: "transparent"
      visible: confirm.opened

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        opened: win.confirmKind !== ""
        message: win.confirmKind === "fresh"
          ? "Start fresh? Vinyl keeps your current playlists file as a dated backup, then starts with no playlists."
          : "Delete the playlist “" + (win.currentPlaylist ? Paths.displayName(win.currentPlaylist.name) : "")
            + "”? Your music files are not touched."
        confirmText: win.confirmKind === "fresh" ? "Start fresh" : "Delete"
        onOpenedChanged: selectedIndex = 1
        onCanceled: { win.confirmKind = ""; list.forceActiveFocus() }
        onConfirmed: win.confirmKind === "fresh" ? win.startFresh() : win.deletePlaylist()
      }
    }
  }
}
