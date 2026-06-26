#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Agency
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🖥️

PROFILE="Agency"

osascript <<EOF
tell application "iTerm"
    activate
    create window with profile "$PROFILE"
end tell
EOF
