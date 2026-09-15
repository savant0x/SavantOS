import QtQuick
import org.kde.kwin.decoration

// One Savant traffic-light dot.
//
// Root type is DecorationButton — the framework owns click handling
// entirely (verified against the in-tree plastik reference PlastikButton.qml
// on the pinned Plasma 6.7 guest: no MouseArea, no onClicked, no
// requestToggle* in QML; press/hover/toggled state comes from the C++ button
// API). The previous MouseArea + requestToggleMaximization(mouse.button)
// form broke on Qt 6.7 — implicit signal-parameter injection is gone, so
// `mouse` was undefined and every maximize-dot click threw "Insufficient
// arguments" (kwin journal, 2026-09-13).
//
// Palette is the savant-code traffic-lights identity: success #39ff14,
// warning #ff9500, error #ff2d55 (the "true red", not pink). States are
// painted with opacity only — no theme-engine cache, no SVG, nothing to
// fail silently. width/height and buttonType are assigned by main.qml.
DecorationButton {
    id: root

    property color dotColor: "#39ff14"

    // Resting state is the calm glowing orb; hover brightens and shows the
    // glyph; pressed dims. Availability (closeable/minimizeable/maximizeable)
    // is enforced by the C++ DecorationButton itself.
    readonly property real baseOpacity: 0.92

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.dotColor
        opacity: root.pressed ? 0.55 : (root.hovered ? 1.0 : root.baseOpacity)
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // Soft halo behind the orb (subtle, not harsh).
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 1.7
        height: width
        radius: width / 2
        color: root.dotColor
        opacity: root.hovered ? 0.28 : 0.16
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // Hover marks, drawn geometrically instead of font glyphs.
    //
    // The first cut used Text with anchors.centerIn, which centers the FONT
    // BOX, not the drawn mark — symbol glyphs (□ / ❐ worst: their metrics
    // come from whatever symbol font the guest falls back to) sit
    // asymmetrically inside their boxes, so one dot looked off-center on
    // hover on all four sides (operator report 2026-09-15). Anchored
    // primitives are optically centered by construction, identical across
    // guest fonts, and keep the file's "nothing to fail silently" property.
    readonly property real glyphSpan: root.width * 0.46
    readonly property real glyphStroke: 1.5
    readonly property color glyphColor: "#050508"

    // Close ×: two centered bars rotated ±45° (rotation is around the item
    // center, so both stay perfectly centered).
    Item {
        anchors.centerIn: parent
        visible: root.hovered && root.buttonType === DecorationOptions.DecorationButtonClose
        width: root.glyphSpan
        height: root.glyphSpan
        Rectangle {
            anchors.centerIn: parent
            width: parent.width; height: root.glyphStroke
            radius: root.glyphStroke / 2
            rotation: 45
            color: root.glyphColor
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width; height: root.glyphStroke
            radius: root.glyphStroke / 2
            rotation: -45
            color: root.glyphColor
        }
    }

    // Minimize −: one centered bar.
    Rectangle {
        anchors.centerIn: parent
        visible: root.hovered && root.buttonType === DecorationOptions.DecorationButtonMinimize
        width: root.glyphSpan
        height: root.glyphStroke
        radius: root.glyphStroke / 2
        color: root.glyphColor
    }

    // Maximize □: one centered outline square.
    Rectangle {
        anchors.centerIn: parent
        visible: root.hovered && root.buttonType === DecorationOptions.DecorationButtonMaximizeRestore
                 && !decoration.client.maximized
        width: root.glyphSpan
        height: root.glyphSpan
        radius: 1
        color: "transparent"
        border.color: root.glyphColor
        border.width: root.glyphStroke
    }

    // Restore ❐: two offset outline squares; the front one is filled with the
    // dot color so the overlap reads as occlusion, and the pair is centered
    // as a whole inside the dot.
    Item {
        anchors.centerIn: parent
        visible: root.hovered && root.buttonType === DecorationOptions.DecorationButtonMaximizeRestore
                 && decoration.client.maximized
        width: root.glyphSpan
        height: root.glyphSpan
        Rectangle {
            width: parent.width * 0.62; height: width
            anchors.top: parent.top
            anchors.right: parent.right
            radius: 1
            color: "transparent"
            border.color: root.glyphColor
            border.width: root.glyphStroke
        }
        Rectangle {
            width: parent.width * 0.62; height: width
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            radius: 1
            color: root.dotColor
            border.color: root.glyphColor
            border.width: root.glyphStroke
        }
    }
}