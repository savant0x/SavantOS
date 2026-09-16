# Theme eval transcript (raw, verbatim)

18:44:35 # Theme eval v3 2026-09-16T18:44:35+00:00
18:44:35 before: gtk='Breeze' icons=Papirus-Dark kvantum=none
18:44:35 ## base (shipped identity)
18:44:59 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/base.png
18:44:59 capture attempt 1 failed — retrying
18:45:21 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/base.png
18:45:21 capture attempt 2 failed — retrying
18:45:43 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/base.png
18:45:43 capture attempt 3 failed — retrying
18:45:45 CAPTURE FAILED: /tmp/theme-eval/base.png
18:45:45 ## sync + installs (mirrorlist pins the 2026-08-11 snapshot)
:: Synchronizing package databases...
 core downloading...
 extra downloading...
18:45:51 -Sy: OK
18:45:51 portal backend (factory capture-path fix)
warning: xdg-desktop-portal-kde-6.7.4-2 is up to date -- skipping
 there is nothing to do
18:45:51   xdg-desktop-portal-kde: OK
18:45:53 pacman -S --noconfirm kvantum-theme-materia materia-kde materia-gtk-theme orchis-theme graphite
  tela-circle-icon-theme-dark
warning: graphite-1:1.3.15-1 is up to date -- skipping
error: target not found: tela-circle-icon-theme-dark
18:45:53 batch failed — per-package fallback
resolving dependencies...
looking for conflicting packages...

Packages (1) kvantum-theme-materia-20220823-4

Total Download Size:   0.03 MiB
Total Installed Size:  0.48 MiB

:: Proceed with installation? [Y/n] 
:: Retrieving packages...
 kvantum-theme-materia-20220823-4-any downloading...
checking keyring...
checking package integrity...
loading package files...
checking for file conflicts...
checking available disk space...
:: Processing package changes...
installing kvantum-theme-materia...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/Kvantum/
filesystem: 777  package: 755
:: Running post-transaction hooks...
(1/1) Arming ConditionNeedsUpdate...
18:45:54   kvantum-theme-materia: OK
resolving dependencies...
looking for conflicting packages...

Packages (6) qt5-base-5.15.19+kde+r96-1  qt5-declarative-5.15.19+kde+r23-1  qt5-graphicaleffects-5.15.19-1 
  qt5-quickcontrols2-5.15.19+kde+r5-1  qt5-translations-5.15.19-1  materia-kde-20220823-4

Total Download Size:    24.60 MiB
Total Installed Size:  117.81 MiB

:: Proceed with installation? [Y/n] 
:: Retrieving packages...
 qt5-base-5.15.19+kde+r96-1-x86_64 downloading...
 qt5-declarative-5.15.19+kde+r23-1-x86_64 downloading...
 materia-kde-20220823-4-any downloading...
 qt5-translations-5.15.19-1-any downloading...
 qt5-quickcontrols2-5.15.19+kde+r5-1-x86_64 downloading...
 qt5-graphicaleffects-5.15.19-1-x86_64 downloading...
checking keyring...
checking package integrity...
loading package files...
checking for file conflicts...
checking available disk space...
:: Processing package changes...
installing qt5-translations...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
installing qt5-base...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/bin/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/lib/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
Optional dependencies for qt5-base
    qt5-svg: to use SVG icon themes
    qt5-wayland: to run Qt applications in a Wayland session
    postgresql-libs: PostgreSQL driver
    mariadb-libs: MariaDB driver
    unixodbc: ODBC driver
    libfbclient: Firebird/iBase driver
    freetds: MS SQL driver
    gtk3: GTK platform plugin [installed]
    perl: for fixqt4headers and syncqt [installed]
installing qt5-declarative...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/bin/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/lib/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
installing qt5-graphicaleffects...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/lib/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
installing qt5-quickcontrols2...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/lib/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
Optional dependencies for qt5-quickcontrols2
    qt5-graphicaleffects: for the Material style [installed]
installing materia-kde...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/aurorae/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/aurorae/themes/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/color-schemes/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/konsole/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/plasma/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/plasma/look-and-feel/
filesystem: 777  package: 755
Optional dependencies for materia-kde
    materia-gtk-theme: Matching GTK theme
    kvantum-theme-materia: Materia theme for Kvantum Qt style (recommended) [installed]
:: Running post-transaction hooks...
(1/1) Arming ConditionNeedsUpdate...
18:46:09   materia-kde: OK
resolving dependencies...
looking for conflicting packages...

Packages (1) materia-gtk-theme-20210322-4

Total Download Size:   0.33 MiB
Total Installed Size:  5.97 MiB

:: Proceed with installation? [Y/n] 
:: Retrieving packages...
 materia-gtk-theme-20210322-4-any downloading...
checking keyring...
checking package integrity...
loading package files...
checking for file conflicts...
checking available disk space...
:: Processing package changes...
installing materia-gtk-theme...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
:: Running post-transaction hooks...
(1/1) Arming ConditionNeedsUpdate...
18:46:10   materia-gtk-theme: OK
resolving dependencies...
looking for conflicting packages...

