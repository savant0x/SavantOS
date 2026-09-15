import QtQuick
import org.kde.kwin.decoration

// SavantOS traffic-lights window decoration.
//
// Modeled exactly on the in-tree kwin4_decoration_qml_plastik package
// (verified live 2026-09-13: QML decorations load via Library=
// org.kde.kwin.aurorae + Theme=<KPackage id>; supportInformation reports
// "Plugin: org.kde.kwin.aurorae" with no lookup errors).
//
// Windows-11-like geometry: slim titlebar, flat #0b0b11 field, hairline
// bottom border, dots on the RIGHT (DecorationOptions order is display
// order — [min, max, close] renders min-left, close-right).
Decoration {
    id: root

    ColorHelper { id: colorHelper }
    DecorationOptions { id: options; deco: decoration }

    readonly property color voidColor: "#0b0b11"
    readonly property color hairline: "#1c1c26"
    readonly property color titleText: decoration.client.active ? "#e8e8ef" : "#8a8a96"
    readonly property real buttonSize: 16
    readonly property real paddingH: 12
    readonly property real titleBarHeight: 36

    alpha: false

    // Geometry: no side borders (Windows-11-like), real top border.
    Component.onCompleted: {
        borders.setBorders(1);
        borders.setSideBorders(0);
        borders.setTitle(titleBarHeight);
        maximizedBorders.setTitle(titleBarHeight);
        extendedBorders.setAllBorders(0);
    }

    Rectangle {
        anchors.fill: parent
        color: root.voidColor

        // Titlebar strip: the item installed to KWin for drag and
        // double-click-to-maximize hit-testing (mirrors plastik's titleRow).
        Rectangle {
            id: titleBar
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: root.titleBarHeight
            color: root.voidColor

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: root.hairline
            }

            Text {
                id: caption
                textFormat: Text.PlainText
                anchors {
                    left: parent.left
                    right: buttonRow.left
                    rightMargin: 12
                    leftMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                color: root.titleText
                text: decoration.client.caption
                font: options.titleFont
                elide: Text.ElideMiddle
                renderType: Text.NativeRendering
            }

            Row {
                id: buttonRow
                spacing: 10
                anchors {
                    right: parent.right
                    rightMargin: root.paddingH
                    verticalCenter: parent.verticalCenter
                }

                SavantButton {
                    width: root.buttonSize
                    height: root.buttonSize
                    buttonType: DecorationOptions.DecorationButtonMinimize
                    dotColor: "#39ff14"
                }
                SavantButton {
                    width: root.buttonSize
                    height: root.buttonSize
                    buttonType: DecorationOptions.DecorationButtonMaximizeRestore
                    dotColor: "#ff9500"
                }
                SavantButton {
                    width: root.buttonSize
                    height: root.buttonSize
                    buttonType: DecorationOptions.DecorationButtonClose
                    dotColor: "#ff2d55"
                }
            }
        }

        Component.onCompleted: {
            decoration.installTitleItem(titleBar);
        }
    }

    Connections {
        target: decorationSettings
        function onBorderSizeChanged() {
            borders.setBorders(1);
            borders.setSideBorders(0);
            borders.setTitle(root.titleBarHeight);
            maximizedBorders.setTitle(root.titleBarHeight);
        }
    }
}
