var PLUGIN_ID = "io.github.luccast.frigate"
var DEFAULT_URL = "http://127.0.0.1:5000"
var SEEN_LIMIT = 200

function normalizeUrl(url) {
  var value = String(url || "").replace(/^\s+|\s+$/g, "").replace(/\/+$/, "")
  return value || DEFAULT_URL
}

function pluginSettings(config, id) {
  var key = String(id || PLUGIN_ID)
  var empty = { url: DEFAULT_URL, username: "", refreshSeconds: 2 }
  if (!config || typeof config !== "object") return empty

  function fromEntry(entry) {
    if (!entry || typeof entry !== "object") return null
    if (String(entry.id || "") !== key) return null
    return {
      url: normalizeUrl(entry.url),
      username: String(entry.username || ""),
      refreshSeconds: Math.max(1, parseInt(entry.refreshSeconds, 10) || 2)
    }
  }

  var bar = config.bar && config.bar.layout ? config.bar.layout : {}
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = bar[sections[s]] || []
    for (var i = 0; i < entries.length; i++) {
      var found = fromEntry(entries[i])
      if (found) return found
    }
  }

  var plugins = config.plugins || []
  for (var p = 0; p < plugins.length; p++) {
    var plugin = fromEntry(plugins[p])
    if (plugin) return plugin
  }
  return empty
}

function parsePasswordFile(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return data && typeof data.password === "string" ? data.password : ""
  } catch (e) {
    return ""
  }
}

function serializePasswordFile(password) {
  return JSON.stringify({ password: String(password || "") }) + "\n"
}

function parseSeenFile(raw) {
  try {
    var data = JSON.parse(String(raw || "[]"))
    return Array.isArray(data) ? data.map(String) : []
  } catch (e) {
    return []
  }
}

function serializeSeenFile(ids) {
  var list = Array.isArray(ids) ? ids.map(String) : []
  if (list.length > SEEN_LIMIT) list = list.slice(list.length - SEEN_LIMIT)
  return JSON.stringify(list) + "\n"
}

function parseConfig(raw) {
  var empty = { notificationsEnabled: true, cameras: [] }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return empty
    var globalNotify = !(data.notifications && data.notifications.enabled === false)
    var cameras = []
    var source = data.cameras && typeof data.cameras === "object" ? data.cameras : {}
    for (var name in source) {
      if (!Object.prototype.hasOwnProperty.call(source, name)) continue
      var camera = source[name] || {}
      var notify = camera.notifications || {}
      cameras.push({
        name: String(name),
        enabled: camera.enabled !== false,
        notifyEnabled: notify.enabled !== false,
        notifySuspendedUntil: Number(notify.suspended || 0) || 0
      })
    }
    cameras.sort(function(a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0 })
    return { notificationsEnabled: globalNotify, cameras: cameras }
  } catch (e) {
    return empty
  }
}

