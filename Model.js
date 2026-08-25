var PLUGIN_ID = "io.github.luccast.frigate"
var DEFAULT_URL = "http://127.0.0.1:5000"
var SEEN_LIMIT = 200

function normalizeUrl(url) {
  var value = String(url || "").replace(/^\s+|\s+$/g, "").replace(/\/+$/, "")
  return value || DEFAULT_URL
}

function pluginSettings(config, id) {
  var key = String(id || PLUGIN_ID)
  var empty = { url: DEFAULT_URL, username: "", refreshSeconds: 2, popupOnAlert: false, rtspUsername: "", hqStream: false, aspectRatio: "16:9" }
  if (!config || typeof config !== "object") return empty

  function fromEntry(entry) {
    if (!entry || typeof entry !== "object") return null
    if (String(entry.id || "") !== key) return null
    return {
      url: normalizeUrl(entry.url),
      username: String(entry.username || ""),
      refreshSeconds: Math.max(1, parseInt(entry.refreshSeconds, 10) || 2),
      popupOnAlert: entry.popupOnAlert === true,
      rtspUsername: String(entry.rtspUsername || ""),
      hqStream: entry.hqStream === true,
      aspectRatio: String(entry.aspectRatio || "16:9") === "4:3" ? "4:3" : "16:9"
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
    return {
      password: data && typeof data.password === "string" ? data.password : "",
      rtspPassword: data && typeof data.rtspPassword === "string" ? data.rtspPassword : ""
    }
  } catch (e) {
    return { password: "", rtspPassword: "" }
  }
}

function serializePasswordFile(password, rtspPassword) {
  return JSON.stringify({
    password: String(password || ""),
    rtspPassword: String(rtspPassword || "")
  }) + "\n"
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
        notifySuspendedUntil: Number(notify.suspended || 0) || 0,
        rtspUrl: rtspMainUrl(camera)
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

function parseStats(raw) {
  var empty = { version: "", uptime: 0, diskFree: 0, detectorMs: 0, cameras: {} }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return empty
    var service = data.service || {}
    var storage = (service.storage || {})["/media/frigate/recordings"] || {}
    var detectors = data.detectors || {}
    var detectorMs = 0
    for (var name in detectors) {
      if (!Object.prototype.hasOwnProperty.call(detectors, name)) continue
      detectorMs = Number(detectors[name].inference_speed) || 0
      break
    }
    var cameras = {}
    var source = data.cameras && typeof data.cameras === "object" ? data.cameras : {}
    for (var camName in source) {
      if (!Object.prototype.hasOwnProperty.call(source, camName)) continue
      var cam = source[camName] || {}
      var fps = Number(cam.camera_fps) || 0
      cameras[camName] = {
        fps: fps,
        detectionFps: Number(cam.detection_fps) || 0,
        online: fps > 0 && !!cam.ffmpeg_pid
      }
    }
    return {
      version: String(service.version || ""),
      uptime: Number(service.uptime) || 0,
      diskFree: Number(storage.free) || 0,
      detectorMs: detectorMs,
      cameras: cameras
    }
  } catch (e) {
    return empty
  }
}

function latestReviews(reviews) {
  var latest = {}
  var list = Array.isArray(reviews) ? reviews : []
  for (var i = 0; i < list.length; i++) {
    var review = list[i]
    if (!review || !review.camera || latest[review.camera]) continue
    latest[review.camera] = {
      objects: reviewObjects(review),
      severity: String(review.severity || ""),
      startTime: Number(review.start_time) || 0,
      live: review.end_time == null
    }
  }
  return latest
}

function timeAgo(ts) {
  var t = Number(ts) || 0
  if (!t) return ""
  var sec = Math.max(0, Math.floor(Date.now() / 1000 - t))
  if (sec < 60) return sec + "s"
  if (sec < 3600) return Math.floor(sec / 60) + "m"
  if (sec < 86400) return Math.floor(sec / 3600) + "h"
  return Math.floor(sec / 86400) + "d"
}

function formatMb(mb) {
  var n = Number(mb) || 0
  if (n >= 1024) return (Math.round(n / 102.4) / 10) + " GB"
  return Math.round(n) + " MB"
}

function cameraDetail(st, last) {
  var parts = []
  if (st && st.online === false) parts.push("offline")
  else if (st && st.fps) parts.push((Math.round(st.fps * 10) / 10) + " fps")
  if (last && last.objects) {
    var when = last.live ? "now" : timeAgo(last.startTime)
    var label = (last.severity === "alert" ? "alert " : "") + last.objects
    parts.push(when ? label + " · " + when : label)
  }
  return parts.join(" · ")
}

function mergeCameras(configCameras, stats, reviews) {
  var cameras = Array.isArray(configCameras) ? configCameras : []
  var statsCams = stats && stats.cameras ? stats.cameras : {}
  var latest = latestReviews(reviews)
  var out = []
  for (var i = 0; i < cameras.length; i++) {
    var cam = cameras[i] || {}
    var name = String(cam.name || "")
    var st = statsCams[name] || {}
    var last = latest[name] || {}
    out.push({
      name: name,
      enabled: cam.enabled !== false,
      notifyEnabled: cam.notifyEnabled !== false,
      notifySuspendedUntil: cam.notifySuspendedUntil || 0,
      fps: Number(st.fps) || 0,
      online: st.online === true,
      lastObjects: last.objects || "",
      lastSeverity: last.severity || "",
      live: last.live === true,
      detail: cameraDetail(st, last)
    })
  }
  return out
}

function hostSummary(stats) {
  if (!stats) return ""
  var parts = []
  if (stats.version) parts.push(stats.version)
  if (stats.diskFree) parts.push(formatMb(stats.diskFree) + " free")
  if (stats.detectorMs) parts.push(Math.round(stats.detectorMs) + "ms detect")
  return parts.join(" · ")
}

function cameraAllowed(configState, cameraName) {
  var cameras = configState && configState.cameras ? configState.cameras : []
  for (var i = 0; i < cameras.length; i++) {
    if (cameras[i].name !== cameraName) continue
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

function liveUrl(base, camera) {
  return normalizeUrl(base) + "/api/" + encodeURIComponent(String(camera || ""))
}

function stripRtspCreds(path) {
  return String(path || "").replace(/^rtsp:\/\/[^@]*@/, "rtsp://")
}

function rtspWithCreds(url, user, pass) {
  if (!user || !pass) return ""
  return String(url || "").replace(/^rtsp:\/\//, "rtsp://" + encodeURIComponent(user) + ":" + encodeURIComponent(pass) + "@")
}

function rtspMainUrl(cam) {
  if (!cam) return ""
  var inputs = cam.ffmpeg && cam.ffmpeg.inputs ? cam.ffmpeg.inputs : []
  for (var i = 0; i < inputs.length; i++) {
    var roles = inputs[i].roles || []
    if (roles.indexOf("record") !== -1) return stripRtspCreds(inputs[i].path)
  }
  return ""
}

function clipUrl(base, camera, start, end) {
  var s = Number(start) || 0
  var e = Number(end) || 0
  if (!e || e <= s) e = s + 30
  return normalizeUrl(base) + "/api/" + encodeURIComponent(String(camera || "")) +
    "/start/" + s + "/end/" + e + "/clip.mp4"
}

function reviewThumbUrl(base, review) {
  var camera = review && review.camera ? review.camera : ""
  var id = review && review.id ? review.id : ""
  return normalizeUrl(base) + "/clips/review/thumb-" + encodeURIComponent(String(camera)) +
    "-" + encodeURIComponent(String(id)) + ".webp"
}

function reviewPreviewUrl(base, id) {
  return normalizeUrl(base) + "/api/review/" + encodeURIComponent(String(id || "")) + "/preview"
}

function viewedUrl(base) {
  return normalizeUrl(base) + "/api/reviews/viewed"
}

function viewedBody(ids) {
  var list = Array.isArray(ids) ? ids.map(String).filter(Boolean) : []
  return JSON.stringify({ ids: list })
}

function reviewItems(reviews, limit) {
  var out = []
  var list = Array.isArray(reviews) ? reviews : []
  var max = Math.max(1, parseInt(limit, 10) || 8)
  for (var i = 0; i < list.length; i++) {
    var review = list[i]
    if (!review || !review.id) continue
    if (review.severity && review.severity !== "alert") continue
    var startTime = Number(review.start_time) || 0
    var live = review.end_time == null
    var objects = reviewObjects(review)
    var zones = reviewZones(review)
    var when = live ? "now" : timeAgo(startTime)
    var parts = [objects]
    if (zones) parts.push(zones)
    if (when) parts.push(when)
    out.push({
      id: String(review.id),
      camera: String(review.camera || ""),
      objects: objects,
      zones: zones,
      startTime: startTime,
      endTime: live ? 0 : Number(review.end_time) || 0,
      live: live,
      viewed: !!review.has_been_reviewed,
      firstDetection: firstDetectionId(review),
      detail: parts.join(" · ")
    })
    if (out.length >= max) break
  }
  return out
}

function snapshotUrl(base, eventId) {
  return normalizeUrl(base) + "/api/events/" + encodeURIComponent(String(eventId || "")) + "/snapshot.jpg"
}

function liveGeometry(index, aspect) {
  var i = Math.max(0, parseInt(index, 10) || 0)
  var w = 640
  var h = aspect === "4:3" ? 480 : 360
  var gap = 16
  var margin = 40
  var col = Math.floor(i / 2)
  var row = i % 2
  return w + "x" + h + "-" + (margin + col * (w + gap)) + "-" + (margin + row * (h + gap))
}

function reviewUrl(base) {
  return normalizeUrl(base) + "/api/review?limit=20"
}

function configUrl(base) {
  return normalizeUrl(base) + "/api/config"
}

function statsUrl(base) {
  return normalizeUrl(base) + "/api/stats"
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
  assert(pluginSettings({}).popupOnAlert === false, "popup default")
  assert(pluginSettings({}).hqStream === false, "hqStream default")
  assert(pluginSettings({}).aspectRatio === "16:9", "aspectRatio default")
  assert(pluginSettings({
    bar: { layout: { right: [{ id: PLUGIN_ID, popupOnAlert: true }] } }
  }).popupOnAlert === true, "popup on")
  assert(parsePasswordFile('{"password":"secret","rtspPassword":"cam"}').password === "secret", "password")
  assert(parsePasswordFile('{"password":"secret","rtspPassword":"cam"}').rtspPassword === "cam", "rtsp password")
  assert(parseConfig('{"notifications":{"enabled":false},"cameras":{"gate":{}}}').notificationsEnabled === false, "config notify")
  assert(shouldNotify({ id: "a", severity: "alert", camera: "gate" }, { notificationsEnabled: true, cameras: [] }, []) === true, "new alert")
  assert(shouldNotify({ id: "a", severity: "alert", camera: "gate" }, { notificationsEnabled: false, cameras: [{ name: "gate", notifyEnabled: false }] }, []) === true, "frigate notify service off")
  assert(shouldNotify({ id: "a", severity: "alert", camera: "gate" }, { notificationsEnabled: true, cameras: [{ name: "gate", notifySuspendedUntil: Date.now() / 1000 + 600 }] }, []) === false, "camera suspended")
  assert(shouldNotify({ id: "a", severity: "alert", camera: "gate" }, { notificationsEnabled: true, cameras: [] }, ["a"]) === false, "seen alert")
  assert(shouldNotify({ id: "a", severity: "detection", camera: "gate" }, { notificationsEnabled: true, cameras: [] }, []) === false, "detection skipped")
  assert(toastBody({ data: { objects: ["person"], zones: ["driveway"] } }) === "person · driveway", "toast")
  assert(parseLoginResponse("HTTP/1.1 200\r\nSet-Cookie: token=abc.def; HttpOnly\r\n\r\n{}") === "abc.def", "login cookie")
  assert(liveUrl("http://nvr:5000/", "front left") === "http://nvr:5000/api/front%20left", "liveUrl")
  assert(stripRtspCreds("rtsp://admin:pass@192.168.1.1:554/stream") === "rtsp://192.168.1.1:554/stream", "stripRtspCreds")
  assert(rtspMainUrl({ ffmpeg: { inputs: [
    { path: "rtsp://admin:pass@1.2.3.4:554/sub", roles: ["detect"] },
    { path: "rtsp://admin:pass@1.2.3.4:554/main", roles: ["record"] }
  ] } }) === "rtsp://1.2.3.4:554/main", "rtspMainUrl")
  assert(rtspWithCreds("rtsp://1.2.3.4:554/main", "admin", "pass") === "rtsp://admin:pass@1.2.3.4:554/main", "rtspWithCreds")
  assert(liveGeometry(0) === "640x360-40-40", "liveGeometry0")
  assert(liveGeometry(0, "4:3") === "640x480-40-40", "liveGeometry43")
  assert(liveGeometry(1) === "640x360-40-416", "liveGeometry1")
  assert(clipUrl("http://nvr:5000/", "front left", 1.5, 2) === "http://nvr:5000/api/front%20left/start/1.5/end/2/clip.mp4", "clipUrl")
  assert(reviewThumbUrl("http://nvr", { camera: "garage", id: "1.2-ab" }) === "http://nvr/clips/review/thumb-garage-1.2-ab.webp", "reviewThumb")
  assert(viewedBody(["a", "b"]) === '{"ids":["a","b"]}', "viewedBody")
  assert(reviewItems([
    { id: "a", severity: "alert", camera: "gate", has_been_reviewed: false, start_time: 1, data: { objects: ["person"], zones: ["drive"] } },
    { id: "b", severity: "detection", camera: "gate", has_been_reviewed: false, start_time: 1 },
    { id: "c", severity: "alert", camera: "gate", has_been_reviewed: true, start_time: 1 }
  ], 8).length === 2, "reviewItems")
  assert(reviewItems([
    { id: "a", severity: "alert", camera: "gate", has_been_reviewed: false, start_time: 1, data: { objects: ["person"] } }
  ], 8)[0].objects === "person", "reviewItem objects")
  assert(reviewItems([
    { id: "c", severity: "alert", camera: "gate", has_been_reviewed: true, start_time: 1, data: { objects: ["person"] } }
  ], 8)[0].viewed === true, "reviewItem viewed")
  assert(reviewItems([
    { id: "a", severity: "alert", camera: "gate", has_been_reviewed: false, start_time: 1, data: { objects: ["person"], detections: ["d1"] } }
  ], 8)[0].firstDetection === "d1", "reviewItem firstDetection")
  assert(rememberIds(["1"], ["1", "2"]).join(",") === "1,2", "remember")
  var stats = parseStats(JSON.stringify({
    cameras: { gate: { camera_fps: 5.1, detection_fps: 2, ffmpeg_pid: 9 } },
    detectors: { coral: { inference_speed: 7.8 } },
    service: { version: "0.17.1", storage: { "/media/frigate/recordings": { free: 1671.1 } } }
  }))
  assert(stats.cameras.gate.online === true && stats.detectorMs === 7.8, "stats")
  assert(hostSummary(stats) === "0.17.1 · 1.6 GB free · 8ms detect", "host")
  var merged = mergeCameras([{ name: "gate" }], stats, [
    { camera: "gate", severity: "alert", start_time: Date.now() / 1000 - 90, end_time: Date.now() / 1000 - 80, data: { objects: ["person"] } }
  ])
  assert(merged[0].detail === "5.1 fps · alert person · 1m", "merge")
  var live = mergeCameras([{ name: "gate" }], stats, [
    { camera: "gate", severity: "detection", start_time: Date.now() / 1000, end_time: null, data: { objects: ["car"] } }
  ])
  assert(live[0].detail === "5.1 fps · car · now", "live")
  if (fails) {
    console.error(fails + " failed")
    throw new Error("Model.js checks failed")
  }
  console.log("Model.js ok")
}
