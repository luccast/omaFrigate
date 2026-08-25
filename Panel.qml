import QtQuick
import QtQuick.Controls
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
  readonly property var reviews: service ? service.reviews : []
  readonly property string statusText: service ? service.statusText : "Connecting…"
  readonly property bool needsLogin: service ? service.needsLogin === true : false
  property bool signedIn: false
  property bool showSettings: false
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
    root.service.persistPassword(passField.text, root.service.rtspPassword)
    root.service.token = ""
    root.service.loginAttempted = false
    root.service.connected = false
    root.service.signedIn = false
    root.signedIn = false
    root.service.statusText = "Connecting…"
    Qt.callLater(function() { if (root.service) root.service.tick() })
  }

  function saveSettings() {
    if (!root.service) return
    root.service.persistSettings({
      rtspUsername: rtspUserField.text,
      hqStream: !!(root.service && root.service.hqStream)
    })
    root.service.persistPassword(root.service.password, rtspPassField.text)
  }

  function logout() {
    if (root.service) root.service.logout()
    root.signedIn = false
    root.showSettings = false
    passField.text = ""
    userField.text = ""
    rtspUserField.text = ""
    rtspPassField.text = ""
  }

  function syncAuth() {
    root.signedIn = !!(root.service && root.service.signedIn)
    if (!root.service) return
    if (!urlField.activeFocus) urlField.text = root.service.url
    if (!userField.activeFocus) userField.text = root.service.username
    if (!passField.activeFocus) passField.text = root.service.password
    if (!rtspUserField.activeFocus) rtspUserField.text = root.service.rtspUsername
    if (!rtspPassField.activeFocus) rtspPassField.text = root.service.rtspPassword
  }

  onServiceChanged: root.syncAuth()

  Connections {
    target: root.service
    function onSignedInChanged() { root.syncAuth() }
    function onConnectedChanged() { root.syncAuth() }
    function onStatusTextChanged() { root.syncAuth() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus || userField.activeFocus || passField.activeFocus || rtspUserField.activeFocus || rtspPassField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: content
        width: panelFlick.width
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: Math.max(titleLabel.implicitHeight, headerActions.implicitHeight)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            FrigateIcon {
              iconSize: Style.font.subtitle
              color: root.contentForeground
            }

            Text {
              id: titleLabel
              text: "omaFrigate"
              elide: Text.ElideRight
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              visible: root.signedIn
              iconText: "󰒓"
              tooltipText: root.showSettings ? "Back to cameras" : "Settings"
              foreground: root.showSettings ? Color.accent : root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.showSettings = !root.showSettings
            }

            PanelActionButton {
              iconText: "󰖟"
              tooltipText: "Open omaFrigate"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (root.service) root.service.openInBrowser()
            }

            PanelActionButton {
              visible: root.signedIn
              iconText: "󰍃"
              tooltipText: "Log out"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.logout()
            }
          }
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
          visible: root.cameras.length > 0 && !root.showSettings

          Repeater {
            model: root.cameras

            CursorSurface {
              id: tile
              required property var modelData
              width: root.tileWidth
              implicitHeight: tileContent.implicitHeight + Style.space(12)
              hasCursor: tileMouse.containsMouse
              foreground: root.contentForeground
              accent: Color.accent

              Column {
                id: tileContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(6)
                spacing: Style.space(4)

                Image {
                  width: parent.width
                  height: root.tileHeight
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  source: root.service
                    ? "file://" + root.service.stillPath(tile.modelData.name) + "?" + root.stillRevision
                    : ""
                }

                Text {
                  width: parent.width
                  text: tile.modelData.name
                  elide: Text.ElideRight
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: !!tile.modelData.detail
                  width: parent.width
                  text: tile.modelData.detail || ""
                  elide: Text.ElideRight
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.service) root.service.openLive(tile.modelData.name)
                  root.close()
                }
              }
            }
          }
        }

        Text {
          visible: root.cameras.length === 0 && !root.showSettings
          width: parent.width
          text: root.needsLogin ? "Sign in to load cameras." : "No cameras yet."
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        PanelSeparator {
          visible: root.signedIn && root.reviews.length > 0 && !root.showSettings
          foreground: root.contentForeground
        }

        Item {
          width: parent.width
          height: Math.max(reviewHeader.implicitHeight, markAllBtn.implicitHeight)
          visible: root.signedIn && root.reviews.length > 0 && !root.showSettings

          PanelSectionHeader {
            id: reviewHeader
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "ALERTS"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          PanelActionButton {
            id: markAllBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰄭"
            tooltipText: "Mark all reviewed"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: if (root.service) {
              var ids = []
              for (var i = 0; i < root.reviews.length; i++) ids.push(root.reviews[i].id)
              root.service.markReviewed(ids)
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.signedIn && root.reviews.length > 0 && !root.showSettings

          Repeater {
            model: root.reviews

            CursorSurface {
              id: reviewRow
              required property var modelData
              width: parent.width
              implicitHeight: reviewContent.implicitHeight + Style.space(10)
              hasCursor: reviewMouse.containsMouse
              foreground: root.contentForeground
              accent: Color.accent
              opacity: reviewRow.modelData.viewed ? 0.5 : 1.0

              MouseArea {
                id: reviewMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.openReview(reviewRow.modelData)
              }

              Row {
                id: reviewContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(6)
                spacing: Style.space(8)

                Image {
                  width: Style.space(48)
                  height: Style.space(36)
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  source: root.service
                    ? "file://" + root.service.reviewThumbPath(reviewRow.modelData.id) + "?" + root.stillRevision
                    : ""
                }

                Column {
                  width: parent.width - Style.space(48) - dismissBtn.width - parent.spacing * 2
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: reviewRow.modelData.camera
                    elide: Text.ElideRight
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    text: reviewRow.modelData.detail || ""
                    elide: Text.ElideRight
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                PanelActionButton {
                  id: dismissBtn
                  iconText: "󰄬"
                  tooltipText: "Dismiss"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: if (root.service) root.service.dismissReview(reviewRow.modelData.id)
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.signedIn && root.showSettings
          height: visible ? implicitHeight : 0

          PanelSectionHeader {
            text: "NOTIFICATIONS"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Toggle {
            width: parent.width
            label: "Live popup on alerts"
            description: "Open the camera when an alert fires"
            checked: !!(root.service && root.service.popupOnAlert)
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: if (root.service)
              root.service.persistSettings({ popupOnAlert: !root.service.popupOnAlert })
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          PanelSectionHeader {
            text: "DISPLAY"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Toggle {
            width: parent.width
            label: "4:3 aspect ratio"
            description: "Use 4:3 instead of 16:9 for camera windows"
            checked: !!(root.service && root.service.aspectRatio === "4:3")
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: if (root.service)
              root.service.persistSettings({ aspectRatio: root.service.aspectRatio === "4:3" ? "16:9" : "4:3" })
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          PanelSectionHeader {
            text: "STREAM QUALITY"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Toggle {
            width: parent.width
            label: "Higher quality stream"
            description: "Use RTSP main stream (H264) instead of MJPEG. Requires camera credentials."
            checked: !!(root.service && root.service.hqStream)
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: if (root.service)
              root.service.persistSettings({ hqStream: !root.service.hqStream })
          }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: !!(root.service && root.service.hqStream)
            height: visible ? implicitHeight : 0

            TextField {
              id: rtspUserField
              width: parent.width
              placeholderText: "camera username"
            }

            TextField {
              id: rtspPassField
              width: parent.width
              password: true
              placeholderText: "camera password"
            }

            Button {
              text: "Save"
              foreground: root.contentForeground
              onClicked: root.saveSettings()
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !root.signedIn
          height: visible ? implicitHeight : 0

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
      }
      }
    }
  }
}
