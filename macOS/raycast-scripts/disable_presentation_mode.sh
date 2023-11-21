#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Disable Presentation mode
# @raycast.mode compact

# Optional parameters:
# @raycast.needsConfirmation false

# Documentation:
# @raycast.description Disable Presentation mode
# @raycast.icon images/teams-icon.icns
# @raycast.author Eric van Wijk
# @raycast.authorURL https://github.com/ericvan

# Turn off do not Disturb
defaults write com.apple.ncprefs.plist dnd_prefs -data 62706C6973743030D5010203040506070707075B646E644D6972726F7265645F100F646E64446973706C6179536C6565705F101E72657065617465644661636574696D6543616C6C73427265616B73444E445E646E64446973706C61794C6F636B5F10136661636574696D6543616E427265616B444E44090808080808131F3152617778797A7B0000000000000101000000000000000B0000000000000000000000000000007C
killall ControlCenter && killall usernoted

# Show dock & menu bar
# defaults write NSGlobalDomain _HIHideMenuBar -bool false #; killall Finder
osascript -e 'tell application "System Events" to tell dock preferences to set autohide menu bar to false'
osascript -e 'tell application "System Events" to set the autohide of the dock preferences to false'
killall Finder

# Show desktop icons
defaults write com.apple.finder CreateDesktop -bool true; killall -HUP Finder

# Lighing
litra-off