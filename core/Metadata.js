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


var MAX_DATA_ART = 16 * 1024 * 1024

// PNG structural and image dimension limits.
var MAX_PNG_CHUNKS = 4096
var MAX_PNG_WIDTH = 4096
var MAX_PNG_HEIGHT = 4096
var MAX_PNG_PIXELS = 16 * 1024 * 1024

var BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function base64Byte(data, index) {
  var group = Math.floor(index / 3)
  var pos = group * 4
  var a = BASE64.indexOf(data.charAt(pos))
  var b = BASE64.indexOf(data.charAt(pos + 1))
  var c = BASE64.indexOf(data.charAt(pos + 2))
  var d = BASE64.indexOf(data.charAt(pos + 3))

  if (a < 0 || b < 0) return -1

  if (index % 3 === 0) return (a << 2) | (b >> 4)
  if (index % 3 === 1) return ((b & 15) << 4) | (c >> 2)
  if (c < 0 || d < 0) return -1
  return ((c & 3) << 6) | d
}

function pngUint32(data, offset) {
  var a = base64Byte(data, offset)
  var b = base64Byte(data, offset + 1)
  var c = base64Byte(data, offset + 2)
  var d = base64Byte(data, offset + 3)

  if (a < 0 || b < 0 || c < 0 || d < 0) return -1

  return a * 16777216 + b * 65536 + c * 256 + d
}

// Inspect PNG chunk headers directly in the base64 string. Do not decode
// the entire image into a second buffer just to validate its structure.
function safePngBase64(data) {
  if (typeof data !== "string" || data.length < 16 || data.length % 4 !== 0) return false

  var padding = data.slice(-2) === "==" ? 2 : data.slice(-1) === "=" ? 1 : 0
  var byteLength = (data.length / 4) * 3 - padding

  if (byteLength < 57) return false

  // PNG signature.
  var signature = [137, 80, 78, 71, 13, 10, 26, 10]
  for (var s = 0; s < 8; s++) {
    if (base64Byte(data, s) !== signature[s]) return false
  }

  var offset = 8
  var chunks = 0
  var seenIHDR = false
  var seenIDAT = false
  var endedIDAT = false
  var seenIEND = false

  while (offset < byteLength) {
    if (++chunks > MAX_PNG_CHUNKS || offset + 12 > byteLength) return false

    var length = base64Byte(data, offset) * 16777216
      + base64Byte(data, offset + 1) * 65536
      + base64Byte(data, offset + 2) * 256
      + base64Byte(data, offset + 3)

    if (!isFinite(length) || length < 0 || length > byteLength - offset - 12) return false

    var type = ""
    for (var t = 0; t < 4; t++) {
      var ch = base64Byte(data, offset + 4 + t)
      if (ch < 65 || (ch > 90 && ch < 97) || ch > 122) return false
      type += String.fromCharCode(ch)
    }

    // PNG's first chunk must be IHDR, exactly once, with a 13-byte body.
    if (!seenIHDR) {
      if (type !== "IHDR" || length !== 13) return false

      var width = pngUint32(data, offset + 8)
      var height = pngUint32(data, offset + 12)

      if (width < 1 || height < 1) return false
      if (width > MAX_PNG_WIDTH || height > MAX_PNG_HEIGHT) return false
      if (width * height > MAX_PNG_PIXELS) return false

      seenIHDR = true
    } else if (type === "IHDR") {
      return false
    }

    // Reject text and compressed-profile chunks before Qt/libpng sees them.
    // This avoids unbounded aggregate decompression of untrusted metadata.
    if (type === "tEXt" || type === "zTXt" || type === "iTXt" || type === "iCCP") {
      return false
    }

    if (type === "IDAT") {
      if (endedIDAT) return false
      seenIDAT = true
    } else if (seenIDAT && type !== "IEND") {
      endedIDAT = true
    }

    offset += length + 12

    if (type === "IEND") {
      if (length !== 0 || !seenIDAT || offset !== byteLength) return false
      seenIEND = true
      break
    }
  }

  return seenIHDR && seenIDAT && seenIEND
}

// MPRIS artUrl -> the cover to show, or "": a local file (see localArtUrl),
// or a bounded embedded image. PNG chunks are checked before reaching Qt.
function artUrl(value) {
  var local = localArtUrl(value)
  if (local !== "") return local
  if (typeof value !== "string" || value.length > MAX_DATA_ART) return ""

  var match = value.match(/^data:image\/(jpeg|png|webp|gif|bmp);base64,([A-Za-z0-9+/]+={0,2})$/)
  if (!match) return ""

  if (match[1] === "png" && !safePngBase64(match[2])) return ""
  return value
}
