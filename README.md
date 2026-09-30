# Vinyl

A minimal local music player for [Omarchy](https://omarchy.org/). Choose
your music folder once, and every song in it — subfolders included — is in
one list: click a song and it plays. Vinyl puts what you're listening to in
your bar, gives you a small mini-player to control it, and remembers where
you stopped, even after a restart.

Vinyl plays music itself, with a hidden mpv it starts and stops on its own:
there is nothing to run by hand and no player window. It also shows and
controls other local music players (through the standard MPRIS interface)
while they play. It never goes online, never scans in the background, and
never changes your music files.

## Features

**In the bar**

- What's playing, in the style you choose (see [Bar display](#bar-display)):
  - **Track Info** (default): `Artist Name — Song Title`, with the title
    shortened to 12 characters, after a play or pause sign that shows
    whether the song is playing or paused.
  - **Spectrum**: small frequency bars that follow the music.
  - **Pulse Dots**: a row of dots that follow how loud the music is.
- Dimmed while paused. Hover for the full title and artist.
- Right-click to pause or resume.
- After a restart it shows the song you stopped on, paused where you left it.
- Before you've chosen a music folder, it shows **Set up music library**.

**Mini-player** (click Vinyl in the bar)

- Cover art, title, artist, and album.
- Play/pause, previous, next, shuffle, and repeat-one.
- A progress bar you can click or drag to seek.
- Controls your player doesn't support are shown disabled.
- A library button that opens the Music Library.

**Music Library**

- Every song in your music folder and its subfolders, in one list, grouped
  in blocks headed by each folder's path.
- Click any song to play it. The rest of the list plays after it (and
  **previous** goes back up the list), then playback stops.
- Search the whole library by file or folder name.
- Vinyl remembers the song, the queue, and the exact position. Pause, turn
  the computer off, and the next day the song is waiting in the bar, paused
  at the same spot — play continues right there, never from 0.
- **Playlists:** collect tracks from anywhere in your library into named
  playlists. Create, rename, delete, add, remove, and reorder.
- Playing a track from a playlist plays only that playlist: from the chosen
  track to the end, then from the beginning up to the track before it.
- Tracks that were moved or deleted are marked as missing and skipped.
- Full keyboard control, and a keyboard shortcut to open the library.

Vinyl follows your Omarchy theme, font, and colors, and opens and closes like
Omarchy's own panels.

## Requirements

- **Omarchy** with its Quickshell-based shell (Omarchy 4 or newer).
- **mpv**, which plays the music, and **mpv-mpris**, which lets media keys
  and Omarchy's media controls reach Vinyl. Omarchy installs both by
  default; if you removed them:

  ```bash
  omarchy pkg add mpv mpv-mpris
  ```

  Vinyl starts mpv itself, only while it has something to play, without a
  window and without your own mpv settings (`mpv.conf` doesn't affect it).
- Optional: the mini-player also shows other MPRIS music players, such as
  MPD (with mpDris2) or Strawberry. Web browsers are ignored on purpose.

- Optional, for the **Spectrum** bar display only: **cava**.

  ```bash
  omarchy pkg add cava
  ```

## Installation

1. Add the plugin:

   ```bash
   omarchy plugin add https://github.com/shoxjaxon-atabayev/vinyl-local-music.git
   ```

   Plugins are added disabled, so you can review the code first. The files
   are placed in `~/.config/omarchy/plugins/community.shoxjaxon.vinyl/`.

2. Enable it:

   ```bash
   omarchy plugin enable community.shoxjaxon.vinyl
   ```

   Vinyl appears in the right section of your bar. To move it, use
   `omarchy bar move community.shoxjaxon.vinyl --section <left|center|right>`.

You can also do both steps at once:

```bash
omarchy plugin add https://github.com/shoxjaxon-atabayev/vinyl-local-music.git --enable
```

## Getting started

1. Click **Set up music library** in the bar, then the library button next
   to the close button.
2. Click **Choose Music Folder**, browse to your music (for example
   `~/Music`), and click **Use this folder**. Vinyl remembers it. (If the
   folder has no music Vinyl can play, the library says so and lets you
   choose another one.)
3. Click any song to play it.

That's all: there is no player to start.

## Bar display

Open the Music Library and click the **Settings** button (the cog next to
the close button). Choose how the bar shows what's playing:

| Mode | Shows |
|---|---|
| **Track Info** (default) | `Artist Name — Song Title`. The artist is shown in full; the title is shortened to 12 characters, ending in "…" when cut. A play sign before it means the song is playing, a pause sign that it is paused. |
| **Spectrum** | Twenty-four small bars, low to high frequencies, measured from the music. Needs **cava**. |
| **Pulse Dots** | Five dots whose size follows how loud the music is. |

The choice applies at once and is kept after restarts. Spectrum and Pulse
Dots move only with real audio: while paused, or when there is no audio to
read, they rest flat. They read only your music player's own sound, never
other apps (see [Privacy](#privacy)).

## Using the Music Library

**Mouse**

- Click a song to play it. Clicking the song that is playing doesn't
  restart it.
- **Change folder** (next to the folder's path at the top) picks another
  music folder.
- Hover a track and click its **+** button to add it to a playlist.
- To add several tracks: **Ctrl-click** each one (this selects without
  playing; **Shift-click** selects a range), and choose **Add to playlist**.
- In a playlist, hover a track and click **−** to remove it, or use
  **Rename**, **Delete**, and **Play playlist** at the top.
- Click the cog next to the close button for **Settings** (the bar display).
- Click outside the window to close it.

**Keyboard**

| Key | Action |
|---|---|
| ↑ / ↓ | Move through the list |
| Enter | Play the song (in the folder chooser: open the folder) |
| Backspace | In the folder chooser: go up one folder |
| / | Search |
| Space | Select or unselect the track |
| Shift + ↑ / ↓ | Extend the selection |
| Ctrl + A | Select all tracks |
| Alt + ↑ / ↓ | Move a track up or down in a playlist |
| Delete | Remove the track from the playlist |
| Escape | Close a menu, clear the selection or search, or close the window |

Removing a track from a playlist never deletes the music file.

### A keyboard shortcut for the library

Add a line to `~/.config/hypr/bindings.lua` (pick a key combination that
isn't already in use — see `omarchy menu keybindings --print`):

```lua
o.bind("SUPER + SHIFT + M", "Music library", "omarchy-shell shell toggle community.shoxjaxon.vinyl")
```

## Configuration

- **Music folder:** choose it in the library (**Change folder**). It is saved
  with Vinyl's entry in `~/.config/omarchy/shell.json` as `libraryFolder`.
- **Bar display:** choose it in the library's **Settings**. It is saved in
  the same entry as `displayMode`: `trackInfo`, `spectrum`, or `pulseDots`.
  A missing or unknown value means Track Info.
- **Playlists** are saved in `~/.local/share/vinyl/playlists.json`
  (or `$XDG_DATA_HOME/vinyl/playlists.json`). The folder and file are
  private to your user. Limits: 100 playlists, 1,000 tracks per playlist,
  and 16 MB for the file.
- **Where you stopped** (the queue, the song, its position, shuffle and
  repeat) is saved in `session.json` in the same private folder: on every
  pause, seek, and song change, and every 5 seconds while playing. A queue
  holds up to 1,000 songs.
- The library lists up to 20,000 songs, 8 folder levels deep.

Supported audio files: mp3, flac, ogg, oga, opus, m4a, aac, wav, aif, aiff,
wv, ape, wma, and mka. Hidden files and folders are not shown. Links
(symlinks) inside your music folder are never followed, and Vinyl never reads
anything outside the folder you chose.

## Troubleshooting

**"Vinyl needs mpv to play music"**
mpv isn't installed. Install it with `omarchy pkg add mpv mpv-mpris`, then
click the song again.

**Media keys don't pause Vinyl**
They reach Vinyl through mpv-mpris: install it with
`omarchy pkg add mpv-mpris`. The bar's right click and the mini-player work
without it.

**"Playlists couldn't be read"**
The playlists file is damaged, larger than 16 MB, or from a newer version of
Vinyl. Vinyl doesn't change it. Click **Start fresh** and confirm to begin with
an empty list — your old file is kept next to it as
`playlists.json.bak-<date-time>`.

**"Playlists are read-only" or "can't be saved here"**
For safety, Vinyl only saves to a private folder and file. Fix the
permissions:

```bash
chmod 700 ~/.local/share/vinyl
chmod 600 ~/.local/share/vinyl/playlists.json
```

Vinyl also refuses to save if `~/.local/share/vinyl` or `playlists.json` is a
symbolic link.

**A track shows "Missing" or "Not in this library"**
The file was moved, renamed, or deleted, or it is outside the music folder
you chose. Missing tracks are skipped when playing; remove them from the
playlist or put the file back.

**Icons show as boxes**
Vinyl uses the icon glyphs of your Omarchy font. Omarchy installs a font with
these glyphs by default (JetBrainsMono Nerd Font); reinstall it if it was
removed.

**Vinyl doesn't appear in the bar**
Check that the plugin is enabled: `omarchy plugin list`. If you edited the
plugin's files by hand, reload with `omarchy-shell shell rescanPlugins`.

**Spectrum says it needs cava**
Install it with `omarchy pkg add cava`, then choose Spectrum again in the
library's Settings. Track Info and Pulse Dots don't need it.

**Spectrum or Pulse Dots stay flat while music plays**
They read the sound of your music player's own PipeWire stream. Hover Vinyl
in the bar: "No audio data" means that stream wasn't found — for example, the
player outputs audio without PipeWire, or its audio is turned off. The dots
and bars never move without real sound.

**The bar shows text on a horizontal bar only**
On a bar placed left or right there is no room for text or visualizations,
so Vinyl shows its music note in every mode.

## Removing Vinyl

```bash
omarchy plugin remove community.shoxjaxon.vinyl
```

Your playlists and the saved session stay in `~/.local/share/vinyl/`.
Delete that folder if you don't need them anymore.

## Privacy

Vinyl needs no network access and sends nothing anywhere; its mpv plays
local files only (online streaming is turned off). It reads only your chosen
music folder and its own files, and writes only its playlists file, its
session file, a temporary queue file and mpv's control socket in your
private runtime folder (the queue file is emptied as soon as mpv has loaded
it), and its settings entry in `shell.json`.

With **Spectrum** or **Pulse Dots** selected, and only while music plays,
Vinyl also reads the sound level of your music player's own output — never
other applications, never your microphone. Pulse Dots reads it inside the
shell; Spectrum reads it through cava, using a small settings file in the
same private runtime folder. Nothing is recorded, stored, or sent. With
Track Info (the default), no audio is read at all.

## License

[MIT](LICENSE)