Packages (1) orchis-theme-2026_07_07-1

Total Download Size:   0.35 MiB
Total Installed Size:  9.92 MiB

:: Proceed with installation? [Y/n] 
:: Retrieving packages...
 orchis-theme-2026_07_07-1-any downloading...
checking keyring...
checking package integrity...
loading package files...
checking for file conflicts...
checking available disk space...
:: Processing package changes...
installing orchis-theme...
warning: directory permissions differ on /usr/
filesystem: 777  package: 755
warning: directory permissions differ on /usr/share/
filesystem: 777  package: 755
Optional dependencies for orchis-theme
    tela-circle-icon-theme: recommended icon theme
    vimix-cursors: recommended cursors theme
:: Running post-transaction hooks...
(1/1) Arming ConditionNeedsUpdate...
18:46:12   orchis-theme: OK
warning: graphite-1:1.3.15-1 is up to date -- skipping
 there is nothing to do
18:46:12   graphite: OK
error: target not found: tela-circle-icon-theme-dark
18:46:12   tela-circle-icon-theme-dark: FAILED
18:46:12 installed check:
xdg-desktop-portal-kde 6.7.4-2
kvantum-theme-materia 20220823-4
materia-kde 20220823-4
materia-gtk-theme 20210322-4
orchis-theme 2026_07_07-1
graphite 1:1.3.15-1
error: package 'tela-circle-icon-theme-dark' was not found
18:46:12 ## materia-kvantum-dark
18:46:12 apply: kvantummanager --set MateriaDark; gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark'
18:47:12 TIMEOUT(60s): bash -c kvantummanager --set MateriaDark; gsettings set org.gnome.desktop.interface gtk-theme
  'Materia-dark'
18:47:12 TIMEOUT(60s): bash -c kvantummanager --set MateriaDark; gsettings set org.gnome.desktop.interface gtk-theme
  'Materia-dark'
18:47:35 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/materia-kvantum-dark.png
18:47:35 capture attempt 1 failed — retrying
18:47:57 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/materia-kvantum-dark.png
18:47:57 capture attempt 2 failed — retrying
18:48:19 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/materia-kvantum-dark.png
18:48:19 capture attempt 3 failed — retrying
18:48:21 CAPTURE FAILED: /tmp/theme-eval/materia-kvantum-dark.png
18:48:21 revert: revert_kv
18:48:22 ## orchis-gtk-dark
18:48:22 apply: gsettings set org.gnome.desktop.interface gtk-theme 'Orchis-dark'
18:48:45 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/orchis-gtk-dark.png
18:48:45 capture attempt 1 failed — retrying
18:49:07 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/orchis-gtk-dark.png
18:49:07 capture attempt 2 failed — retrying
18:49:29 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/orchis-gtk-dark.png
18:49:29 capture attempt 3 failed — retrying
18:49:31 CAPTURE FAILED: /tmp/theme-eval/orchis-gtk-dark.png
18:49:31 revert: revert_gtk
18:49:32 ## graphite-gtk-dark
18:49:32 apply: gsettings set org.gnome.desktop.interface gtk-theme 'Graphite-dark'
18:49:54 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/graphite-gtk-dark.png
18:49:54 capture attempt 1 failed — retrying
18:50:16 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/graphite-gtk-dark.png
18:50:16 capture attempt 2 failed — retrying
18:50:38 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/graphite-gtk-dark.png
18:50:39 capture attempt 3 failed — retrying
18:50:41 CAPTURE FAILED: /tmp/theme-eval/graphite-gtk-dark.png
18:50:41 revert: revert_gtk
18:50:42 ## tela-circle-icons
18:50:43 apply: kwriteconfig6 --file kdeglobals --group Icons --key Theme Tela-circle-dark
18:51:05 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/tela-circle-icons.png
18:51:05 capture attempt 1 failed — retrying
18:51:27 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/tela-circle-icons.png
18:51:27 capture attempt 2 failed — retrying
18:51:49 TIMEOUT(20s): spectacle -b -n -o /tmp/theme-eval/tela-circle-icons.png
18:51:49 capture attempt 3 failed — retrying
18:51:51 CAPTURE FAILED: /tmp/theme-eval/tela-circle-icons.png
18:51:51 revert: revert_icons
18:51:52 ## revert verification
18:51:52 gtk now: 'Breeze'
18:51:52 icons now: Papirus-Dark
18:51:52 kvantum: none
18:51:53 ## files
total 16
drwxr-xr-x  2 savant savant    80 Sep 16 18:44 .
drwxrwxrwt 15 root   root     400 Sep 16 18:44 ..
-rw-r--r--  1 savant savant  2476 Sep 16 18:51 driver.log
-rw-r--r--  1 savant savant 10732 Sep 16 18:51 notes.md
