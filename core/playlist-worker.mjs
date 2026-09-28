// Vinyl's playlists, held off the UI thread (Qt WorkerScript). The UI keeps
// only a summary (names and counts) and the entries of the open playlist.
// Every reply echoes `seq`. Edits return the text to save; an edit that
// would make the file larger than 16 MB is undone here, before any save.

const MAX_PLAYLISTS = 100
const MAX_TRACKS = 1000
const MAX_BYTES = 16 * 1024 * 1024
const VERSION = 1

let doc = { version: VERSION, playlists: [] }
let savedText = ""          // the text of the last load or accepted edit

function reply(msg, fields) {
  const out = { seq: msg.seq, op: msg.op }
  for (const k in fields) out[k] = fields[k]
  WorkerScript.sendMessage(out)
}

function summary() {
  return doc.playlists.map(p => ({ id: p.id, name: p.name, count: p.entries.length }))
}

function serialize() {
  return JSON.stringify(doc, null, 2) + "\n"
}

function utf8Length(s) {
  let n = 0
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (c >= 0xd800 && c <= 0xdbff) { n += 4; i++ }
    else n += 3
  }
  return n
}

// Accepts only the exact shape Vinyl writes; anything else is reported, not
// repaired, so no entry is ever dropped silently.
function parse(text) {
  let data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return { error: "malformed" }
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return { error: "malformed" }
  if (typeof data.version !== "number") return { error: "malformed" }
  if (data.version > VERSION) return { error: "newer" }
  if (!Array.isArray(data.playlists)) return { error: "malformed" }
  const ids = {}
  for (const p of data.playlists) {
    if (!p || typeof p !== "object") return { error: "malformed" }
    if (typeof p.id !== "string" || p.id === "" || ids[p.id]) return { error: "malformed" }
    if (typeof p.name !== "string") return { error: "malformed" }
    if (!Array.isArray(p.entries)) return { error: "malformed" }
    for (const e of p.entries) if (typeof e !== "string") return { error: "malformed" }
    ids[p.id] = true
  }
  return { doc: { version: VERSION, playlists: data.playlists.map(p => ({ id: p.id, name: p.name, entries: p.entries.slice() })) } }
}

function find(id) {
  return doc.playlists.find(p => p.id === id) || null
}

function nameProblem(name, exceptId) {
  const n = String(name || "").trim()
  if (n === "") return "Enter a name."
  if (n.length > 64) return "Use at most 64 characters."
  if (/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(n)) return "Use letters, numbers, and punctuation only."
  for (const p of doc.playlists)
    if (p.id !== exceptId && p.name.toLowerCase() === n.toLowerCase()) return "A playlist with this name already exists."
  return ""
}

function newId() {
  let id
  do { id = "p" + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36) } while (find(id))
  return id
}

// New tracks for `entries`: in order, without ones already there or repeated.
function freshPaths(entries, paths) {
  const have = {}
  for (const e of entries) have[e] = true
  const out = []
  for (const p of paths) {
    if (typeof p !== "string" || have[p]) continue
    have[p] = true
    out.push(p)
  }
  return out
}

function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }

