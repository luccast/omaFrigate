import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var cameras: []
  property var configState: ({ notificationsEnabled: true, cameras: [] })
  property bool connected: false
  property bool needsLogin: false
  property bool signedIn: false
  property string statusText: "Connecting…"
  property string token: ""
  property string password: ""
  property int unreadCount: 0
  property int stillRevision: 0
  property bool panelOpen: false
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
  readonly property var pluginSettings: Model.pluginSettings(shell ? shell.shellConfig : null, Model.PLUGIN_ID)
  readonly property string url: pluginSettings.url
  readonly property string username: pluginSettings.username
  readonly property int refreshSeconds: pluginSettings.refreshSeconds

  function stillPath(camera) {
    return cacheDir + "/" + String(camera || "").replace(/[^A-Za-z0-9._-]/g, "_") + ".jpg"
  }

  function alertPath(id) {
    return cacheDir + "/alerts/" + String(id || "").replace(/[^A-Za-z0-9._-]/g, "_") + ".jpg"
  }

  function persistSettings(values) {
    var entry = { id: Model.PLUGIN_ID, url: root.url, username: root.username, refreshSeconds: root.refreshSeconds }
    for (var key in values) entry[key] = values[key]
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(Model.PLUGIN_ID, entry)
  }

  function persistPassword(value) {
    root.password = String(value || "")
    passwordFile.setText(Model.serializePasswordFile(root.password))
    if (!root.loginPending) {
      chmodProc.command = ["chmod", "600", passwordPath]
      chmodProc.running = true
    }
  }

  function stopStills() {
    if (stillsProc.running) stillsProc.running = false
  }

  function logout() {
    root.loginPending = false
    root.loginAttempted = false
    root.token = ""
    root.connected = false
    root.signedIn = false
    root.needsLogin = true
    root.cameras = []
    root.configState = { notificationsEnabled: true, cameras: [] }
    root.statusText = "Signed out"
    root.unreadCount = 0
    stopStills()
    persistSettings({ username: "" })
    persistPassword("")
    loginBodyFile.setText("")
    ensureCacheProc.command = ["bash", "-c", "rm -f \"$1\"/*.jpg", "--", cacheDir]
    ensureCacheProc.running = true
    root.stillRevision += 1
  }

  function persistSeen() {
    seenFile.setText(Model.serializeSeenFile(root.seenIds))
  }

  function remember(ids) {
    var next = Model.rememberIds(root.seenIds, ids)
    if (JSON.stringify(next) === JSON.stringify(root.seenIds)) return
    root.seenIds = next
    persistSeen()
  }

  function curlJson(kind, url) {
    if (apiProc.running) return false
    root.apiKind = kind
    var cmd = ["curl", "-sS", "-w", "\n%{http_code}", "--max-time", "8"]
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

  function startConfig() {
    return curlJson("config", Model.configUrl(root.url))
  }

  function startReviews() {
    return curlJson("reviews", Model.reviewUrl(root.url))
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
    var cmd = ["curl", "-sS", "-o", alertPath(review.id), "-w", "\n%{http_code}", "--max-time", "8"]
    if (root.token) cmd.push("-H", "Authorization: Bearer " + root.token)
    cmd.push(Model.snapshotUrl(root.url, eventId))
    apiProc.command = cmd
    apiProc.running = true
    return true
  }

  function startStills() {
    if (!root.panelOpen || stillsProc.running || !root.cameras.length) return false
    var cmd = ["curl", "-sS", "--max-time", "8"]
    if (root.token) cmd.push("-H", "Authorization: Bearer " + root.token)
    for (var i = 0; i < root.cameras.length; i++) {
      cmd.push("-o", stillPath(root.cameras[i].name), Model.latestUrl(root.url, root.cameras[i].name))
    }
    stillsProc.command = cmd
    stillsProc.running = true
    return true
  }

  function sendToast(review, imagePath) {
    var cmd = ["omarchy-notification-send", "--app-name", "Frigate", "-u", "normal",
      "-g", "󰄀", "--exec", "omarchy-shell shell summon " + Model.PLUGIN_ID + " '{}'",
      String(review.camera || "Frigate"), Model.toastBody(review)]
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
    var parsed = splitHttp(text)
    if (root.apiKind === "snapshot") {
      var review = root.pendingNotify
      if (!review) return
      sendToast(review, parsed.status === 200 ? alertPath(review.id) : "")
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
      root.cameras = config.cameras
      root.connected = true
      root.signedIn = true
      root.needsLogin = false
      root.statusText = config.cameras.length ? (config.cameras.length + " cameras") : "Connected"
      root.loginAttempted = false
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
    for (var i = 0; i < reviews.length; i++) {
      var review = reviews[i]
      if (!review || !review.id) continue
      ids.push(String(review.id))
      if (!next && Model.shouldNotify(review, root.configState, root.seenIds))
        next = review
    }
    if (!root.seededSeen) {
      remember(ids)
      root.seededSeen = true
      return
    }
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
      if (retry === "reviews") startReviews()
      else startConfig()
      return
    }
    if (root.loginPending) return
    if (root.username && !root.token && root.password && !root.loginAttempted) {
      startLogin()
      return
    }
    if (!root.connected) {
      startConfig()
      return
    }
    startReviews()
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
    onLoaded: root.password = Model.parsePasswordFile(text())
    onLoadFailed: root.password = ""
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
    id: stillsProc
    running: false
    onExited: root.stillRevision += 1
  }

  Process {
    id: apiProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleApiSuccess(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.handleApiFailure()
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
    onTriggered: if (!apiProc.running) root.startConfig()
  }

  Timer {
    interval: Math.max(1, root.refreshSeconds) * 1000
    running: root.panelOpen && root.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: root.startStills()
  }

  onPanelOpenChanged: if (!root.panelOpen) root.stopStills()

  onUrlChanged: {
    root.token = ""
    root.connected = false
    root.signedIn = false
    root.loginAttempted = false
    root.statusText = "Connecting…"
  }

  Component.onCompleted: {
    passwordFile.reload()
    seenFile.reload()
    ensureCacheProc.command = ["mkdir", "-p", cacheDir + "/alerts"]
    ensureCacheProc.running = true
  }
}
