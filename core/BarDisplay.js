.pragma library

// The bar's display modes and the Track Info text. Plain functions with no
// QML types, so they can also be checked outside the shell.

var TRACK_INFO = "trackInfo"
var SPECTRUM = "spectrum"
var PULSE_DOTS = "pulseDots"
var MODES = [TRACK_INFO, SPECTRUM, PULSE_DOTS]

// What Track Info shows: "Artist — Title" (the default), the title only,
// or the artist only.
var LABEL_ARTIST_TITLE = "artistTitle"
var LABEL_TITLE = "title"
var LABEL_ARTIST = "artist"
var LABELS = [LABEL_ARTIST_TITLE, LABEL_TITLE, LABEL_ARTIST]

// Longest title shown in Track Info, counting the ellipsis.
var MAX_TITLE = 12

// A saved setting, or Track Info (the default) for anything missing or
// unknown.
function normalizeMode(value) {
  return typeof value === "string" && MODES.indexOf(value) !== -1 ? value : TRACK_INFO
}

function isVisual(mode) {
  return mode === SPECTRUM || mode === PULSE_DOTS
}

// A saved Track Info choice, or "Artist — Title" (the default) for anything
// missing or unknown.
function normalizeLabel(value) {
  return typeof value === "string" && LABELS.indexOf(value) !== -1 ? value : LABEL_ARTIST_TITLE
}

// The title without a leading copy of the artist, as files from video
// sites often have it: "Tame Impala - Let It Happen" by Tame Impala is
// "Let It Happen". Only when the artist is followed by a dash, colon, or
// bar and more text; any other title is kept as it is.
function cleanTitle(artist, title) {
  var t = String(title || "").trim()
  var a = String(artist || "").trim()
  if (a === "" || t.length <= a.length || t.slice(0, a.length).toLowerCase() !== a.toLowerCase()) return t
  var rest = t.slice(a.length).match(/^\s*[-–—:|]\s*(\S[\s\S]*)$/)
  return rest ? rest[1] : t
}

// `title` cut to at most `max` characters (code points, so no emoji or
// accented letter is split), ending in a single "…" when it was cut.
function shortTitle(title, max) {
  var limit = max === undefined ? MAX_TITLE : max
  var chars = Array.from(String(title || "").trim())
  if (chars.length <= limit) return chars.join("")
  return chars.slice(0, limit - 1).join("").replace(/\s+$/, "") + "…"
}

// Track Info's text for `label` (see LABELS; the default when missing):
//   artistTitle  "Full Artist Name — Song Ti…": the artist in full, the
//                title shortened
//   title        "Song Ti…"
//   artist       "Full Artist Name"
// With one of the two missing, the other is shown.
function trackLabel(artist, title, label) {
  var a = String(artist || "").trim()
  var t = shortTitle(title)
  var l = normalizeLabel(label)
  if (l === LABEL_TITLE) return t !== "" ? t : a
  if (l === LABEL_ARTIST) return a !== "" ? a : t
  if (a !== "" && t !== "") return a + " — " + t
  return a !== "" ? a : t
}
