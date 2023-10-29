#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Enable Presentation mode
# @raycast.mode compact

# Optional parameters:
# @raycast.needsConfirmation false

# Documentation:
# @raycast.description Enable Presentation mode
# @raycast.icon images/teams-icon.icns
# @raycast.author Eric van Wijk
# @raycast.authorURL https://github.com/ericvan

# Unmute Audio
set volume without output muted

# Do not Disturb
defaults write com.apple.ncprefs.plist dnd_prefs -data 62706C6973743030D60102030405060708080A08085B646E644D6972726F7265645F100F646E64446973706C6179536C6565705F101E72657065617465644661636574696D6543616C6C73427265616B73444E445875736572507265665E646E64446973706C61794C6F636B5F10136661636574696D6543616E427265616B444E44090808D30B0C0D070F1057656E61626C6564546461746556726561736F6E093341C2B41C4FC9D3891001080808152133545D6C828384858C9499A0A1AAACAD00000000000001010000000000000013000000000000000000000000000000AE
killall ControlCenter && killall usernoted
osascript -e 'tell application "System Events" to tell dock preferences to set autohide to 1'

# Hide dock & menu bar
# defaults write com.apple.Dock autohide-delay -float 0.0001; killall Dock
# defaults write NSGlobalDomain _HIHideMenuBar -bool true #; killall Finder
osascript -e 'tell application "System Events" to tell dock preferences to set autohide menu bar to true'
osascript -e 'tell application "System Events" to set the autohide of the dock preferences to true'
killall Finder

# Hide desktop icons
defaults write com.apple.finder CreateDesktop -bool false; killall -HUP Finder
