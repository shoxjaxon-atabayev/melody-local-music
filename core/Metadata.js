.pragma library

// Helpers for untrusted MPRIS data. Pure functions: nothing here touches the
// network, the filesystem, or evaluates input.

// C0/C1 controls, line/paragraph separators, and bidi embedding/override/
// isolate controls (which can visually reorder text).
var UNSAFE_CHARS = /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g

// Metadata string -> single-line plain text, capped at `maxLength` characters.
function plainText(value, maxLength) {
  if (value === undefined || value === null) return ""
  var limit = maxLength > 0 ? maxLength : 256
  var s = String(value)
  if (s.length > limit * 4) s = s.slice(0, limit * 4)
  s = s.replace(UNSAFE_CHARS, " ").replace(/\s+/g, " ").trim()
  if (s.length > limit) s = s.slice(0, limit).trim() + "…"
  return s
}

// MPRIS artUrl -> a normalized local file:// URL, or "" if it is anything
// else. Only absolute local paths are accepted: no remote hosts, no http(s),
// no data: URIs, no query/fragment, no "." or ".." segments, and nothing
// under /dev, /proc, or /sys.
function localArtUrl(value) {
  if (value === undefined || value === null) return ""
  var s = String(value).trim()
  if (s.length === 0 || s.length > 4096) return ""

  var match = s.match(/^file:\/\/(localhost)?(\/[^?#]*)$/i)
  if (!match) return ""

  var path
  try {
    path = decodeURIComponent(match[2])
  } catch (e) {
    return ""
  }
  if (path.indexOf("\u0000") !== -1) return ""

  var segments = path.split("/")
  for (var i = 1; i < segments.length; i++) {
    var segment = segments[i]
    if (segment === "." || segment === "..") return ""
  }
  if (segments.length < 2 || segments[segments.length - 1] === "") return ""
  if (/^\/(dev|proc|sys)(\/|$)/.test(path)) return ""

  var encoded = []
  for (var j = 1; j < segments.length; j++) {
    if (segments[j] === "") continue
    encoded.push(encodeURIComponent(segments[j]))
  }
  return "file:///" + encoded.join("/")
}

// Longest embedded cover accepted as a data: URL, in characters.
var MAX_DATA_ART = 16 * 1024 * 1024

// MPRIS artUrl -> the cover to show, or "": a local file (see localArtUrl),
// or the image embedded in the music file, which mpv-mpris sends as a
// base64 data: URL. Only image types, only base64 characters, at most
// MAX_DATA_ART characters; Qt decodes it like a cover file.
function artUrl(value) {
  var local = localArtUrl(value)
  if (local !== "") return local
  if (typeof value !== "string" || value.length > MAX_DATA_ART) return ""
  return /^data:image\/(jpeg|png|webp|gif|bmp);base64,[A-Za-z0-9+\/]+={0,2}$/.test(value) ? value : ""
}
