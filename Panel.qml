import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "remi.kbdlight"
  ipcTarget: "remi.kbdlight"

  readonly property string device: "tpacpi::kbd_backlight"
  property int level: 0
  property int maxLevel: 2
  // The level to come back to when switching on. Saved, so a "low" choice
  // survives restarts.
  property int lastOn: Number(setting("level", 2))

  // Sundown mode: on a little before sunset, off at sunrise, or at custom
  // times. Only acts when the schedule flips, so clicks in between win
  // until the next switch.
  readonly property bool sunsetMode: setting("sunsetMode", true) === true
  // Empty = follow the sun for that side.
  readonly property string onTime: String(setting("onTime", ""))
  readonly property string offTime: String(setting("offTime", ""))
  readonly property int leadMinutes: Number(setting("leadMinutes", 20))

  // Location comes from the timezone's main city (zone.tab), so it follows
  // the clock when travelling and no coordinates are stored.
  property string zone: ""
  property real lat: NaN
  property real lon: NaN

  property string sky: ""

  // Any schedule change, from the menu or from shell.json, puts the light
  // where the new schedule says.
  function scheduleChanged() { if (zone !== "") Qt.callLater(function() { root.checkSky(true) }) }
  onSunsetModeChanged: scheduleChanged()
  onOnTimeChanged: scheduleChanged()
  onOffTimeChanged: scheduleChanged()
  property var plan: null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function save(patch) {
    settings = Object.assign({}, settings, patch)
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, settings)
  }

  function toggleLight() {
    setLevel(level > 0 ? 0 : lastOn)
  }

  function setLevel(next) {
    level = next
    if (next > 0 && next !== lastOn) {
      lastOn = next
      save({ level: next })
    }
    setProc.command = ["brightnessctl", "-q", "-d", device, "set", String(next)]
    setProc.running = true
  }

  function read(raw) {
    var parts = String(raw || "").trim().split(/\s+/)
    if (parts.length < 2) return
    var now = parseInt(parts[0])
    var max = parseInt(parts[1])
    if (isNaN(now) || isNaN(max)) return
    maxLevel = max
    level = now
  }

  function readZone(raw) {
    var lines = String(raw || "").trim().split("\n")
    zone = lines[0] || ""
    var c = Model.parseIso6709(lines[1] || "")
    lat = c ? c.lat : NaN
    lon = c ? c.lon : NaN
    checkSky(false)
  }

  function computePlan() {
    return Model.schedule(new Date(), {
      onMin: Model.parseClock(onTime),
      offMin: Model.parseClock(offTime),
      lat: lat, lon: lon, leadMinutes: leadMinutes
    })
  }

  // applyNow: put the light where the schedule says right away (used when
  // the mode or the times change), instead of waiting for the next flip.
  function checkSky(applyNow) {
    plan = sunsetMode ? computePlan() : null
    if (!plan) { sky = ""; return }
    var now = plan.dark ? "dark" : "light"
    // First reading after start also applies, so the light matches the
    // schedule after a reboot.
    if (applyNow || now !== sky) setLevel(plan.dark ? lastOn : 0)
    sky = now
  }

  function setSunsetMode(on) {
    save({ sunsetMode: on })
  }

  // A typed time overrides the sun for that side; clearing it goes back.
  function setTime(key, text) {
    if (text.trim() !== "" && Model.parseClock(text) < 0) return false
    var patch = {}
    patch[key] = text.trim()
    save(patch)
    return true
  }

  readonly property bool automatic: onTime === "" && offTime === ""

  function resetAutomatic() {
    save({ onTime: "", offTime: "" })
  }

  function sunText(kind) {
    if (!plan) return ""
    return Model.clock12(kind === "on" ? plan.nextOn : plan.nextOff)
  }

  Process {
    id: readProc
    command: ["bash", "-c",
      "cat /sys/class/leds/" + root.device + "/brightness /sys/class/leds/" + root.device + "/max_brightness"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.read(text) }
  }

  Process {
    id: zoneProc
    command: ["bash", "-c",
      "tz=$(readlink /etc/localtime | sed 's#.*zoneinfo/##'); echo \"$tz\"; " +
      "awk -v tz=\"$tz\" '$3==tz {print $2; exit}' /usr/share/zoneinfo/zone.tab /usr/share/zoneinfo/zone1970.tab"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.readZone(text) }
  }

  Process {
    id: setProc
    onExited: readProc.running = true
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!readProc.running) readProc.running = true
  }

  // Timezone check every 10 minutes catches travel; the schedule check
  // every minute catches sunset.
  Timer {
    interval: 600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!zoneProc.running) zoneProc.running = true
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.checkSky(false)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    // Same three shades as the menu: dark, dim, bright.
    foreground: {
      var c = root.bar ? root.bar.barForeground : Color.foreground
      var a = root.level === 0 ? 0.3 : root.level >= root.maxLevel ? 1.0 : 0.6
      return Qt.rgba(c.r, c.g, c.b, a)
    }
    tooltipText: root.level === 0 ? "Keyboard light off"
      : root.level >= root.maxLevel ? "Keyboard light high" : "Keyboard light low"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggle()
      else root.toggleLight()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(280))
    contentHeight: panel.fittedContentHeight(menuColumn.implicitHeight)

    ColumnLayout {
      id: menuColumn
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.spacing.sm

      Text {
        Layout.fillWidth: true
        Layout.bottomMargin: Style.spacing.sm
        text: "ThinkPad keyboard backlight"
        color: Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      // Brightness as keyboards: dark, dimmer, bright. The current one is underlined.
      RowLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
          model: [
            { shade: 0.25, value: 0, tip: "Off" },
            { shade: 0.6, value: 1, tip: "Low" },
            { shade: 1.0, value: 2, tip: "High" }
          ]
          delegate: Item {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: Style.space(34)

            Text {
              anchors.centerIn: parent
              text: "󰌌"
              color: Color.foreground
              opacity: modelData.shade
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.heading
            }
            Rectangle {
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(22)
              height: Math.max(1, Style.space(2))
              color: Color.foreground
              visible: root.level === modelData.value
            }
            MouseArea {
              id: levelMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.setLevel(modelData.value)
            }
            PanelToolTip {
              visible: levelMouse.containsMouse
              text: modelData.tip
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.spacing.sm

        Text {
          Layout.fillWidth: true
          text: "Turn on at sundown"
          color: Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
        ToggleSwitch {
          checked: root.sunsetMode
          onToggled: root.setSunsetMode(!root.sunsetMode)
        }
      }

      Repeater {
        model: [
          { label: "Backlight on", key: "onTime", side: "on", lit: true },
          { label: "Backlight off", key: "offTime", side: "off", lit: false }
        ]
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          visible: root.sunsetMode
          spacing: Style.space(10)

          Text {
            text: "󰌌"
            color: Color.foreground
            opacity: modelData.lit ? 1.0 : 0.3
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.heading
          }
          Text {
            Layout.fillWidth: true
            text: modelData.label
            color: Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
          // Empty field shows the sun time as placeholder; typing a time
          // overrides it, clearing the field goes back to the sun.
          // Typing breaks the text binding, so push saved changes (like
          // the Automatic button clearing it) back into the field.
          readonly property string saved: root[modelData.key]
          onSavedChanged: timeField.text = saved

          TextField {
            id: timeField
            Layout.preferredWidth: Style.space(100)
            text: root[modelData.key]
            placeholderText: root.sunText(modelData.side)
            foreground: Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            onEditingFinished: if (!root.setTime(modelData.key, text)) text = root[modelData.key]
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.spacing.sm
        visible: root.sunsetMode

        Text {
          text: "󰇧"
          color: Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.heading
        }
        Text {
          Layout.fillWidth: true
          Layout.leftMargin: Style.space(10) - Style.spacing.sm
          text: root.zone.split("/").pop().replace(/_/g, " ")
          color: Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
        Button {
          Layout.preferredWidth: Style.space(100)
          text: "Automatic"
          bordered: true
          selected: root.automatic
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: root.resetAutomatic()
        }
      }
    }
  }
}
