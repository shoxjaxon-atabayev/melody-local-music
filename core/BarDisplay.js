.pragma library

// The bar's display modes and the Track Info text. Plain functions with no
// QML types, so they can also be checked outside the shell.

var TRACK_INFO = "trackInfo"
var SPECTRUM = "spectrum"
var PULSE_DOTS = "pulseDots"
var MODES = [TRACK_INFO, SPECTRUM, PULSE_DOTS]

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

// `title` cut to at most `max` characters (code points, so no emoji or
// accented letter is split), ending in a single "…" when it was cut.
function shortTitle(title, max) {
  var limit = max === undefined ? MAX_TITLE : max
  var chars = Array.from(String(title || "").trim())
  if (chars.length <= limit) return chars.join("")
  return chars.slice(0, limit - 1).join("").replace(/\s+$/, "") + "…"
}

// "Full Artist Name — Song Ti…": the artist in full, the title shortened.
function trackLabel(artist, title) {
  var a = String(artist || "").trim()
  var t = shortTitle(title)
  if (a !== "" && t !== "") return a + " — " + t
  return a !== "" ? a : t
}
