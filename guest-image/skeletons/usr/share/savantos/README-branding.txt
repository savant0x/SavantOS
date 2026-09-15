SavantOS desktop identity
=========================

Color system: Savant Cyberpunk palette, canonical source
savant-code cli/src/utils/theme-system/palette.ts (dark theme):
  background  #050508   deep void
  surface     #0b0b11
  hover       #14141c
  foreground  #e4e4e8
  muted       #8f8f99
  accent      #18faf9   cyan
  success     #39ff14   green light
  warning     #ff9500   orange light
  error       #ff2d55   red light

Applied system-wide via /usr/share/color-schemes/Savant.colors,
Konsole scheme/profile in /usr/share/konsole/, and the factory
user config planted in /etc/skel + /home/savant.

Wallpapers: deterministic traffic-lights renders (three glowing
dots on the void, cyan horizon). Generator: builder tree
wallpapers/gen-wallpaper.py; output embedded at
/usr/share/wallpapers/savant/.

There is no Omarchy branding anywhere in this image. The upstream
project was forked and fully rebranded; any upstream string that
surfaces in the UI is a bug — report it against the builder
(guest-image/), not the guest.
