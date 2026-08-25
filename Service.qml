import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var cameras: []
  property var configState: ({ cameras: [] })
  property var statsState: ({ version: "", diskFree: 0, detectorMs: 0, cameras: {} })
  property var lastReviews: []
  property bool connected: false
  property bool needsLogin: false
  property bool signedIn: false
  property string statusText: "Connecting…"
  property string token: ""
  property string password: ""
  property string rtspPassword: ""
  property int unreadCount: 0
  property int stillRevision: 0
  property bool panelOpen: false
  property bool liveConfigReady: false
  property var reviews: []
  property var viewedQueue: []
  property var dismissedSet: ({})
  property bool seededSeen: false
  property var seenIds: []
  property var pendingNotify: null
  property string apiKind: ""
  property string retryKind: ""
  property bool loginAttempted: false
  property bool loginPending: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"
  readonly property string cacheDir: home + "/.cache/omarchy/frigate"
  readonly property string passwordPath: stateDir + "/frigate.json"
  readonly property string seenPath: stateDir + "/frigate-seen.json"
  readonly property string loginBodyPath: cacheDir + "/login.json"
  readonly property string viewedBodyPath: cacheDir + "/viewed.json"
  readonly property string liveConfigPath: cacheDir + "/mpv-live.conf"
  readonly property var pluginSettings: Model.pluginSettings(shell ? shell.shellConfig : null, Model.PLUGIN_ID)
  readonly property string url: pluginSettings.url
  readonly property string username: pluginSettings.username
  readonly property int refreshSeconds: pluginSettings.refreshSeconds
  readonly property bool popupOnAlert: pluginSettings.popupOnAlert === true
  readonly property string rtspUsername: pluginSettings.rtspUsername
  readonly property bool hqStream: pluginSettings.hqStream === true
  readonly property string aspectRatio: pluginSettings.aspectRatio

  function cachePath(subdir, id, ext) {
    return cacheDir + (subdir ? "/" + subdir : "") + "/" +
      String(id || "").replace(/[^A-Za-z0-9._-]/g, "_") + ext
  }

  function stillPath(camera) { return cachePath("", camera, ".jpg") }
  function alertPath(id) { return cachePath("alerts", id, ".jpg") }
  function reviewThumbPath(id) { return cachePath("reviews", id, ".gif") }

  function persistSettings(values) {
    var entry = {
      id: Model.PLUGIN_ID,
      url: root.url,
      username: root.username,
      refreshSeconds: root.refreshSeconds,
      popupOnAlert: root.popupOnAlert,
      rtspUsername: root.rtspUsername,
      hqStream: root.hqStream,
      aspectRatio: root.aspectRatio
    }
    for (var key in values) entry[key] = values[key]
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(Model.PLUGIN_ID, entry)
  }

  function persistPassword(value, rtspValue) {
    root.password = String(value || "")
    root.rtspPassword = String(rtspValue || "")
    passwordFile.setText(Model.serializePasswordFile(root.password, root.rtspPassword))
    if (!root.loginPending) {
      chmodProc.command = ["chmod", "600", passwordPath]
      chmodProc.running = true
    }
  }

  function logout() {
    root.loginPending = false
    root.loginAttempted = false
    root.token = ""
    root.connected = false
    root.signedIn = false
    root.needsLogin = true
    root.cameras = []
    root.configState = { cameras: [] }
    root.statsState = { version: "", diskFree: 0, detectorMs: 0, cameras: {} }
    root.lastReviews = []
    root.reviews = []
    root.viewedQueue = []
    root.dismissedSet = ({})
    root.statusText = "Signed out"
    root.unreadCount = 0
    if (stillsProc.running) stillsProc.running = false
    persistSettings({ username: "", rtspUsername: "", hqStream: false, aspectRatio: "16:9" })
    persistPassword("", "")
    loginBodyFile.setText("")
    closeLive()
    ensureCacheProc.command = ["bash", "-c", "rm -f \"$1\"/*.jpg \"$1\"/reviews/*", "--", cacheDir]
    ensureCacheProc.running = true
    root.stillRevision += 1
  }

  function persistSeen() {
    seenFile.setText(Model.serializeSeenFile(root.seenIds))
  }

  function openInBrowser() {
    if (!root.url) return
    openProc.command = ["omarchy", "launch", "browser", root.url]
    openProc.running = true
  }

  function liveConfigText() {
    var lines = ["profile=low-latency", "untimed=yes", "cache=no", "audio=no"]
    if (root.token) lines.push("http-header-fields=Authorization: Bearer " + root.token)
    return lines.join("\n") + "\n"
  }

  function writeLiveConfig() {
    liveConfigFile.setText(liveConfigText())
    liveChmodProc.command = ["chmod", "600", liveConfigPath]
    liveChmodProc.running = true
  }

  function liveIndexOf(name) {
    for (var i = 0; i < liveModel.count; i++) {
      if (liveModel.get(i).name === name) return i
    }
    return -1
  }

  function openPlayer(name, url, title, loop) {
    var key = String(name || "")
    var media = String(url || "")
    if (!key || !media) return
    if (liveIndexOf(key) !== -1) return
    liveModel.append({
      name: key,
      mediaUrl: media,
      title: String(title || key),
      geometry: Model.liveGeometry(liveModel.count, root.aspectRatio),
      loop: loop === true
    })
    if (!root.liveConfigReady) writeLiveConfig()
  }

  function openLive(camera) {
    var name = String(camera || "")
    if (!name || !root.url) return
    var url = Model.liveUrl(root.url, name)
    if (root.hqStream && root.rtspUsername && root.rtspPassword) {
      for (var i = 0; i < root.configState.cameras.length; i++) {
        if (root.configState.cameras[i].name === name) {
          var rtsp = root.configState.cameras[i].rtspUrl
          if (rtsp) url = Model.rtspWithCreds(rtsp, root.rtspUsername, root.rtspPassword)
          break
        }
      }
    }
    openPlayer(name, url, "omaFrigate – " + name)
  }

  function openReview(review) {
    if (!review || !review.id) return
    if (review.live) openLive(review.camera)
    else openPlayer("clip-" + review.id, Model.clipUrl(root.url, review.camera, review.startTime, review.endTime),
      "omaFrigate – " + String(review.camera || "review"), true)
    markReviewed([review.id])
  }

  function dismissReview(id) {
    root.dismissedSet[String(id)] = true
    markReviewed([id])
    applyReviews()
  }

  function dropLive(name) {
    var idx = liveIndexOf(name)
    if (idx !== -1) liveModel.remove(idx)
  }

  function closeLive() {
    liveModel.clear()
  }

  function remember(ids) {
    var next = Model.rememberIds(root.seenIds, ids)
    if (JSON.stringify(next) === JSON.stringify(root.seenIds)) return
    root.seenIds = next
    persistSeen()
  }

  function markReviewed(ids) {
    var incoming = Array.isArray(ids) ? ids : []
    var next = []
    for (var i = 0; i < incoming.length; i++) {
      var id = String(incoming[i] || "")
      if (!id || root.viewedQueue.indexOf(id) !== -1) continue
      next.push(id)
    }
    if (!next.length) return
    var reviews = Array.isArray(root.lastReviews) ? root.lastReviews.slice() : []
    for (var r = 0; r < reviews.length; r++) {
      if (reviews[r] && next.indexOf(String(reviews[r].id)) !== -1)
        reviews[r].has_been_reviewed = true
    }
    root.lastReviews = reviews
    applyReviews()
    applyCameras()
    root.viewedQueue = root.viewedQueue.concat(next)
    remember(next)
    if (!apiProc.running) startViewed()
  }

  function startViewed() {
    if (apiProc.running || !root.viewedQueue.length || !root.url) return false
    viewedBodyFile.setText(Model.viewedBody(root.viewedQueue))
    root.apiKind = "viewed"
    var cmd = ["curl", "-sS", "-w", "\n%{http_code}"].concat(Model.curlBounds(Model.API_MAX_BYTES), [
      "-X", "POST", "-H", "Content-Type: application/json",
      "--data-binary", "@" + viewedBodyPath
    ])
    if (root.token) cmd.push("-H", "Authorization: Bearer " + root.token)
    cmd.push(Model.viewedUrl(root.url))
    apiProc.command = cmd
    apiProc.running = true
    return true
  }

  function curlJson(kind, url) {
    if (apiProc.running) return false
    root.apiKind = kind
    var cmd = ["curl", "-sS", "-w", "\n%{http_code}"].concat(Model.curlBounds(Model.API_MAX_BYTES))
    if (root.token) cmd.push("-H", "Authorization: Bearer " + root.token)
    if (kind === "login")
      cmd.push("-i", "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@" + loginBodyPath)
    cmd.push(url)
    apiProc.command = cmd
    apiProc.running = true
    return true
  }

  function startLogin() {
    if (apiProc.running || root.loginPending) return false
    root.loginAttempted = true
    root.loginPending = true
    loginBodyFile.setText(Model.loginBody(root.username, root.password))
    chmodProc.command = ["chmod", "600", loginBodyPath]
    chmodProc.running = true
    return true
  }

  function applyReviews() {
    var items = Model.reviewItems(root.lastReviews, 8)
    var filtered = []
    for (var i = 0; i < items.length; i++) {
      if (!root.dismissedSet[items[i].id]) filtered.push(items[i])
    }
    root.reviews = filtered
    if (root.connected && !stillsProc.running) Qt.callLater(root.startStills)
  }

  function applyCameras() {
    root.cameras = Model.mergeCameras(root.configState.cameras, root.statsState, root.lastReviews)
    if (root.connected)
      root.statusText = Model.hostSummary(root.statsState) || (root.cameras.length + " cameras")
  }

  function startSnapshot(review) {
    var eventId = Model.firstDetectionId(review)
    if (!eventId) {
      sendToast(review, "")
      return false
    }
    if (apiProc.running) return false
    root.pendingNotify = review
    root.apiKind = "snapshot"
    ensureCacheProc.command = ["mkdir", "-p", cacheDir + "/alerts"]
    ensureCacheProc.running = true
    var cmd = ["curl", "-sS", "-o", alertPath(review.id), "-w", "\n%{http_code}"].concat(
      Model.curlBounds(Model.IMAGE_MAX_BYTES))
    if (root.token) cmd.push("-H", "Authorization: Bearer " + root.token)
    cmd.push(Model.snapshotUrl(root.url, eventId))
    apiProc.command = cmd
    apiProc.running = true
    return true
  }

  function startStills() {
    if (stillsProc.running) return false
    var cmd = ["curl", "-sS"].concat(Model.curlBounds(Model.IMAGE_MAX_BYTES))
    if (root.token) cmd.push("-H", "Authorization: Bearer " + root.token)
    var added = 0
    if (root.panelOpen) {
      for (var i = 0; i < root.cameras.length; i++) {
        cmd.push("-o", stillPath(root.cameras[i].name), Model.latestUrl(root.url, root.cameras[i].name))
        added += 1
      }
    }
    for (var r = 0; r < root.reviews.length; r++) {
      cmd.push("-o", reviewThumbPath(root.reviews[r].id), Model.reviewPreviewUrl(root.url, root.reviews[r].id))
      added += 1
    }
    if (!added) return false
    stillsProc.command = cmd
    stillsProc.running = true
    return true
  }

  function sendToast(review, imagePath) {
    var cmd = ["omarchy-notification-send", "--app-name", "omaFrigate", "-u", "normal",
      "-g", "󰄀", "--exec", "omarchy-shell shell summon " + Model.PLUGIN_ID + " '{}'",
      String(review.camera || "omaFrigate"), Model.toastBody(review)]
    if (imagePath) cmd.splice(5, 0, "--image", imagePath)
    toastProc.command = cmd
    toastProc.running = true
    root.unreadCount += 1
    root.pendingNotify = null
  }

  function splitHttp(text) {
    var raw = String(text || "")
    var nl = raw.lastIndexOf("\n")
    if (nl === -1) return { body: raw, status: 0 }
    return { body: raw.slice(0, nl), status: parseInt(raw.slice(nl + 1), 10) || 0 }
  }

  function handleApiSuccess(text) {
    if (String(text || "").length > Model.API_MAX_BYTES + 16) {
      handleApiFailure()
      return
    }
    var parsed = splitHttp(text)
    if (root.apiKind === "snapshot") {
      var review = root.pendingNotify
      if (!review) return
      sendToast(review, parsed.status === 200 ? alertPath(review.id) : "")
      return
    }
    if (root.apiKind === "viewed") {
      if (parsed.status < 400) root.viewedQueue = []
      return
    }
    if (parsed.status === 401 && root.username && root.apiKind !== "login" && !root.loginAttempted) {
      root.retryKind = root.apiKind
      startLogin()
      return
    }
    if (root.apiKind === "login") {
      var token = Model.parseLoginResponse(parsed.body)
      if (parsed.status >= 400 || !token) {
        root.needsLogin = true
        root.signedIn = false
        root.statusText = "Login failed"
        return
      }
      root.token = token
      root.needsLogin = false
      root.retryKind = root.retryKind || "config"
      return
    }
    if (parsed.status >= 400) {
      handleApiFailure()
      return
    }
    if (root.apiKind === "config") {
      var config = Model.parseConfig(parsed.body)
      root.configState = config
      root.connected = true
      root.signedIn = true
      root.needsLogin = false
      root.loginAttempted = false
      applyCameras()
      root.retryKind = root.retryKind || "stats"
      return
    }
    if (root.apiKind === "stats") {
      root.statsState = Model.parseStats(parsed.body)
      applyCameras()
      return
    }
    if (root.apiKind === "reviews") handleReviews(Model.parseReviews(parsed.body))
  }

  function handleApiFailure() {
    if (root.apiKind === "snapshot") {
      var review = root.pendingNotify
      if (review) sendToast(review, "")
      return
    }
    if (root.apiKind === "viewed") return
    if (root.username && root.apiKind !== "login" && !root.loginAttempted) {
      root.retryKind = root.apiKind
      startLogin()
      return
    }
    if (root.apiKind === "login") {
      root.needsLogin = true
      root.signedIn = false
      root.statusText = "Login failed"
      return
    }
    root.connected = false
    root.signedIn = false
    root.statusText = root.username ? "Needs login" : "Unreachable"
    if (root.username && !root.password) root.needsLogin = true
  }

  function handleReviews(reviews) {
    var ids = []
    var next = null
    var popupCams = []
    for (var i = 0; i < reviews.length; i++) {
      var review = reviews[i]
      if (!review || !review.id) continue
      ids.push(String(review.id))
      if (!Model.shouldNotify(review, root.configState, root.seenIds)) continue
      if (!next) next = review
      var camera = String(review.camera || "")
      if (root.popupOnAlert && camera && popupCams.indexOf(camera) === -1)
        popupCams.push(camera)
    }
    root.lastReviews = reviews
    applyReviews()
    applyCameras()
    if (!root.seededSeen) {
      remember(ids)
      root.seededSeen = true
      return
    }
    for (var p = 0; p < popupCams.length; p++) openLive(popupCams[p])
    if (next) {
      remember([next.id])
      startSnapshot(next)
      return
    }
    remember(ids)
  }

  function tick() {
    if (apiProc.running) return
    if (root.retryKind) {
      var retry = root.retryKind
      root.retryKind = ""
      if (retry === "reviews") curlJson("reviews", Model.reviewUrl(root.url))
      else if (retry === "stats") curlJson("stats", Model.statsUrl(root.url))
      else if (retry === "viewed") startViewed()
      else curlJson("config", Model.configUrl(root.url))
      return
    }
    if (root.viewedQueue.length) {
      startViewed()
      return
    }
    if (root.loginPending) return
    if (root.username && !root.token && root.password && !root.loginAttempted) {
      startLogin()
      return
    }
    if (!root.connected) {
      curlJson("config", Model.configUrl(root.url))
      return
    }
    curlJson("reviews", Model.reviewUrl(root.url))
  }

  function clearUnread() {
    root.unreadCount = 0
  }

  FileView {
    id: passwordFile
    path: root.passwordPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = Model.parsePasswordFile(text())
      root.password = parsed.password
      root.rtspPassword = parsed.rtspPassword
    }
    onLoadFailed: {
      root.password = ""
      root.rtspPassword = ""
    }
    onFileChanged: reload()
  }

  FileView {
    id: loginBodyFile
    path: root.loginBodyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: liveConfigFile
    path: root.liveConfigPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: viewedBodyFile
    path: root.viewedBodyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  ListModel {
    id: liveModel
  }

  Instantiator {
    model: liveModel
    delegate: Process {
      required property string name
      required property string mediaUrl
      required property string title
      required property string geometry
      required property bool loop
      running: root.liveConfigReady && mediaUrl !== ""
      command: {
        var cmd = [
          "mpv",
          "--include=" + root.liveConfigPath,
          "--title=" + title,
          "--wayland-app-id=omaFrigate-live",
          "--force-window=immediate",
          "--geometry=" + geometry,
          "--no-audio",
          "--really-quiet",
          "--video-aspect-override=" + (root.aspectRatio === "4:3" ? "4/3" : "16/9")
        ]
        if (loop) cmd.push("--loop-file=inf", "--untimed=no", "--cache=yes")
        else if (String(mediaUrl).indexOf("rtsp://") === 0) cmd.push("--untimed=no", "--cache=yes")
        cmd.push(mediaUrl)
        return cmd
      }
      onExited: if (!running) root.dropLive(name)
    }
  }

  FileView {
    id: seenFile
    path: root.seenPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.seenIds = Model.parseSeenFile(text())
      root.seededSeen = root.seenIds.length > 0
    }
    onLoadFailed: {
      root.seenIds = []
      root.seededSeen = false
    }
  }

  Process {
    id: ensureCacheProc
    running: false
  }

  Process {
    id: chmodProc
    running: false
    onExited: {
      if (!root.loginPending) return
      root.loginPending = false
      curlJson("login", Model.loginUrl(root.url))
    }
  }

  Process {
    id: toastProc
    running: false
  }

  Process {
    id: openProc
    running: false
  }

  Process {
    id: liveChmodProc
    running: false
    onExited: root.liveConfigReady = true
  }

  Process {
    id: stillsProc
    running: false
    onExited: root.stillRevision += 1
  }

  Process {
    id: apiProc
    running: false
    stdout: StdioCollector {
      id: apiOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.handleApiFailure()
      else root.handleApiSuccess(apiOut.text)
      Qt.callLater(root.tick)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  Timer {
    interval: 15000
    running: root.connected
    repeat: true
    onTriggered: if (!apiProc.running) root.curlJson("stats", Model.statsUrl(root.url))
  }

  Timer {
    interval: Math.max(1, root.refreshSeconds) * 1000
    running: root.panelOpen && root.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: root.startStills()
  }

  onPanelOpenChanged: if (!root.panelOpen && stillsProc.running) stillsProc.running = false

  onUrlChanged: {
    root.token = ""
    root.connected = false
    root.signedIn = false
    root.loginAttempted = false
    root.statusText = "Connecting…"
    root.closeLive()
  }

  Component.onCompleted: {
    passwordFile.reload()
    seenFile.reload()
    ensureCacheProc.command = ["mkdir", "-p", cacheDir + "/alerts", cacheDir + "/reviews"]
    ensureCacheProc.running = true
    writeLiveConfig()
  }
}