function parseReviews(raw) {
  try {
    var data = JSON.parse(String(raw || "[]"))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function cameraAllowed(configState, cameraName) {
  if (!configState || configState.notificationsEnabled === false) return false
  var cameras = configState.cameras || []
  for (var i = 0; i < cameras.length; i++) {
    if (cameras[i].name !== cameraName) continue
    if (cameras[i].notifyEnabled === false) return false
    if (cameras[i].notifySuspendedUntil && cameras[i].notifySuspendedUntil > Date.now() / 1000)
      return false
    return true
  }
  return true
}

function shouldNotify(review, configState, seen) {
  if (!review || review.severity !== "alert" || !review.id) return false
  if (seen && seen.indexOf(String(review.id)) !== -1) return false
  return cameraAllowed(configState, String(review.camera || ""))
}

function reviewObjects(review) {
  var data = review && review.data ? review.data : {}
  var objects = data.objects || []
  return objects.length ? objects.join(", ") : "activity"
}

function reviewZones(review) {
  var data = review && review.data ? review.data : {}
  var zones = data.zones || []
  return zones.length ? zones.join(", ") : ""
}

function toastBody(review) {
  var objects = reviewObjects(review)
  var zones = reviewZones(review)
  return zones ? objects + " · " + zones : objects
}

function firstDetectionId(review) {
  var data = review && review.data ? review.data : {}
  var detections = data.detections || []
  return detections.length ? String(detections[0]) : ""
}

function parseLoginResponse(raw) {
  var text = String(raw || "")
  var cookie = text.match(/set-cookie:\s*[^=]+=([^;\r\n]+)/i)
  if (cookie && cookie[1]) {
    try { return decodeURIComponent(cookie[1]) } catch (e) { return cookie[1] }
  }
  var start = text.indexOf("{")
  if (start === -1) return ""
  try {
    var data = JSON.parse(text.slice(start))
    return String(data.token || data.access_token || "")
  } catch (e) {
    return ""
  }
}

function latestUrl(base, camera) {
  return normalizeUrl(base) + "/api/" + encodeURIComponent(String(camera || "")) + "/latest.jpg"
}

function snapshotUrl(base, eventId) {
  return normalizeUrl(base) + "/api/events/" + encodeURIComponent(String(eventId || "")) + "/snapshot.jpg"
}

function reviewUrl(base) {
  return normalizeUrl(base) + "/api/review?severity=alert&limit=20"
}

function configUrl(base) {
  return normalizeUrl(base) + "/api/config"
}

function loginUrl(base) {
  return normalizeUrl(base) + "/api/login"
}

function loginBody(username, password) {
  return JSON.stringify({ user: String(username || ""), password: String(password || "") })
}

function rememberIds(seen, ids) {
  var next = Array.isArray(seen) ? seen.slice() : []
  var incoming = Array.isArray(ids) ? ids : []
  for (var i = 0; i < incoming.length; i++) {
    var id = String(incoming[i] || "")
    if (!id || next.indexOf(id) !== -1) continue
    next.push(id)
  }
  if (next.length > SEEN_LIMIT) next = next.slice(next.length - SEEN_LIMIT)
  return next
}

if (typeof Qt === "undefined") {
  var fails = 0
  function assert(cond, msg) {
    if (!cond) {
      fails += 1
      console.error("fail:", msg)
    }
  }

  assert(normalizeUrl(" http://cam:5000/ ") === "http://cam:5000", "normalizeUrl")
  assert(pluginSettings({
    bar: { layout: { right: [{ id: PLUGIN_ID, url: "http://nvr:8971", username: "admin" }] } }
  }).username === "admin", "pluginSettings")
  assert(parsePasswordFile('{"password":"secret"}') === "secret", "password")
  assert(parseConfig('{"notifications":{"enabled":false},"cameras":{"gate":{}}}').notificationsEnabled === false, "config notify")
  assert(shouldNotify({ id: "a", severity: "alert", camera: "gate" }, { notificationsEnabled: true, cameras: [] }, []) === true, "new alert")
  assert(shouldNotify({ id: "a", severity: "alert", camera: "gate" }, { notificationsEnabled: true, cameras: [] }, ["a"]) === false, "seen alert")
  assert(shouldNotify({ id: "a", severity: "detection", camera: "gate" }, { notificationsEnabled: true, cameras: [] }, []) === false, "detection skipped")
  assert(toastBody({ data: { objects: ["person"], zones: ["driveway"] } }) === "person · driveway", "toast")
  assert(parseLoginResponse("HTTP/1.1 200\r\nSet-Cookie: token=abc.def; HttpOnly\r\n\r\n{}") === "abc.def", "login cookie")
  assert(rememberIds(["1"], ["1", "2"]).join(",") === "1,2", "remember")
  if (fails) {
    console.error(fails + " failed")
    throw new Error("Model.js checks failed")
  }
  console.log("Model.js ok")
}
