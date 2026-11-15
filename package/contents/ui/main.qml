import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property string errorText: ""
    property bool stale: false
    property string staleReason: ""
    property string updated: ""
    property bool loading: false
    property bool loadedOnce: false
    property date now: new Date()
    property string todayKey: dateKey(new Date())

    readonly property bool dimPast: Plasmoid.configuration.dimPast

    Plasmoid.icon: "view-calendar-agenda"
    // backgroundMode: 0 = Plasma theme, 1 = custom colour, 2 = transparent (desktop only)
    readonly property bool ownBackground: !inPanel && Plasmoid.configuration.backgroundMode !== 0
    readonly property bool customBackground: !inPanel && Plasmoid.configuration.backgroundMode === 1
    Plasmoid.backgroundHints: ownBackground
        ? PlasmaCore.Types.NoBackground
        : PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground

    readonly property color themeTextColor: Kirigami.Theme.textColor

    function isLight(c) {
        // Blend with a mid-grey wallpaper guess when translucent.
        const a = c.a, mix = v => v * a + 0.5 * (1 - a)
        return 0.2126 * mix(c.r) + 0.7152 * mix(c.g) + 0.0722 * mix(c.b) > 0.55
    }
    // Full list on the desktop; a calendar icon with a popup in panels / system tray.
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                    || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    toolTipMainText: i18n("Agenda")
    toolTipSubText: nextEventText()

    // "Next: Title – Wed 11:00" (or "Now: …") for the panel icon's tooltip.
    function nextEventText() {
        const _ = now  // re-evaluate as time passes
        for (let i = 0; i < eventModel.count; i++) {
            const ev = eventModel.get(i)
            const s = parseLocal(ev.start), e = parseLocal(ev.end)
            if (e <= now) continue
            if (s <= now) return i18n("Now: %1", ev.title)
            const when = ev.day === todayKey
                ? (ev.allDay ? i18n("today") : fmtTime(s))
                : s.toLocaleDateString(Qt.locale(), "ddd") + (ev.allDay ? "" : " " + fmtTime(s))
            return i18n("Next: %1 – %2", ev.title, when)
        }
        return loadedOnce ? i18n("Nothing scheduled") : ""
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        },
        PlasmaCore.Action {
            text: i18n("Open KOrganizer")
            icon.name: "korganizer"
            onTriggered: root.openKOrganizer()
        }
    ]

    ListModel { id: eventModel }

    // ---- helpers ------------------------------------------------------------

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function dateKey(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

    // Parse "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" as *local* time.
    function parseLocal(s) {
        const m = /^(\d+)-(\d+)-(\d+)(?:T(\d+):(\d+))?/.exec(s)
        return new Date(+m[1], +m[2] - 1, +m[3], m[4] ? +m[4] : 0, m[5] ? +m[5] : 0)
    }

    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    readonly property string scriptPath:
        decodeURIComponent(Qt.resolvedUrl("../code/agenda.py").toString().replace(/^file:\/\//, ""))

    function command() {
        let cmd = '"$HOME/.local/share/proton-agenda/venv/bin/python" ' + shellQuote(scriptPath)
                + " --days " + Plasmoid.configuration.days
        if (Plasmoid.configuration.customUrl.trim() !== "")
            cmd += " --url " + shellQuote(Plasmoid.configuration.customUrl.trim())
        return cmd
    }

    function refresh() {
        if (loading) return
        loading = true
        runner.connectSource(command())
    }

    function openKOrganizer() {
        launcher.connectSource("kstart korganizer")
    }

    // Ask KOrganizer (over D-Bus, starting it if needed) to show this occurrence,
    // then raise its window. Falls back to just opening KOrganizer.
    function openEvent(uid, startStr) {
        if (!uid) { openKOrganizer(); return }
        const d = parseLocal(startStr)
        // QDateTime as D-Bus struct: ((y,m,d),(h,min,s,ms),timeSpec 0 = local time)
        const occurrence = "((" + d.getFullYear() + "," + (d.getMonth() + 1) + "," + d.getDate() + "),("
                         + d.getHours() + "," + d.getMinutes() + ",0,0),0)"
        launcher.connectSource(
            "gdbus call --session --dest org.kde.korganizer --object-path /Calendar"
            + " --method org.kde.calendar.Calendar.showIncidenceByUid "
            + shellQuote(uid) + " " + shellQuote(occurrence) + " '' >/dev/null 2>&1; kstart korganizer")
    }

    function handleResult(exitCode, stdout, stderr) {
        loading = false
        loadedOnce = true
        let data
        try {
            data = JSON.parse(stdout)
        } catch (e) {
            errorText = exitCode === 127
                ? i18n("Helper not installed. Run install.sh from the widget's project folder.")
                : i18n("Agenda helper failed: %1", (stderr || stdout || ("exit code " + exitCode)).trim().split("\n").pop())
            return
        }
        errorText = data.error || ""
        stale = !!data.stale
        staleReason = data.staleReason || ""
        updated = data.updated || ""
        eventModel.clear()
        for (const day of data.days) {
            for (const ev of day.events) {
                eventModel.append({
                    day: day.date,
                    uid: ev.uid || "",
                    title: ev.title,
                    location: ev.location,
                    allDay: ev.allDay,
                    start: ev.start,
                    end: ev.end
                })
            }
        }
    }

    function dayLabel(key) {
        const d = parseLocal(key)
        const nice = d.toLocaleDateString(Qt.locale(), "ddd d MMM")
        const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1)
        if (key === todayKey) return i18n("Today") + "  ·  " + nice
        if (key === dateKey(tomorrow)) return i18n("Tomorrow") + "  ·  " + nice
        return d.toLocaleDateString(Qt.locale(), "dddd d MMMM")
    }

    function fmtTime(d) { return d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat) }

    // Time text for an event as shown under a particular day heading.
    function timeLabel(dayKey, allDay, startStr, endStr) {
        if (allDay) return i18n("All day")
        const dayStart = parseLocal(dayKey)
        const dayEnd = new Date(dayStart); dayEnd.setDate(dayEnd.getDate() + 1)
        const s = parseLocal(startStr), e = parseLocal(endStr)
        const startsToday = s >= dayStart
        const endsToday = e <= dayEnd
        if (startsToday && endsToday)
            return e > s ? fmtTime(s) + " – " + fmtTime(e) : fmtTime(s)
        if (startsToday)
            return fmtTime(s) + " – " + e.toLocaleDateString(Qt.locale(), "ddd") + " " + fmtTime(e)
        if (endsToday)
            return i18n("until %1", fmtTime(e))
        return i18n("All day")
    }

    function isPast(endStr) { return parseLocal(endStr) <= now }

    // ---- data sources & timers ----------------------------------------------

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            root.handleResult(data["exit code"], data["stdout"], data["stderr"])
        }
    }

    P5Support.DataSource {
        id: launcher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMinutes) * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Keeps "finished" dimming and Today/Tomorrow labels current; refetches at midnight.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            root.now = new Date()
            const k = root.dateKey(root.now)
            if (k !== root.todayKey) {
                root.todayKey = k
                root.refresh()
            }
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onDaysChanged() { root.refresh() }
        function onCustomUrlChanged() { root.refresh() }
    }

    // ---- UI -------------------------------------------------------------------

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24

        // With a custom colour, pick dark or light text for contrast.
        Kirigami.Theme.inherit: !root.customBackground
        Kirigami.Theme.textColor: root.customBackground
            ? (root.isLight(Plasmoid.configuration.backgroundColor) ? "#232629" : "#eff0f1")
            : root.themeTextColor

        Rectangle {
            anchors.fill: parent
            visible: root.customBackground
            color: Plasmoid.configuration.backgroundColor
            radius: Kirigami.Units.cornerRadius * 2
        }

        ColumnLayout {
            anchors.fill: parent
            // Plasma's own background adds padding; supply it ourselves otherwise.
            anchors.margins: root.ownBackground ? Kirigami.Units.largeSpacing : 0
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 2
                    text: i18n("Agenda")
                    elide: Text.ElideRight
                }
                PlasmaComponents3.BusyIndicator {
                    visible: root.loading
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.loading
                    onClicked: root.refresh()
                    QQC2.ToolTip.text: root.updated
                        ? i18n("Refresh (last updated %1)", root.parseLocal(root.updated).toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
                        : i18n("Refresh")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: eventModel.count > 0 && root.errorText === ""
                // Avoid a horizontal scrollbar; content wraps instead.
                PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                ListView {
                    id: list
                    model: eventModel
                    clip: true
                    spacing: Kirigami.Units.smallSpacing
                    boundsBehavior: Flickable.StopAtBounds

                    section.property: "day"
                    section.criteria: ViewSection.FullString
                    section.delegate: ColumnLayout {
                        required property string section
                        width: ListView.view.width
                        spacing: 0
                        Item { implicitHeight: Kirigami.Units.smallSpacing }
                        Kirigami.Heading {
                            Layout.fillWidth: true
                            level: 4
                            text: root.dayLabel(section)
                            color: section === root.todayKey ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                            elide: Text.ElideRight
                        }
                        Kirigami.Separator {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            Layout.bottomMargin: Kirigami.Units.smallSpacing
                            opacity: 0.5
                        }
                    }

                    delegate: Item {
                        id: row
                        required property string day
                        required property string uid
                        required property string title
                        required property string location
                        required property bool allDay
                        required property string start
                        required property string end

                        readonly property bool past: root.dimPast && root.isPast(end)

                        width: ListView.view.width
                        implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 2
                        opacity: past ? 0.45 : 1

                        Rectangle {
                            anchors.fill: parent
                            radius: Kirigami.Units.cornerRadius
                            color: Kirigami.Theme.highlightColor
                            opacity: mouse.containsMouse ? 0.15 : 0
                        }

                        RowLayout {
                            id: content
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Kirigami.Units.smallSpacing
                            anchors.rightMargin: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing * 2

                            Rectangle {
                                Layout.fillHeight: true
                                implicitWidth: 3
                                radius: 1.5
                                color: Kirigami.Theme.highlightColor
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: row.title
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: root.timeLabel(row.day, row.allDay, row.start, row.end)
                                          + (row.location ? "  ·  " + row.location : "")
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.75
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openEvent(row.uid, row.start)
                        }
                    }
                }
            }

            PlasmaExtras.PlaceholderMessage {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignCenter
                Layout.margins: Kirigami.Units.largeSpacing
                visible: root.loadedOnce && (root.errorText !== "" || eventModel.count === 0)
                iconName: root.errorText !== "" ? "dialog-warning" : "view-calendar-agenda"
                text: root.errorText !== ""
                      ? root.errorText
                      : i18np("Nothing scheduled for the next day", "Nothing scheduled for the next %1 days",
                              Plasmoid.configuration.days)
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.stale && root.errorText === ""
                text: i18n("Offline: showing the last saved copy")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.neutralTextColor
                elide: Text.ElideRight
                QQC2.ToolTip.text: root.staleReason
                QQC2.ToolTip.visible: staleHover.hovered && root.staleReason !== ""
                HoverHandler { id: staleHover }
            }
        }
    }
}
