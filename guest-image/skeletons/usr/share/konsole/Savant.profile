# Savant Konsole profile — factory default for the guest image.
#
# The traffic-lights terminal: void background, cyan accents, the three
# semantic lights for directory/link/deletion coloring. Referenced from
# konsolerc's DefaultProfile (see 20-savantos-kdeglobals below via kwriteconfig
# in finalize; file lives in /usr/share/konsole so every user inherits it).

[General]
Name=Savant
Command=/bin/bash

[Appearance]
ColorScheme=Savant
Font=Hack,10,-1,5,50,0,0,0,0,0

[Scrolling]
ScrollBarPosition=1
