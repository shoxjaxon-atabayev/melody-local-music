import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../core/Paths.js" as Paths

// The mini-player's setup steps, shown in place of the player while Melody
// can't play yet: first install what Melody runs, when something is missing
// (a warning, the missing packages, and Install), then choose the music
// folder. The install runs in Omarchy's terminal (core/Requirements.qml),
// and the card closes so the terminal is in view; this view follows the
// install and shows the folder step (or Try Again) when it is opened again.
Item {
  id: root

  required property var theme
  required property var service

  signal folderRequested()
  // Install started its terminal.
  signal installStarted()

  readonly property var requirements: service ? service.requirements : null
  readonly property var missing: requirements ? requirements.missing : []
  readonly property bool installStep: !!requirements && requirements.checked && missing.length > 0
  readonly property bool installing: !!requirements && requirements.installing
  readonly property bool failed: !!requirements && requirements.installState === "failed"
  readonly property string folderStatus: !service ? "unset"
    : service.libraryRoot === "" ? "unset" : service.libraryStatus

  // What each package is for.
  readonly property var purposes: ({
    "mpv": "plays your music",
    "mpv-mpris": "media keys and cover art",
    "cava": "the Spectrum bar display"
  })

  // Nerd Font code points for the button, as in Icon.qml.
  readonly property string downloadGlyph: String.fromCodePoint(0xF01DA)   // download
  readonly property string loadingGlyph: String.fromCodePoint(0xF0772)    // loading

  // The music folder for people: the home folder as "~".
  readonly property string home: Quickshell.env("HOME") || "/"
  readonly property string folderPath: {
    var p = service ? String(service.libraryRoot) : ""
    if (home !== "/" && (p === home || p.indexOf(home + "/") === 0)) p = "~" + p.slice(home.length)
    return Paths.displayName(p)
  }

  readonly property string titleText: {
    if (installStep) return missing.length === 1 ? "Melody needs one package" : "Melody needs " + missing.length + " packages"
    if (folderStatus === "empty") return "Your music folder has no music"
    if (folderStatus === "missing" || folderStatus === "notFolder") return "Music folder not found"
    if (folderStatus === "permission") return "Can’t open your music folder"
    return "Choose your music folder"
  }

  readonly property string detailText: {
    if (installStep) return ""
    if (folderStatus === "empty") return folderPath + " has no music Melody can play. Choose another folder."
    if (folderStatus === "missing" || folderStatus === "notFolder") return folderPath + " was moved or deleted."
    if (folderStatus === "permission") return "You don’t have permission to read " + folderPath + "."
    return "Melody lists every song in it, subfolders included, and plays them itself."
  }

  readonly property string noteText: !installStep ? ""
    : installing ? "Continue in the terminal window. Melody goes on by itself when it’s done."
    : failed ? "The installation didn’t finish. Try again."
    : "They install in a terminal window, which asks for your password."

  implicitHeight: column.implicitHeight

  Column {
    id: column
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    spacing: Style.spacing.lg

    Icon {
      objectName: "setupIcon"
      anchors.horizontalCenter: parent.horizontalCenter
      name: root.installStep ? "alert" : "library"
      size: theme.px(28)
      color: root.installStep ? Color.urgent : theme.textSecondary
    }

    Text {
      objectName: "setupTitle"
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.titleText
      textFormat: Text.PlainText
      color: theme.textPrimary
      font.family: theme.fontFamily
      font.pixelSize: theme.fontLabel
      font.bold: true
      wrapMode: Text.Wrap
    }

    Text {
      objectName: "setupDetail"
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      visible: text !== ""
      text: root.detailText
      textFormat: Text.PlainText
      color: theme.textMuted
      font.family: theme.fontFamily
      font.pixelSize: theme.fontBody
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
    }

    // The missing packages, each with what it's for.
    Column {
      objectName: "setupPackages"
      visible: root.installStep
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.xs

      Repeater {
        model: root.installStep ? root.missing : []

        Row {
          id: pkgRow
          required property string modelData
          spacing: root.theme.px(6)

          Text {
            text: pkgRow.modelData
            textFormat: Text.PlainText
            color: root.theme.textPrimary
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontBody
            font.bold: true
          }

          Text {
            text: "— " + (root.purposes[pkgRow.modelData] || "")
            textFormat: Text.PlainText
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontBody
          }
        }
      }
    }

    Text {
      objectName: "setupNote"
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      visible: text !== ""
      text: root.noteText
      textFormat: Text.PlainText
      color: root.failed && !root.installing ? Color.urgent : theme.textSecondary
      font.family: theme.fontFamily
      font.pixelSize: theme.fontSmall
      wrapMode: Text.Wrap
    }

    Button {
      objectName: "setupAction"
      anchors.horizontalCenter: parent.horizontalCenter
      text: !root.installStep ? (root.folderStatus === "unset" ? "Choose Music Folder" : "Choose Another Folder")
        : root.installing ? "Installing…"
        : root.failed ? "Try Again" : "Install"
      iconText: root.installStep ? (root.installing ? root.loadingGlyph : root.downloadGlyph) : ""
      iconSpinning: root.installing
      iconSize: Style.font.iconSmall
      bordered: true
      active: true
      foreground: theme.textPrimary
      enabled: !root.installing
      onClicked: {
        if (!root.installStep) { root.folderRequested(); return }
        root.requirements.install()
        if (root.requirements.installing) root.installStarted()
      }
    }
  }
}
