import QtQuick
import Quickshell

// Omarchy shell plugin entry point (overlay kind). omarchy-shell injects
// `shell` and `manifest`, then calls open(), close() and toggle() as the
// plugin is summoned, hidden or toggled.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  readonly property bool opened: wheel.opened

  Radial {
    id: wheel
    shell: root.shell
    pluginId: root.manifest ? String(root.manifest.id || "") : "aprabin98.vice-city-radial"
  }

  function open(payloadJson) { wheel.open(payloadJson) }
  function close() { wheel.close() }
  function toggle() { wheel.toggle() }
  function ping() { return "ok" }
  function status() { return wheel.status() }
}
