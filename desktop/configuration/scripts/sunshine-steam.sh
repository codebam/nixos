# --- LOGGING ---
# Redirect all output (stdout and stderr) from this script to a log file.
# exec >> "$HOME/sunshine-steam-script.log" 2>&1
# --- END LOGGING ---
echo "=========================================================="
echo "Log started at: $(date)"

# --- DYNAMIC SWAYSOCK DISCOVERY ---
USER_ID=$(id -u)
echo "Attempting to find socket for USER_ID: $USER_ID"
SWAY_SOCKETS=(/run/user/"$USER_ID"/sway-ipc.*.sock)

if [ ${#SWAY_SOCKETS[@]} -eq 0 ]; then
  echo "ERROR: Could not find an active Sway socket in /run/user/$USER_ID/"
  exit 1
fi
export SWAYSOCK="${SWAY_SOCKETS[0]}"
echo "SUCCESS: Found and exported SWAYSOCK=$SWAYSOCK"
# --- END OF DISCOVERY ---

steam -gamepadui &
STEAM_PID=$!
echo "Steam launched with PID: $STEAM_PID"

# --- Wait for window using the combined CLASS and INSTANCE identifiers ---
echo "Waiting for the Steam window (class=steam, instance=steamwebhelper)..."
for i in {1..30}; do
  echo "Attempt #$i to find window..."
  # Use jq to look for a window with BOTH matching properties.
  if swaymsg -t get_tree | jq -e '.. | select(.class? and .class == "steam" and .instance == "steamwebhelper")' > /dev/null; then
    echo "SUCCESS: Steam window found!"
    break
  fi
  sleep 1
done

if [ "$i" = "30" ]; then
  echo "ERROR: Timed out waiting for the Steam window."
else
  # --- Move window using the combined CLASS and INSTANCE identifiers ---
  echo "Attempting to move window to workspace 10."
  sleep 0.5
  swaymsg 'for_window [class="^steam$" instance="^steamwebhelper$"] move container to workspace number 10'
  echo "Move command sent."
fi

echo "Script is now waiting for Steam (PID: $STEAM_PID) to close."
wait $STEAM_PID
echo "Steam has closed. Exiting script."
echo "=========================================================="