// Applies `e` to `doc`. Returns { ok, message, error, id }.
function apply(e) {
  switch (e.kind) {
  case "create": {
    if (doc.playlists.length >= MAX_PLAYLISTS)
      return { ok: false, error: "You already have 100 playlists, the maximum." }
    const problem = nameProblem(e.name, "")
    if (problem) return { ok: false, error: problem }
    const paths = freshPaths([], e.paths || [])
    if (paths.length > MAX_TRACKS)
      return { ok: false, error: "These " + paths.length + " tracks don't fit in one playlist (limit 1,000). Nothing was created." }
    const p = { id: newId(), name: String(e.name).trim(), entries: paths }
    doc.playlists.push(p)
    return { ok: true, id: p.id,
             message: paths.length ? "Created " + p.name + " with " + plural(paths.length, "track", "tracks") + "." : "Created " + p.name + "." }
  }
  case "add": {
    const p = find(e.id)
    if (!p) return { ok: false, error: "That playlist no longer exists." }
    const fresh = freshPaths(p.entries, e.paths || [])
    const skipped = (e.paths || []).length - fresh.length
    if (fresh.length === 0)
      return { ok: false, error: (e.paths || []).length === 1 ? "Already in " + p.name + "." : "All of these are already in " + p.name + "." }
    const room = Math.max(0, MAX_TRACKS - p.entries.length)
    if (fresh.length > room)
      return { ok: false, error: room === 0 ? p.name + " is full (limit 1,000). Nothing was added."
               : p.name + " has room for " + plural(room, "more track", "more tracks") + " (limit 1,000). Nothing was added." }
    for (const x of fresh) p.entries.push(x)
    return { ok: true, id: p.id,
             message: "Added " + plural(fresh.length, "track", "tracks") + " to " + p.name + (skipped ? " · " + skipped + " already there" : "") }
  }
  case "remove": {
    const p = find(e.id)
    if (!p) return { ok: false, error: "That playlist no longer exists." }
    const drop = {}
    for (const x of e.paths || []) drop[x] = true
    const before = p.entries.length
    p.entries = p.entries.filter(x => !drop[x])
    const removed = before - p.entries.length
    if (removed === 0) return { ok: false, error: "Nothing to remove." }
    return { ok: true, id: p.id, message: "Removed " + plural(removed, "track", "tracks") + " from " + p.name }
  }
  case "move": {
    const p = find(e.id)
    if (!p) return { ok: false, error: "That playlist no longer exists." }
    const from = e.index, to = e.index + e.delta
    if (from < 0 || from >= p.entries.length || to < 0 || to >= p.entries.length) return { ok: false, error: "" }
    const x = p.entries.splice(from, 1)[0]
    p.entries.splice(to, 0, x)
    return { ok: true, id: p.id, message: "" }
  }
  case "rename": {
    const p = find(e.id)
    if (!p) return { ok: false, error: "That playlist no longer exists." }
    const problem = nameProblem(e.name, p.id)
    if (problem) return { ok: false, error: problem }
    const old = p.name
    p.name = String(e.name).trim()
    return { ok: true, id: p.id, message: old === p.name ? "" : "Renamed " + old + " to " + p.name + "." }
  }
  case "delete": {
    const i = doc.playlists.findIndex(p => p.id === e.id)
    if (i < 0) return { ok: false, error: "That playlist no longer exists." }
    const name = doc.playlists[i].name
    doc.playlists.splice(i, 1)
    return { ok: true, id: e.id, message: "Deleted " + name + ". Its music files are untouched." }
  }
  }
  return { ok: false, error: "Unknown change." }
}

WorkerScript.onMessage = function(msg) {
  if (msg.op === "load") {
    // msg.text === null: no file yet.
    if (msg.text === null) {
      doc = { version: VERSION, playlists: [] }
      savedText = ""
      reply(msg, { ok: true, summary: summary() })
      return
    }
    const r = parse(msg.text)
    if (r.error) { reply(msg, { ok: false, error: r.error }); return }
    doc = r.doc
    savedText = msg.text
    reply(msg, { ok: true, summary: summary() })
  } else if (msg.op === "entries") {
    const p = find(msg.id)
    reply(msg, { id: msg.id, entries: p ? p.entries.slice() : null })
  } else if (msg.op === "edit") {
    const before = savedText
    const r = apply(msg.edit)
    if (!r.ok) { reply(msg, { ok: false, error: r.error, summary: summary() }); return }
    const text = serialize()
    if (utf8Length(text) > MAX_BYTES) {
      // Undo: back to the last saved state.
      const back = before === "" ? { doc: { version: VERSION, playlists: [] } } : parse(before)
      if (back.doc) doc = back.doc
      reply(msg, { ok: false, error: "Your playlists would be larger than 16 MB, so nothing was changed.", summary: summary() })
      return
    }
    const p = r.id ? find(r.id) : null
    reply(msg, { ok: true, text: text, id: r.id || "", message: r.message, summary: summary(),
                 entries: p ? p.entries.slice() : null })
  } else if (msg.op === "accept") {
    // The edit's text was saved.
    savedText = msg.text
    reply(msg, { ok: true })
  } else if (msg.op === "revert") {
    // Back to `text` (the file on disk), e.g. after a failed or refused save.
    if (msg.text === null) { doc = { version: VERSION, playlists: [] }; savedText = ""; reply(msg, { ok: true, summary: summary() }); return }
    const r = parse(msg.text)
    if (r.error) { reply(msg, { ok: false, error: r.error }); return }
    doc = r.doc
    savedText = msg.text
    reply(msg, { ok: true, summary: summary() })
  }
}
