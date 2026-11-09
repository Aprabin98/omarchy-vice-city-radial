.pragma library

// Pure menu logic for the radial wheel: parsing Omarchy's JSONC menu files,
// merging the user's extension file, building the tree and searching it.
// Kept free of QML so it can be tested with plain node.

function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

// Raw {id: fields} map, or null when the text is not a menu (e.g. caught mid-write).
function parseRaw(text) {
  var stripped = stripJsonc(text)
  if (!stripped.trim()) return {}
  var parsed
  try { parsed = JSON.parse(stripped) } catch (e) { return null }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null
  var source = (parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items)) ? parsed.items : parsed
  var out = {}
  for (var id in source) {
    var entry = source[id]
    if (entry && typeof entry === "object" && !Array.isArray(entry)) out[id] = entry
  }
  return out
}

function asList(v) {
  if (Array.isArray(v)) return v.filter(function(x) { return x })
  return (typeof v === "string" && v) ? [v] : []
}

// Later maps override earlier ones field by field (same rule as Omarchy's menu).
function build(maps) {
  var merged = {}
  var order = []
  for (var m = 0; m < maps.length; m++) {
    var map = maps[m]
    if (!map) continue
    for (var id in map) {
      if (!(id in merged)) { merged[id] = {}; order.push(id) }
      merged[id] = Object.assign({}, merged[id], map[id])
    }
  }
  var items = {}
  var children = {}
  for (var i = 0; i < order.length; i++) {
    var key = order[i]
    var v = merged[key]
    var parent = v.parent
    if (parent === undefined) parent = key.indexOf(".") >= 0 ? key.split(".").slice(0, -1).join(".") : "root"
    if (key === "root") parent = ""
    items[key] = {
      id: key, parent: parent,
      kind: v.action ? "action" : (v.target ? "link" : "menu"),
      icon: v.icon || "", label: v.label || key, title: v.title || "",
      description: v.description || "", action: v.action || "", target: v.target || "",
      provider: v.provider || "", when: v.when || "",
      aliases: asList(v.aliases), searchTerms: asList(v.searchTerms)
    }
    if (parent) (children[parent] = children[parent] || []).push(key)
  }
  return { items: items, children: children, order: order }
}

// Ids whose `when` shell condition must be evaluated (flat [id, cmd, id, cmd...]).
function whenArgs(model) {
  var args = []
  for (var i = 0; i < model.order.length; i++) {
    var it = model.items[model.order[i]]
    if (it.when) { args.push(it.id); args.push(it.when) }
  }
  return args
}

function visible(model, id, pass) {
  var it = model.items[id]
  if (!it) return false
  return !it.when || !!(pass && pass[id])
}

// An item that only links elsewhere behaves as its target.
function resolve(model, id) {
  var it = model.items[id]
  var guard = 0
  while (it && it.kind === "link" && guard++ < 8) it = model.items[it.target]
  return it || null
}

function kids(model, id, pass) {
  var out = []
  var list = model.children[id] || []
  for (var i = 0; i < list.length; i++) {
    if (!visible(model, list[i], pass)) continue
    var it = model.items[list[i]]
    var real = resolve(model, list[i])
    if (!real) continue
    // Hide submenus that end up empty (all rows filtered out).
    if (it.kind !== "action" && !real.provider && !hasContent(model, real.id, pass, 0)) continue
    out.push(it)
  }
  return out
}

function hasContent(model, id, pass, depth) {
  if (depth > 8) return false
  var list = model.children[id] || []
  for (var i = 0; i < list.length; i++) {
    if (!visible(model, list[i], pass)) continue
    var real = resolve(model, list[i])
    if (!real) continue
    if (real.kind === "action" || real.provider) return true
    if (hasContent(model, real.id, pass, depth + 1)) return true
  }
  return false
}

// Does selecting this item open a deeper ring (true) or run something (false)?
function opensChildren(model, it, pass) {
  var real = resolve(model, it.id)
  if (!real) return false
  if (real.id === "apps") return true
  if (real.kind === "menu") return kids(model, real.id, pass).length > 0
  return false
}

function pathLabel(model, id) {
  var parts = []
  var cur = model.items[id]
  var guard = 0
  while (cur && cur.id !== "root" && guard++ < 10) {
    parts.unshift(cur.label)
    cur = model.items[cur.parent]
  }
  return parts.join(" \u203a ")
}

// Every runnable row in the whole tree, for search.
function leaves(model, pass) {
  var out = []
  for (var i = 0; i < model.order.length; i++) {
    var it = model.items[model.order[i]]
    if (it.id === "apps") continue
    if (!visible(model, it.id, pass)) continue
    var real = resolve(model, it.id)
    if (!real) continue
    if (real.kind !== "action" && !real.provider) continue
    // Skip rows hidden by a parent whose `when` failed.
    var ok = true
    var p = it.parent
    var g = 0
    while (p && p !== "root" && g++ < 10) {
      if (!visible(model, p, pass)) { ok = false; break }
      p = model.items[p] ? model.items[p].parent : ""
    }
    if (!ok) continue
    out.push({ it: it, real: real, path: pathLabel(model, it.id) })
  }
  return out
}

// 0 = no match. Prefix > word prefix > substring > path > fuzzy subsequence.
// Hyphens/underscores are ignored too, so "wifi" finds "Wi-Fi".
function score(q, text, path, extra) {
  if (!q) return 0
  var raw = String(text || "").toLowerCase()
  var forms = [raw, raw.replace(/[-_]/g, "")]
  var full = (String(path || "") + " " + String(extra || "")).toLowerCase()
  full += " " + full.replace(/[-_]/g, "")
  for (var f = 0; f < forms.length; f++) {
    var label = forms[f]
    if (label.indexOf(q) === 0) return 100 - Math.min(label.length, 40) / 10
    if (label.indexOf(" " + q) >= 0) return 80
    if (label.indexOf(q) >= 0) return 60
  }
  if (full.indexOf(q) >= 0) return 40
  var i = 0
  for (var k = 0; k < raw.length && i < q.length; k++) if (raw[k] === q[i]) i++
  return i === q.length && q.length > 2 ? 20 : 0
}

// Multi-word queries: every word must hit; score is the sum.
function scoreAll(query, text, path, extra) {
  var words = String(query).toLowerCase().trim().split(/\s+/).filter(function(w) { return w })
  if (!words.length) return 0
  var total = 0
  for (var i = 0; i < words.length; i++) {
    var s = score(words[i], text, path, extra)
    if (!s) return 0
    total += s
  }
  return total
}
