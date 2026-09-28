# Vinyl

A minimal local music player companion for [Omarchy](https://omarchy.org/).
Vinyl puts what you're listening to in your bar, gives you a small
mini-player to control it, and adds a music library window for browsing,
searching, and playing a music folder you choose — with your own playlists.

Vinyl doesn't play audio itself. It works with the music player you already
use, through the standard MPRIS interface. It never goes online, never scans
in the background, and never changes your music files.

## Features

**In the bar**

- A now-playing icon: a small cover thumbnail while music plays, dimmed when
  paused, and a plain music note when nothing is playing.
- Hover for the current title and artist.

**Mini-player** (click the icon)

- Cover art, title, artist, and album.
- Play/pause, previous, next, shuffle, and repeat-one.
- A progress bar you can click or drag to seek.
- Controls your player doesn't support are shown disabled.
- A library button that opens the Music Library.

**Music Library**

- Browse one music folder of your choice and its subfolders.
- Search the whole folder by file or folder name.
- Play a track, or play a whole folder, as a continuous queue: from the track
  you pick to the end of the folder or search results.
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
- For the mini-player: any MPRIS music player, such as mpv, MPD (with
  mpDris2), or Strawberry. Web browsers are ignored on purpose.
- For playing from the Music Library: **mpv** with the **mpv-mpris** plugin.
  Install both with:

  ```bash
  omarchy pkg add mpv mpv-mpris
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

   The Vinyl icon appears in the right section of your bar. To move it, use
   `omarchy bar move community.shoxjaxon.vinyl --section <left|center|right>`.

You can also do both steps at once:

```bash
omarchy plugin add https://github.com/shoxjaxon-atabayev/vinyl-local-music.git --enable
```

## Getting started

1. Start mpv so it waits for music to play:

   ```bash
   mpv --idle --force-window=no
   ```

   Vinyl never starts or stops a player for you.

2. Click the Vinyl icon in the bar, then the library button next to the close
   button.
3. Choose your music folder: browse to it and click **Use this folder**.
   Vinyl remembers it.
4. Double-click a track (or select it and press Enter) to play it.

## Using the Music Library

**Mouse**

- Click a folder to open it; use the path at the top to go back.
- Double-click a track to play from there.
- **Play folder** plays the current folder from its first track.
- Hover a track and click its **+** button to add it to a playlist.
- To add several tracks: click one, then **Ctrl-click** more (or
  **Shift-click** for a range), and choose **Add to playlist**.
- In a playlist, hover a track and click **−** to remove it, or use
  **Rename**, **Delete**, and **Play playlist** at the top.
- Click outside the window to close it.

**Keyboard**

| Key | Action |
|---|---|
| ↑ / ↓ | Move through the list |
| Enter | Open a folder or play a track |
| Backspace | Go up one folder |
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
- **Playlists** are saved in `~/.local/share/vinyl/playlists.json`
  (or `$XDG_DATA_HOME/vinyl/playlists.json`). The folder and file are
  private to your user. Limits: 100 playlists, 1,000 tracks per playlist,
  and 16 MB for the file.

Supported audio files: mp3, flac, ogg, oga, opus, m4a, aac, wav, aif, aiff,
wv, ape, wma, and mka. Hidden files and folders are not shown. Links
(symlinks) inside your music folder are never followed, and Vinyl never reads
anything outside the folder you chose.

## Troubleshooting

**"No compatible player is running"**
Start mpv with `mpv --idle --force-window=no`, and make sure `mpv-mpris` is
installed. Library playback works with mpv only.

**The library plays the whole list again after the last track**
mpv's own "loop playlist" setting is on (for example `loop-playlist` in
`~/.config/mpv/mpv.conf`). Vinyl shows a notice but doesn't change your mpv
settings.

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

**The icon doesn't appear in the bar**
Check that the plugin is enabled: `omarchy plugin list`. If you edited the
plugin's files by hand, reload with `omarchy-shell shell rescanPlugins`.

## Removing Vinyl

```bash
omarchy plugin remove community.shoxjaxon.vinyl
```

Your playlists stay in `~/.local/share/vinyl/`. Delete that folder if you
don't need them anymore.

## Privacy

Vinyl needs no network access and sends nothing anywhere. It reads only your
chosen music folder and its own playlists file, and writes only its
playlists file, a temporary queue file in your private runtime folder
(emptied as soon as mpv has loaded it), and its settings entry in
`shell.json`.

## License

[MIT](LICENSE)
