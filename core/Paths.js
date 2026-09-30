.pragma library

// Path and file-name helpers for the Music Library. Pure functions: nothing
// here touches the filesystem. File and folder names are untrusted text.

// Audio files Melody lists, by extension (case-insensitive).
var AUDIO_EXTENSIONS = ["mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav",
                        "aif", "aiff", "wv", "ape", "wma", "mka"]
var AUDIO_RE = /\.(mp3|flac|ogg|oga|opus|m4a|aac|wav|aif|aiff|wv|ape|wma|mka)$/i

// Control characters, line/paragraph separators, and bidi controls.
var UNSAFE_CHARS = /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g

function isAudioName(name) {
  return AUDIO_RE.test(String(name))
}

function isHiddenName(name) {
  return String(name).charAt(0) === "."
}

// Names with line breaks are shown sanitized but never queued (an M3U line
// break would split the entry).
function hasLineBreak(s) {
  return /[\n\r\u2028\u2029]/.test(String(s))
}

// A file or folder name as single-line plain text.
function displayName(name) {
  var s = String(name === undefined || name === null ? "" : name)
  if (s.length > 1024) s = s.slice(0, 1024) + "…"
  return s.replace(UNSAFE_CHARS, " ")
}

function naturalCompare(a, b) {
  return String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: "base" })
}

function extension(name) {
  var s = String(name)
  var dot = s.lastIndexOf(".")
  return dot > 0 ? s.slice(dot + 1).toUpperCase() : ""
}

// The leading number of a file name ("01 - Title.flac" -> 1), shown in the
// number column; undefined when there is none. Files are never renamed.
function trackNumber(name) {
  var match = String(name).match(/^(\d{1,3})\s*[-.]\s+/)
  return match ? Number(match[1]) : undefined
}

// File name without extension and without the leading track number.
function trackTitle(name) {
  var s = String(name)
  var dot = s.lastIndexOf(".")
  var base = dot > 0 ? s.slice(0, dot) : s
  return displayName(base.replace(/^\d{1,3}\s*[-.]\s+/, "") || base)
}

function baseName(path) {
  var s = String(path)
  return s.slice(s.lastIndexOf("/") + 1)
}

function dirName(path) {
  var s = String(path)
  var i = s.lastIndexOf("/")
  return i > 0 ? s.slice(0, i) : "/"
}

function join(dir, name) {
  return dir === "/" ? "/" + name : dir + "/" + name
}

// Absolute, normalized, no trailing slash: "/a/b". Returns "" otherwise.
function normalizedAbsolute(path) {
  var s = String(path || "")
  if (s.charAt(0) !== "/" || s.indexOf("\u0000") !== -1) return ""
  if (s === "/") return "/"
  var segs = s.split("/")
  for (var i = 1; i < segs.length; i++) {
    if (segs[i] === "" || segs[i] === "." || segs[i] === "..") return ""
  }
  return s
}

// Path relative to `root`, or null when `path` is not strictly inside it.
function relativeTo(root, path) {
  var r = String(root), p = String(path)
  if (r === "/") return p.length > 1 && p.charAt(0) === "/" ? p.slice(1) : null
  return p.indexOf(r + "/") === 0 && p.length > r.length + 1 ? p.slice(r.length + 1) : null
}

// Text-only checks for a playlist entry or queue path (PLAN §2.8), before
// the filesystem checks. Returns { status, ancestors }: status is
// "pending" (needs the filesystem check), "outside" (not in this library),
// or "invalid". `ancestors` lists every folder level below the root.
function precheck(root, path) {
  if (typeof path !== "string" || path.length === 0 || path.length > 4096) return { status: "invalid" }
  if (/[\n\r\u0000]/.test(path)) return { status: "invalid" }
  var rel = relativeTo(root, path)
  if (rel === null) return { status: "outside" }
  var segs = rel.split("/")
  for (var i = 0; i < segs.length; i++) {
    var s = segs[i]
    if (s === "" || s === "." || s === "..") return { status: "invalid" }
    if (s.charAt(0) === ".") return { status: "invalid" }
  }
  if (!isAudioName(segs[segs.length - 1])) return { status: "invalid" }
  var ancestors = []
  var base = root === "/" ? "" : root
  for (var j = 1; j < segs.length; j++) ancestors.push(base + "/" + segs.slice(0, j).join("/"))
  return { status: "pending", ancestors: ancestors }
}

// Local path -> file:// URL with every segment percent-encoded.
function fileUrl(path) {
  var segs = String(path).split("/")
  var out = []
  for (var i = 1; i < segs.length; i++) out.push(encodeURIComponent(segs[i]))
  return "file:///" + out.join("/")
}

// file:// URL -> local path, or "" for anything else.
function pathFromUrl(url) {
  var m = String(url || "").match(/^file:\/\/(localhost)?(\/[^?#]*)$/i)
  if (!m) return ""
  try {
    var p = decodeURIComponent(m[2])
    return p.indexOf("\u0000") === -1 ? p : ""
  } catch (e) {
    return ""
  }
}

// UTF-8 byte length of a string (for the playlists-file size cap).
function utf8Length(s) {
  var n = 0
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (c >= 0xd800 && c <= 0xdbff) { n += 4; i++ }
    else n += 3
  }
  return n
}
