import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.luccast.frigate"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var cameras: service ? service.cameras : []
  readonly property string statusText: service ? service.statusText : "Connecting…"
  readonly property bool needsLogin: service ? service.needsLogin === true : false
  readonly property bool signedIn: service ? service.connected === true && !needsLogin : false
  readonly property int stillRevision: service ? Number(service.stillRevision || 0) : 0
  readonly property int tileWidth: Style.space(168)
  readonly property int tileHeight: Style.space(96)

  function open() {
    if (root.service) {
      root.service.panelOpen = true
      root.service.clearUnread()
    }
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.service) root.service.panelOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function saveConnection() {
    if (!root.service) return
    root.service.persistSettings({
      url: urlField.text,
      username: userField.text
    })
    root.service.persistPassword(passField.text)
    root.service.token = ""
    root.service.loginAttempted = false
    root.service.connected = false
    root.service.statusText = "Connecting…"
    Qt.callLater(function() { if (root.service) root.service.tick() })
  }

  function logout() {
    if (root.service) root.service.logout()
    passField.text = ""
    userField.text = ""
  }

  onServiceChanged: {
    if (!root.service) return
    urlField.text = root.service.url
    userField.text = root.service.username
    passField.text = root.service.password
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus || userField.activeFocus || passField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "Frigate"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          width: parent.width
          text: root.statusText
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(8)
          visible: root.cameras.length > 0

          Repeater {
            model: root.cameras

            Column {
              required property var modelData
              width: root.tileWidth
              spacing: Style.space(4)

              Image {
                width: root.tileWidth
                height: root.tileHeight
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                source: root.service
                  ? "file://" + root.service.stillPath(modelData.name) + "?r=" + root.stillRevision
                  : ""
              }

              Text {
                width: parent.width
                text: modelData.name
                elide: Text.ElideRight
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Text {
          visible: root.cameras.length === 0
          width: parent.width
          text: root.needsLogin ? "Sign in to load cameras." : "No cameras yet."
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !root.signedIn

          TextField {
            id: urlField
            width: parent.width
            placeholderText: "http://127.0.0.1:5000"
          }

          TextField {
            id: userField
            width: parent.width
            placeholderText: "username (blank for :5000)"
          }

          TextField {
            id: passField
            width: parent.width
            password: true
            placeholderText: "password"
          }

          Button {
            text: "Save"
            foreground: root.contentForeground
            onClicked: root.saveConnection()
          }
        }

        Button {
          visible: root.signedIn
          text: "Log out"
          foreground: root.contentForeground
          onClicked: root.logout()
        }
      }
    }
  }
}
