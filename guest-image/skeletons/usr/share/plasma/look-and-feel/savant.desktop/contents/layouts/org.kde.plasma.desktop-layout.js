// Savant desktop layout — installed with the Savant Look & Feel package.
//
// The ONLY panel source (the hand-rolled factory appletsrc is retired):
// plasma-apply-lookandfeel runs this script on every L&F apply, so the
// panel converges to exactly this shape on first login and after any
// drift. Bottom bar, fixed 48px, always visible. Left: Savant kickoff
// (traffic-lights start icon). Next: pinned icons-only task manager.
// Right: system tray + digital clock (12-hour, Windows-like).
//
// Config mechanism: Panel.addWidget(name) takes NO config argument — a
// second object-literal argument is silently dropped, which is why the
// start button kept the stock KDE icon (verified against the Plasma
// scripting API docs and the live stock-icon symptom, 2026-09-13). Applet
// config is written through the returned Widget: currentConfigGroup +
// writeConfig.

// Converge: remove every pre-existing panel (fresh profiles carry a
// default; older factory states carried duplicates).
for (var i = panels().length - 1; i >= 0; i--) {
    panels()[i].remove();
}

var panel = new Panel("org.kde.panel");
panel.alignment = "left";
panel.location = "bottom";
panel.hiding = "none";
panel.height = 48;
panel.floating = false;

// Savant menu, bottom-left (Windows "start button" position).
var kickoff = panel.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "savant-start");
kickoff.writeConfig("favorites", "preferred://browser,applications:chromium.desktop,applications:cursor.desktop,applications:savant-code.desktop,applications:org.kde.konsole.desktop,applications:org.kde.dolphin.desktop,applications:featherpad.desktop,applications:org.kde.kate.desktop,applications:org.kde.systemsettings.desktop");

// Pinned launchers (icons-only task manager: running + pinned apps).
var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "applications:chromium.desktop,applications:cursor.desktop,applications:savant-code.desktop,applications:org.kde.konsole.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.kate.desktop");

// Expanding spacer pushes tray/clock right.
panel.addWidget("org.kde.plasma.panelspacer");

// System tray with the standard gadget set.
panel.addWidget("org.kde.plasma.systemtray");

// Clock, far right: 12-hour, no seconds, date on but COMPACT — the stock
// second line renders the long locale form ("09/15/2026"), which is wide
// and redundant (FID-2026-0915-006 D1). Custom format reads "Mon 15 Sep".
// The 12/24h key is use24hFormat (enum string: automatic | 12h | 24h).
var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["General"];
clock.writeConfig("use24hFormat", "12h");
clock.writeConfig("showSeconds", false);
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd d MMM");

// Desktops: image wallpaper (the Savant traffic-lights render). The
// wallpaper config lives at [Wallpaper][org.kde.image][General] under the
// containment group — the bare ["Wallpaper"] group form wrote a stray key
// the image plugin ignores.
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
    desktopsArray[j].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktopsArray[j].writeConfig("Image", "file:///usr/share/wallpapers/savant/contents/images/savant-traffic-lights.png");
}