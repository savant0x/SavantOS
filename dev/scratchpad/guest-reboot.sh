#!/bin/bash
# Guest-side reboot of the disposable dev VM (factory sudoers authorizes this
# in-guest; nothing privileged happens on the host). Restores a clean Plasma
# session after the theme-eval crash-loop experiment.
sudo systemctl reboot
