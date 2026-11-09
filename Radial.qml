//@ pragma AppId com.omarchy.OmarchyLauncher
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "menu.js" as Menu

// Omarchy Launcher: Omarchy's main menu as a Vice City style radial wheel.
//   inner ring = categories (or the siblings of the open submenu)
//   outer ring = children of the selected category (Enter/click opens it)
//   just type to search menu rows, installed apps and open windows.
Item {
  id: root

  // Omarchy shell plugin lifecycle (overlay kind). shell.qml and Overlay.qml
  // both instantiate this component; shell/pluginId stay unset when standalone.
  property var shell: null
  property string pluginId: ""
  property bool opened: false
  property bool hostClosing: false

  property string home: Quickshell.env("HOME")
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property string configPath: Quickshell.env("XDG_CONFIG_HOME")
    ? Quickshell.env("XDG_CONFIG_HOME") + "/omarchy-launcher/config.json"
    : home + "/.config/omarchy-launcher/config.json"
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy/extensions/omarchy-menu.jsonc"
  property string themePath: home + "/.local/state/omarchy/current/theme"
  property string userShellPath: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy/shell.toml"

  property var config: ({
    radius: 238, iconSize: 44, animationMs: 110, pageSize: 12,
    mouseNavigation: true, keyboardNavigation: true,
    iconFont: "JetBrainsMono Nerd Font",
    colors: {}
  })
  property var themeColors: ({ background: "#101315", foreground: "#f5efff", accent: "#b784ff", muted: "#81778f" })
  property var themeShellValues: ({})
  property var userShellValues: ({})
  property int themeRevision: 0
  readonly property var colors: config.colors || ({})
  readonly property string textColor: colors.text || themeColorValue("launcher.text", themeColors.foreground)
  readonly property string accentColor: colors.purple || themeColorValue("launcher.selected-text", themeColors.accent)
  readonly property string glowColor: colors.pink || themeColorValue("launcher.selected-text", themeColors.accent)
  readonly property string mutedColor: colors.muted || themeColors.muted || textColor
  readonly property string backgroundColor: colors.background || themeColorValue("launcher.background", themeColors.background)
  readonly property string selectedBackgroundColor: colors.selectedBackground || themeColorValue("launcher.selected-background", themeColors.foreground)
  readonly property string selectedTextColor: colors.selectedText || themeColorValue("launcher.selected-text", themeColors.accent)
  readonly property string borderColor: colors.border || themeColorValue("launcher.border", themeColors.foreground)
  readonly property real backgroundAlpha: colors.backgroundAlpha !== undefined
    ? Math.max(0, Math.min(1, Number(colors.backgroundAlpha))) : 0.5
  readonly property real selectedBackgroundAlpha: colorAlpha("launcher.selected-background-alpha", 0.12)
  readonly property real borderAlpha: colorAlpha("launcher.border-alpha", 0.25)

  // Menu data
  property var defaultRaw: null
  property var userRaw: null
  property var menu: Menu.build([])
  property var whenPass: ({})
  property var leafCache: []
  property var searchCache: []

  // Wheel state
  property var path: []                // ids of opened menus, outermost last
  property string query: ""
  property string activeRing: "inner"
  property int innerIndex: 0
  property int outerIndex: 0
  property int openIndex: -1           // inner slot whose submenu is open
  property var innerItems: []
  property var outerItems: []
  property var outerView: []           // current page of outerItems
  property int outerPage: 0
  property int rev: 0
  property bool closing: false
  readonly property bool searching: query.trim().length > 0

  readonly property var allApps: DesktopEntries.applications.values || []
  readonly property var allWindows: Hyprland.toplevels.values || []
  readonly property var focusedScreen: {
    const screens = Quickshell.screens
    const focused = Hyprland.focusedMonitor
    if (focused) {
      for (let i = 0; i < screens.length; i++) {
        if (Hyprland.monitorFor(screens[i]) === focused) return screens[i]
      }
    }
    return screens.length ? screens[0] : null
  }

  // ---------- apps & windows ----------
  function appName(app) { return String(app.name || app.id || "") }
  function appKey(app) { return String(app.id || "").replace(/\.desktop$/i, "") }
  function appSearchText(app) {
    return [app.name, app.genericName, app.comment, app.id,
            app.keywords ? app.keywords.join(" ") : ""].join(" ").toLocaleLowerCase()
  }
  function sortedApps() {
    return Array.from(allApps).filter(function(app) {
      return app && !app.noDisplay && appName(app).length > 0 && app.command && app.command.length > 0
    }).sort(function(a, b) { return appName(a).localeCompare(appName(b)) })
  }
  function iconForApp(app) {
    const icon = String(app && app.icon || "application-x-executable")
    if (icon.indexOf("/") === 0) return "file://" + icon
    if (icon.indexOf("file:") === 0 || icon.indexOf("image:") === 0) return icon
    return Quickshell.iconPath(icon, true) || Quickshell.iconPath("application-x-executable")
  }
  function windowAppId(win) { return String(win && win.wayland ? win.wayland.appId : "") }
  function windowTitle(win) { return String(win && (win.title || (win.wayland && win.wayland.title)) || "") }
  function windowWorkspace(win) { return win && win.workspace ? String(win.workspace.name || win.workspace.id) : "?" }
  function iconForWindow(win) {
    const appId = windowAppId(win).toLocaleLowerCase()
    const app = allApps.find(function(item) {
      const key = appKey(item).toLocaleLowerCase()
      const startup = String(item.startupClass || "").toLocaleLowerCase()
      return (key && (appId === key || appId.indexOf(key) >= 0)) || (startup && appId === startup)
    })
    return app ? iconForApp(app) : Quickshell.iconPath("application-x-executable")
  }
  function imageFor(entry) {
    if (!entry) return ""
    if (entry.type === "app") return iconForApp(entry.app)
    if (entry.type === "win") return iconForWindow(entry.win)
    return ""
  }

  // ---------- entries ----------
  function entryFromItem(it) { return { type: "item", id: it.id, label: it.label, icon: it.icon, sub: it.description, item: it } }
  function entryFromApp(app, sub) { return { type: "app", id: appKey(app), label: appName(app), icon: "", sub: sub || "", app: app } }
  function entryFromWin(win) {
    return { type: "win", id: "win:" + windowAppId(win) + windowTitle(win), label: windowTitle(win), icon: "",
             sub: "Window \u00b7 workspace " + windowWorkspace(win), win: win }
  }
  function entryForId(id) { const it = menu.items[id]; return it ? entryFromItem(it) : null }
  function opens(e) { return !!e && e.type === "item" && Menu.opensChildren(menu, e.item, whenPass) }
  function rootEntries() { return Menu.kids(menu, "root", whenPass).map(entryFromItem) }
  function childrenOf(e) {
    if (!e || e.type !== "item") return []
    const real = Menu.resolve(menu, e.id)
    if (!real) return []
    if (real.id === "apps") return sortedApps().map(function(a) { return entryFromApp(a, "") })
    return Menu.kids(menu, real.id, whenPass).map(entryFromItem)
  }
  // Keep the same array when nothing changed, so ring delegates (and their
  // selection animations) are not rebuilt on every key press.
  function sameEntries(a, b) {
    if (a.length !== b.length) return false
    for (let i = 0; i < a.length; i++) if (a[i].id !== b[i].id || a[i].type !== b[i].type) return false
    return true
  }
  function indexOfId(list, id) {
    for (let i = 0; i < list.length; i++) if (list[i].id === id) return i
    return -1
  }

  // ---------- search ----------
  // Results are grouped by source so every query ranks apps first, then open
  // windows, then app settings/management, then the rest of the system. Match
  // quality still orders entries inside each group, and fuzzy-only matches
  // never outrank a direct match, so an unrelated fuzzy hit cannot jump ahead
  // of an exact result such as "Lock".
  function searchBand(s) { return s > 20 ? 0 : 1 }
  function searchTier(e) {
    if (!e) return 3
    if (e.type === "app") return 0
    if (e.type === "win") return 1
    const category = String(e.id || "").split(".")[0]
    if (category === "setup" || category === "install" || category === "remove") return 2
    return 3
  }
  function updateSearch() {
    const q = query.trim()
    if (!q) { searchCache = []; return }
    const scored = []
    for (let i = 0; i < leafCache.length; i++) {
      const l = leafCache[i]
      const extra = l.it.description + " " + l.it.aliases.join(" ") + " " + l.it.searchTerms.join(" ")
      const s = Menu.scoreAll(q, l.it.label, l.path, extra)
      if (s) { const e = entryFromItem(l.it); e.sub = l.path; scored.push({ s: s, e: e }) }
    }
    const apps = sortedApps()
    for (let i = 0; i < apps.length; i++) {
      const s = Menu.scoreAll(q, appName(apps[i]), "", appSearchText(apps[i]))
      if (s) scored.push({ s: s, e: entryFromApp(apps[i], "App") })
    }
    const wins = Array.from(allWindows)
    for (let i = 0; i < wins.length; i++) {
      const win = wins[i]
      if (!win || !win.wayland || !windowTitle(win).length) continue
      if (windowAppId(win).toLocaleLowerCase().indexOf("omarchylauncher") >= 0) continue
      const s = Menu.scoreAll(q, windowTitle(win), windowAppId(win), "")
      if (s) scored.push({ s: s, e: entryFromWin(win) })
    }
    scored.sort(function(a, b) {
      const ba = searchBand(a.s), bb = searchBand(b.s)
      if (ba !== bb) return ba - bb
      const ta = searchTier(a.e), tb = searchTier(b.e)
      if (ta !== tb) return ta - tb
      return b.s - a.s
    })
    searchCache = scored.slice(0, 60).map(function(x) { return x.e })
  }

  // ---------- state ----------
  function pageSize() { return Math.max(4, Number(config.pageSize) || 12) }
  function wheelOuter() { return Math.min(Number(config.radius) || 238, Math.min(overlay.width, overlay.height) * 0.38) }
  function touch() { rev = rev + 1 }

  function refresh() {
    const newInner = path.length > 1 ? childrenOf(entryForId(path[path.length - 2])) : rootEntries()
    const newOuter = searching ? searchCache : (path.length ? childrenOf(entryForId(path[path.length - 1])) : [])
    if (!sameEntries(innerItems, newInner)) innerItems = newInner
    if (!sameEntries(outerItems, newOuter)) outerItems = newOuter
    if (innerIndex >= innerItems.length) innerIndex = Math.max(0, innerItems.length - 1)
    if (outerIndex >= outerItems.length) outerIndex = Math.max(0, outerItems.length - 1)
    const ps = pageSize()
    outerPage = Math.floor(outerIndex / ps)
    const newView = outerItems.slice(outerPage * ps, outerPage * ps + ps)
    if (!sameEntries(outerView, newView)) outerView = newView
    openIndex = path.length && !searching ? indexOfId(innerItems, path[path.length - 1]) : -1
    touch()
  }
  function rebuildModel() {
    menu = Menu.build([defaultRaw, userRaw])
    runWhen()
    afterWhen()
  }
  function afterWhen() {
    leafCache = Menu.leaves(menu, whenPass)
    updateSearch()
    refresh()
  }
  function runWhen() {
    const args = Menu.whenArgs(menu)
    if (!args.length || whenProc.running) return
    whenProc.collected = ({})
    whenProc.command = ["bash", "-c",
      'export PATH="$HOME/.local/share/omarchy/bin:$PATH"; while [ "$#" -gt 1 ]; do id="$1"; cond="$2"; shift 2; if bash -c "$cond" >/dev/null 2>&1; then printf "%s\\n" "$id"; fi; done',
      "_"].concat(args)
    whenProc.running = true
  }
  function selectedEntry() {
    if (activeRing === "outer" || searching) return outerItems[outerIndex] || null
    return innerItems[innerIndex] || null
  }

  // ---------- actions ----------
  function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  function sh(cmd) {
    Quickshell.execDetached(["bash", "-c", 'export PATH="$HOME/.local/share/omarchy/bin:$PATH"; ' + cmd])
  }
  function launchApp(app) {
    if (!app) return
    let id = appKey(app)
    if (id.slice(-8) !== ".desktop") id += ".desktop"
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id])
    closeLauncher()
  }
  function activateWindow(win) {
    if (!win || !win.wayland) return
    win.wayland.activate()
    closeLauncher()
  }
  function runItem(it) {
    if (!it) return
    // Rows with a plain action run it; provider rows (fonts, languages, kernels)
    // are generated by Omarchy's own menu, so hand those over to it.
    if (it.action && it.id !== "apps") sh(it.action)
    else sh("omarchy-menu summon " + shq(it.id))
    closeLauncher()
  }
  function run(e) {
    if (!e) return
    if (e.type === "app") launchApp(e.app)
    else if (e.type === "win") activateWindow(e.win)
    else runItem(Menu.resolve(menu, e.id))
  }

  function submit() {
    const e = selectedEntry()
    if (!e) return
    if (searching || !opens(e)) { run(e); return }
    if (activeRing === "inner") path = path.slice(0, Math.max(0, path.length - 1)).concat([e.id])
    else path = path.concat([e.id])
    outerIndex = 0
    refresh()
    innerIndex = Math.max(0, indexOfId(innerItems, e.id))
    activeRing = "outer"
    touch()
  }
  function back() {
    if (!path.length) return false
    const popped = path[path.length - 1]
    path = path.slice(0, -1)
    outerIndex = 0
    refresh()
    if (!path.length) {
      innerIndex = Math.max(0, indexOfId(innerItems, popped))
      activeRing = "inner"
    } else {
      activeRing = "outer"
      outerIndex = Math.max(0, indexOfId(outerItems, popped))
      refresh()
      innerIndex = Math.max(0, indexOfId(innerItems, path[path.length - 1]))
    }
    touch()
    return true
  }
  function clearOrBack() {
    if (query.length) { query = ""; updateSearch(); refresh() }
    else if (!back()) closeLauncher()
  }
  function cycle(d) {
    if ((activeRing === "outer" || searching) && outerItems.length) {
      outerIndex = (outerIndex + d + outerItems.length) % outerItems.length
      refresh()
    } else if (innerItems.length && !searching) {
      activeRing = "inner"
      innerIndex = (innerIndex + d + innerItems.length) % innerItems.length
      touch()
    }
  }
  function page(d) {
    if (!outerItems.length) return
    const ps = pageSize()
    outerIndex = Math.max(0, Math.min(outerItems.length - 1, outerIndex + d * ps))
    refresh()
  }
  function pickSlot(i) {
    if ((activeRing === "outer" || searching) && outerItems.length) {
      const target = outerPage * pageSize() + i
      if (target < outerItems.length) { outerIndex = target; refresh() }
    } else if (i < innerItems.length) {
      innerIndex = i
      touch()
    }
  }
  function slotAt(angle, count) {
    return Math.round(angle * count / (Math.PI * 2)) % count
  }
  function selectAt(x, y, force) {
    if (!config.mouseNavigation && !force) return false
    const dx = x - overlay.width / 2, dy = y - overlay.height / 2
    const distance = Math.sqrt(dx * dx + dy * dy)
    const R = wheelOuter()
    const outerInner = R * 0.64
    const innerOuter = outerInner - Math.max(7, R * 0.035)
    const innerInner = R * 0.22
    const angle = (Math.atan2(dy, dx) + Math.PI / 2 + Math.PI * 2) % (Math.PI * 2)
    if (distance >= innerInner && distance <= innerOuter) {
      if (searching || !innerItems.length) return false
      activeRing = "inner"
      innerIndex = slotAt(angle, innerItems.length)
    } else if (distance >= outerInner && distance <= R + 10) {
      if (!outerView.length) return false
      activeRing = "outer"
      outerIndex = outerPage * pageSize() + slotAt(angle, outerView.length)
    } else return false
    touch()
    return true
  }

  // ---------- open / close ----------
  function openLauncher() {
    hostClosing = false
    closing = false
    query = ""
    path = []
    innerIndex = 0
    outerIndex = 0
    activeRing = "inner"
    updateSearch()
    runWhen()
    refresh()
    opened = true
    keyFocus.opacity = 0
    Qt.callLater(function() {
      keyFocus.forceActiveFocus()
      keyFocus.opacity = 1
    })
  }
  function closeLauncher() {
    if (!opened || closing) return
    closing = true
    keyFocus.opacity = 0
    closeDelay.restart()
  }
  function toggleLauncher() {
    if (opened) dismiss()
    else open("{}")
  }
  function open(payloadJson) {
    hostClosing = false
    openLauncher()
  }
  function close() {
    hostClosing = true
    closeLauncher()
  }
  function dismiss() {
    hostClosing = false
    closeLauncher()
  }
  function toggle() {
    if (opened) dismiss()
    else open("{}")
  }
  function notifyHostHidden() {
    if (shell && typeof shell.hide === "function" && pluginId.length)
      shell.hide(pluginId)
  }
  function status() {
    return JSON.stringify({ visible: opened, query: root.query, path: root.path,
      inner: root.innerItems.length, outer: root.outerItems.length, ring: root.activeRing })
  }

  function parseThemeColors(raw) {
    const parsed = Object.assign({}, themeColors)
    const lines = String(raw || "").split("\n")
    for (let i = 0; i < lines.length; i++) {
      const match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) parsed[match[1]] = match[2]
    }
    return parsed
  }
  function parseShellColors(raw) {
    const parsed = ({})
    const lines = String(raw || "").split("\n")
    let section = ""
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      const sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]/)
      if (sectionMatch) { section = sectionMatch[1]; continue }
      const match = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^#\s]+))/)
      if (match && section) parsed[section + "." + match[1]] = match[2] || match[3] || match[4]
    }
    return parsed
  }
  function themeColorValue(key, fallback) {
    let value = userShellValues[key] || themeShellValues[key] || fallback
    for (let i = 0; i < 6; i++) {
      const token = String(value || "").trim().split(/\s+/)[0]
      if (/^#[0-9a-fA-F]{6,8}$/.test(token)) return token
      if (themeColors[token]) return themeColors[token]
      const next = userShellValues[token] || themeShellValues[token]
      if (!next) break
      value = next
    }
    return fallback
  }
  function colorAlpha(key, fallback) {
    const value = Number(userShellValues[key] !== undefined ? userShellValues[key] : themeShellValues[key])
    return isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback
  }
  function alphaColor(value, alpha) {
    const c = Qt.color(value)
    return Qt.rgba(c.r, c.g, c.b, Math.max(0, Math.min(1, alpha)))
  }
  function oppositeThemeBackground() {
    const c = Qt.color(backgroundColor)
    return Qt.rgba(1 - c.r, 1 - c.g, 1 - c.b, 0.5)
  }
  function canvasColor(value, alpha) {
    const c = Qt.color(value)
    return "rgba(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ", " + Math.max(0, Math.min(1, alpha)) + ")"
  }
  function loadThemeColors(raw) {
    themeColors = parseThemeColors(raw)
    themeRevision++
  }
  function loadThemeShell(raw) {
    themeShellValues = parseShellColors(raw)
    themeRevision++
  }
  function loadUserShell(raw) {
    userShellValues = parseShellColors(raw)
    themeRevision++
  }

  // ---------- config & menu files ----------
  function readConfig(text) {
    try {
      const value = JSON.parse(text)
      if (value && typeof value === "object") config = Object.assign({}, config, value)
    } catch (error) {
      console.warn("Omarchy Launcher: config could not be parsed:", error)
    }
  }
  FileView {
    path: root.themePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeColors(text())
    onFileChanged: reload()
  }
  FileView {
    path: root.themePath + "/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeShell(text())
    onFileChanged: reload()
  }
  FileView {
    path: root.userShellPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadUserShell(text())
    onFileChanged: reload()
    onLoadFailed: root.loadUserShell("")
  }
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.readConfig(text())
    onFileChanged: reload()
  }
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { const raw = Menu.parseRaw(text()); if (raw) { root.defaultRaw = raw; root.rebuildModel() } }
    onFileChanged: reload()
  }
  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { const raw = Menu.parseRaw(text()); if (raw) { root.userRaw = raw; root.rebuildModel() } }
    onFileChanged: reload()
  }

  Process {
    id: whenProc
    property var collected: ({})
    stdout: SplitParser {
      onRead: function(line) { whenProc.collected[String(line).trim()] = true }
    }
    onExited: {
      root.whenPass = whenProc.collected
      root.afterWhen()
    }
  }

  IpcHandler {
    target: "omarchy-launcher"
    function toggle(): string { root.toggle(); return "ok" }
    function show(): string { root.open("{}"); return root.opened ? "visible" : "hidden" }
    function hide(): string { root.dismiss(); return "ok" }
    function ping(): string { return "ok" }
    function status(): string { return root.status() }
  }

  Timer {
    id: closeDelay
    interval: Number(root.config.animationMs) || 110
    onTriggered: {
      opened = false
      root.closing = false
      if (!root.hostClosing) root.notifyHostHidden()
      root.hostClosing = false
    }
  }

  PanelWindow {
    id: overlay
    screen: root.focusedScreen
    visible: root.opened
    color: "transparent"
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    surfaceFormat.opaque: false

    Item {
      id: keyFocus
      anchors.fill: parent
      focus: true
      opacity: 1
      Behavior on opacity { NumberAnimation { duration: Number(root.config.animationMs) || 110; easing.type: Easing.OutCubic } }

      // A half-opacity inverse of the theme background keeps the wheel in focus.
      Rectangle {
        anchors.fill: parent
        color: root.oppositeThemeBackground()
      }

      Keys.onPressed: function(event) {
        if (!root.config.keyboardNavigation) return
        const k = event.key
        if (k === Qt.Key_Escape) {
          root.clearOrBack()
        } else if (k === Qt.Key_Backspace) {
          if (root.query.length) {
            root.query = root.query.slice(0, -1)
            root.outerIndex = 0
            root.updateSearch()
            root.refresh()
          } else root.back()
        } else if (k === Qt.Key_Tab) {
          if (!root.searching) {
            if (root.activeRing === "inner" && root.outerItems.length) root.activeRing = "outer"
            else root.activeRing = "inner"
            root.touch()
          }
        } else if (k === Qt.Key_Left || k === Qt.Key_Up) {
          root.cycle(-1)
        } else if (k === Qt.Key_Right || k === Qt.Key_Down) {
          root.cycle(1)
        } else if (k === Qt.Key_PageUp) {
          root.page(-1)
        } else if (k === Qt.Key_PageDown) {
          root.page(1)
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
          root.pickSlot(k === Qt.Key_0 ? 9 : k - Qt.Key_1)
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_Space && !root.query.length)) {
          root.submit()
        } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && event.text.length) {
          const ch = event.text
          if (ch.trim().length || (ch === " " && root.query.length)) {
            root.query += ch
            root.outerIndex = 0
            root.activeRing = "outer"
            root.updateSearch()
            root.refresh()
          }
        } else return
        event.accepted = true
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onPositionChanged: function(mouse) { root.selectAt(mouse.x, mouse.y) }
        onClicked: function(mouse) {
          const R = root.wheelOuter()
          const distance = Math.hypot(mouse.x - overlay.width / 2, mouse.y - overlay.height / 2)
          if (distance > R + 16) root.closeLauncher()
          else if (distance < R * 0.22) root.clearOrBack()
          else if (root.selectAt(mouse.x, mouse.y, true)) root.submit()
        }
      }

      Canvas {
        id: wheel
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        property string refreshToken: [root.rev, root.themeRevision, root.query, root.activeRing, root.innerIndex, root.outerIndex, root.path.length].join(":")
        onRefreshTokenChanged: requestPaint()
        Component.onCompleted: requestPaint()

        function drawRing(ctx, count, inner, outer, index, accent, enabled, openAt, faded) {
          if (!count) return
          const cx = width / 2, cy = height / 2
          const outerR = Math.max(0, Math.min(outer, cx, cy))
          const innerR = Math.max(0, Math.min(inner, outerR))
          if (outerR <= 0) return
          const step = Math.PI * 2 / count
          const gap = Math.min(0.075, step * 0.15)
          ctx.globalAlpha = faded ? 0.45 : 1
          for (let i = 0; i < count; i++) {
            const angle = -Math.PI / 2 + step * i
            const start = angle - step / 2 + gap
            const end = angle + step / 2 - gap
            ctx.beginPath()
            ctx.arc(cx, cy, outerR, start, end)
            ctx.lineTo(cx + Math.cos(end) * innerR, cy + Math.sin(end) * innerR)
            ctx.arc(cx, cy, innerR, end, start, true)
            ctx.closePath()
            const selected = enabled && i === index
            const fill = ctx.createLinearGradient(cx, cy - innerR, cx, cy - outerR)
            fill.addColorStop(0, root.canvasColor(selected ? root.selectedBackgroundColor : root.backgroundColor, selected ? Math.min(1, root.selectedBackgroundAlpha + 0.08) : root.backgroundAlpha))
            fill.addColorStop(1, root.canvasColor(selected ? root.selectedBackgroundColor : root.backgroundColor, selected ? Math.min(1, root.selectedBackgroundAlpha + 0.04) : Math.max(0, root.backgroundAlpha - 0.04)))
            ctx.fillStyle = fill
            ctx.fill()
            ctx.strokeStyle = selected ? accent : (i === openAt ? root.glowColor : root.canvasColor(root.borderColor, root.borderAlpha * 0.35))
            ctx.lineWidth = selected ? 1.8 : (i === openAt ? 1.4 : 0.8)
            ctx.stroke()
            if (selected || i === openAt) {
              ctx.beginPath()
              ctx.arc(cx, cy, Math.max(0.5, outerR - 1), start, end)
              ctx.strokeStyle = selected ? accent : root.glowColor
              ctx.globalAlpha = selected ? 0.55 : 0.4
              ctx.lineWidth = 2.8
              ctx.stroke()
              ctx.globalAlpha = faded ? 0.45 : 1
            }
          }
          ctx.globalAlpha = 1
        }

        onPaint: {
          if (width <= 0 || height <= 0) return
          const ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          const cx = width / 2, cy = height / 2
          const R = Math.min(Number(root.config.radius) || 238, Math.min(width, height) * 0.38)
          const outerInner = R * 0.64
          const innerOuter = outerInner - Math.max(7, R * 0.035)
          const innerInner = R * 0.22
          const accent = root.accentColor
          drawRing(ctx, root.innerItems.length, innerInner, innerOuter, root.innerIndex, accent,
                   root.activeRing === "inner" && !root.searching, root.openIndex, root.searching)
          drawRing(ctx, root.outerView.length, outerInner, R, root.outerIndex - root.outerPage * root.pageSize(), accent,
                   root.activeRing === "outer" || root.searching, -1, false)
          ctx.beginPath(); ctx.arc(cx, cy, Math.max(1, innerInner - 6), 0, Math.PI * 2)
          const centerFill = ctx.createRadialGradient(cx - 20, cy - 24, 2, cx, cy, innerInner)
          centerFill.addColorStop(0, root.canvasColor(root.backgroundColor, root.backgroundAlpha))
          centerFill.addColorStop(1, root.canvasColor(root.backgroundColor, Math.max(0, root.backgroundAlpha - 0.08)))
          ctx.fillStyle = centerFill; ctx.fill()
          ctx.strokeStyle = root.canvasColor(root.borderColor, root.borderAlpha); ctx.lineWidth = 1; ctx.stroke()
          if (root.outerView.length) {
            ctx.beginPath(); ctx.arc(cx, cy, R + 9, 0, Math.PI * 2)
            ctx.strokeStyle = root.canvasColor(root.borderColor, root.borderAlpha * 0.8); ctx.lineWidth = 1; ctx.stroke()
          }
        }
      }

      // Inner ring
      Repeater {
        model: root.innerItems
        delegate: Slot {
          required property int index
          required property var modelData
          readonly property real ringRadius: root.wheelOuter()
          readonly property real ringIn: ringRadius * 0.22
          readonly property real ringOut: ringRadius * 0.64 - Math.max(7, ringRadius * 0.035)
          readonly property real mid: (ringIn + ringOut) / 2 - 7
          readonly property real arc: mid * Math.PI * 2 / Math.max(1, root.innerItems.length)
          readonly property real angle: -Math.PI / 2 + Math.PI * 2 * index / Math.max(1, root.innerItems.length)
          readonly property real labelTextHeight: 28
          readonly property real labelRadius: mid + size / 2 + labelTextHeight / 2 + 2
          entry: modelData
          size: Math.min(Number(root.config.iconSize) * 0.9, (ringOut - ringIn) * 0.42, arc * 0.6)
          labelWidth: Math.min(arc * 0.84, 92)
          labelHeight: labelTextHeight
          labelOffsetX: Math.cos(angle) * (labelRadius - mid) + size / 2 - labelWidth / 2
          labelOffsetY: Math.sin(angle) * (labelRadius - mid) + size / 2 - labelHeight / 2
          textColor: root.textColor
          selectedTextColor: root.selectedTextColor
          accent: root.glowColor
          iconFont: root.config.iconFont || "JetBrainsMono Nerd Font"
          imageSource: root.imageFor(modelData)
          selected: root.activeRing === "inner" && !root.searching && index === root.innerIndex
          dim: root.searching
          x: overlay.width / 2 + Math.cos(angle) * mid - size / 2
          y: overlay.height / 2 + Math.sin(angle) * mid - size / 2
        }
      }

      // Outer ring (current page)
      Repeater {
        model: root.outerView
        delegate: Slot {
          required property int index
          required property var modelData
          readonly property real ringRadius: root.wheelOuter()
          readonly property real ringIn: ringRadius * 0.64
          readonly property real mid: (ringIn + ringRadius) / 2 - 7
          readonly property real arc: mid * Math.PI * 2 / Math.max(1, root.outerView.length)
          readonly property real angle: -Math.PI / 2 + Math.PI * 2 * index / Math.max(1, root.outerView.length)
          entry: modelData
          size: Math.min(Number(root.config.iconSize), (ringRadius - ringIn) * 0.46, arc * 0.6)
          labelWidth: Math.min(arc * 0.84, 100)
          textColor: root.textColor
          selectedTextColor: root.selectedTextColor
          accent: root.glowColor
          iconFont: root.config.iconFont || "JetBrainsMono Nerd Font"
          imageSource: root.imageFor(modelData)
          selected: (root.activeRing === "outer" || root.searching) && index === root.outerIndex - root.outerPage * root.pageSize()
          x: overlay.width / 2 + Math.cos(angle) * mid - size / 2
          y: overlay.height / 2 + Math.sin(angle) * mid - size / 2
        }
      }

      // Center glyph
      Text {
        anchors.centerIn: parent
        text: root.searching ? "\u2315"
          : (root.path.length && root.menu.items[root.path[root.path.length - 1]]
             ? root.menu.items[root.path[root.path.length - 1]].icon : "\u25c8")
        font.family: root.config.iconFont || "JetBrainsMono Nerd Font"
        font.pixelSize: 30
        color: root.textColor
        opacity: 0.9
      }

      // Status pill under the wheel: breadcrumb or live search text, selected item, hints
      Rectangle {
        readonly property real ringRadius: root.wheelOuter()
        width: 380
        height: pill.implicitHeight + 18
        radius: 12
        x: overlay.width / 2 - width / 2
        y: overlay.height / 2 + ringRadius + 26
        color: root.alphaColor(root.backgroundColor, root.backgroundAlpha)
        border.color: root.alphaColor(root.borderColor, root.borderAlpha)
        border.width: 1
        Column {
          id: pill
          anchors.centerIn: parent
          width: parent.width - 24
          spacing: 3
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideLeft
            font.pixelSize: 14
            font.bold: true
            color: root.searching ? root.glowColor : root.textColor
            text: {
              if (root.searching) return "\u2315  " + root.query + "\u258f"
              if (!root.path.length) return "Omarchy"
              return root.path.map(function(id) { return root.menu.items[id] ? root.menu.items[id].label : id }).join("  \u203a  ")
            }
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: 12
            color: root.textColor
            text: {
              const e = root.selectedEntry()
              if (root.searching && !root.outerItems.length) return "No results"
              if (!e) return ""
              return e.label + (e.sub ? "  \u00b7  " + e.sub : "")
            }
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 10
            color: root.mutedColor
            text: "\u21b5 open   esc back   tab ring   pgup/pgdn page"
                  + (root.outerItems.length > root.pageSize()
                     ? "   \u00b7   " + (root.outerPage + 1) + "/" + Math.ceil(root.outerItems.length / root.pageSize()) : "")
          }
        }
      }
    }
  }
}
