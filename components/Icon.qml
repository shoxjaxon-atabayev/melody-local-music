import QtQuick
import qs.Commons
import qs.Ui

// An icon in Omarchy's system convention: a Material Design glyph from the
// system Nerd Font (Style.font.family), drawn with Omarchy's OpticalGlyph —
// the same glyph set Omarchy's media widget (play, pause, skip) and clock
// panel (chevrons) use. Code points are written as numbers so the source
// stays plain ASCII.
OpticalGlyph {
  id: root

  property string name: "folder"
  property real size: Style.font.icon

  readonly property var codes: ({
    folder: 0xF024B,       // folder
    chevron: 0xF0142,      // chevron-right
    library: 0xF0333,      // library-music
    alert: 0xF0026,        // alert
    info: 0xF02FD,         // information-outline
    folderLock: 0xF0250,   // folder-lock
    musicOff: 0xF075B,     // music-off
    timer: 0xF051F,        // timer-sand
    note: 0xF075A,         // music
    close: 0xF0156,        // close
    play: 0xF040A,         // play
    pause: 0xF03E4,        // pause
    next: 0xF04AD,         // skip-next
    previous: 0xF04AE,     // skip-previous
    shuffle: 0xF049D,      // shuffle-variant
    repeatOne: 0xF0458,    // repeat-once
    playlist: 0xF0CB8,     // playlist-music
    playlistAdd: 0xF0412,  // playlist-plus
    playlistRemove: 0xF0413, // playlist-remove
    check: 0xF012C,        // check
    plus: 0xF0415,         // plus
    rename: 0xF03EB,       // pencil
    remove: 0xF0374,       // minus
    search: 0xF0349        // magnify
  })

  text: codes[name] !== undefined ? String.fromCodePoint(codes[name]) : ""
  fontSize: size
  implicitWidth: size
  implicitHeight: size
}
