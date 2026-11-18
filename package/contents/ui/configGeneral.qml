import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQControls

KCM.SimpleKCM {
    property alias cfg_days: daysSpin.value
    property alias cfg_refreshMinutes: refreshSpin.value
    property alias cfg_customUrl: urlField.text
    property alias cfg_dimPast: dimCheck.checked
    property alias cfg_backgroundMode: bgMode.currentIndex
    property alias cfg_backgroundColor: bgColor.color
    property alias cfg_backgroundOpacity: opacitySlider.value

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: daysSpin
            Kirigami.FormData.label: i18n("Days to show:")
            from: 1
            to: 90
        }
        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh every (minutes):")
            from: 1
            to: 240
        }
        QQC2.CheckBox {
            id: dimCheck
            Kirigami.FormData.label: i18n("Finished events:")
            text: i18n("Dim them")
        }
        QQC2.ComboBox {
            id: bgMode
            Kirigami.FormData.label: i18n("Background:")
            model: [i18n("Plasma theme"), i18n("Custom colour"), i18n("Transparent")]
        }
        KQControls.ColorButton {
            id: bgColor
            Kirigami.FormData.label: i18n("Colour:")
            visible: bgMode.currentIndex === 1
            showAlphaChannel: false
            dialogTitle: i18n("Widget background colour")
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Opacity:")
            visible: bgMode.currentIndex === 1
            QQC2.Slider {
                id: opacitySlider
                from: 0
                to: 100
                stepSize: 5
                snapMode: QQC2.Slider.SnapAlways
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            }
            QQC2.Label {
                text: i18nc("opacity percentage", "%1%", Math.round(opacitySlider.value))
                Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
            }
        }
        QQC2.Label {
            visible: bgMode.currentIndex !== 0
            text: i18n("Applies on the desktop. In a panel the popup uses the Plasma theme.")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }
        Kirigami.PasswordField {
            id: urlField
            Kirigami.FormData.label: i18n("Custom calendar link:")
            placeholderText: i18n("Leave empty to use KOrganizer's subscription")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }
        QQC2.Label {
            text: i18n("When empty, the link is read from KOrganizer's iCal subscription each time the widget refreshes.")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }
    }
}
