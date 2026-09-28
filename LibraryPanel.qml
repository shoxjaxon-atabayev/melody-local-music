import QtQuick

// Omarchy "panel" entry for the Music Library. It lets the shell open and
// close the library, for example from a keyboard shortcut:
//   omarchy-shell shell toggle community.shoxjaxon.vinyl '{}'
// The window itself belongs to Vinyl's service, so it keeps its state and
// its close fade after the shell unloads this entry.
Item {
  id: root

  // Injected by the shell.
  property var shell: null
  property var manifest: null

  readonly property var service: shell && manifest && typeof shell.serviceFor === "function"
    ? shell.serviceFor(manifest.id) : null
  // The shell asks this to know whether the panel is open.
  readonly property bool opened: !!service && service.libraryOpen

  function open(payloadJson) {
    if (service) service.showLibrary()
  }

  function close() {
    if (service) service.closeLibrary()
  }

  // When the library closes itself (Escape, close button, outside click),
  // tell the shell, so its next toggle opens it again.
  Connections {
    target: root.service
    function onLibraryOpenChanged() {
      if (!root.service || root.service.libraryOpen || !root.shell || !root.manifest) return
      var shellApi = root.shell
      var id = root.manifest.id
      Qt.callLater(function() { shellApi.hide(id) })
    }
  }
}
