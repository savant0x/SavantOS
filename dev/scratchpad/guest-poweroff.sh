#!/bin/bash
# Guest-side clean poweroff of the dev VM (factory sudoers authorizes this
# in-guest; nothing privileged happens on the host).
sudo systemctl poweroff
