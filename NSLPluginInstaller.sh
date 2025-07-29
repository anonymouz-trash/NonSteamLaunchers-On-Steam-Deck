#!/bin/bash

# ENVIRONMENT VARIABLES
logged_in_user=$(logname 2>/dev/null || whoami)
logged_in_home=$(eval echo "~${logged_in_user}")

# Function to prompt for sudo password
prompt_for_sudo() {
  password=$(zenity --password --title="Authentication Required" --text="Please enter your password to proceed with installation/update.")

  # Validate password
  echo "$password" | sudo -S -v >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    zenity --error --text="Incorrect password or sudo failed. Exiting."
    exit 1
  fi
}

# Function to switch to Game Mode
switch_to_game_mode() {
  echo "Switching to Game Mode..."
  rm -rf "${logged_in_home}/.config/systemd/user/nslgamescanner.service"
  unlink "${logged_in_home}/.config/systemd/user/default.target.wants/nslgamescanner.service"
  systemctl --user daemon-reload
  qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
}

# Function to display Zenity messages
show_message() {
  zenity --notification --text="$1" --timeout=1
}

show_update_message() {
  zenity --notification --text="Updating from $1 to $2..." --timeout=5
}

# Set URLs and paths
REPO_URL="https://github.com/moraroy/NonSteamLaunchersDecky/archive/refs/heads/main.zip"
GITHUB_URL="https://raw.githubusercontent.com/moraroy/NonSteamLaunchersDecky/refs/heads/main/package.json"
LOCAL_DIR="${logged_in_home}/homebrew/plugins/NonSteamLaunchers"

# Ask the user
zenity --question --text="Would you like to install or update the NonSteamLaunchers Decky Plugin?" --title="Install/Update Plugin" --ok-label="Yes" --cancel-label="No"
if [ $? -eq 1 ]; then
  echo "User canceled the installation/update."
  exit 0
fi

# Prompt for sudo once
prompt_for_sudo

# Check for existing directories
DECKY_LOADER_EXISTS=false
NSL_PLUGIN_EXISTS=false

if [ -d "${logged_in_home}/homebrew/plugins" ]; then
  DECKY_LOADER_EXISTS=true
fi

if [ -d "$LOCAL_DIR" ] && [ -n "$(ls -A "$LOCAL_DIR")" ]; then
  NSL_PLUGIN_EXISTS=true
fi

# Version extraction from JSON (no jq)
extract_version() {
  grep -o '"version": *"[^"]*"' "$1" | sed 's/.*"version": *"\([^"]*\)".*/\1/'
}

fetch_github_version() {
  version=$(curl -s "$GITHUB_URL" | grep -o '"version": *"[^"]*"' | sed 's/.*"version": *"\([^"]*\)".*/\1/')
  echo "$version"
}

fetch_local_version() {
  if [ -f "$LOCAL_DIR/package.json" ]; then
    version=$(extract_version "$LOCAL_DIR/package.json")
    echo "$version"
  fi
}

compare_versions() {
  if [ ! -f "$LOCAL_DIR/package.json" ]; then
    return 1
  fi

  local_version=$(fetch_local_version)
  github_version=$(fetch_github_version)

  if [ "$local_version" == "$github_version" ]; then
    return 0
  else
    return 1
  fi
}

# Main logic
set +x

# Sanity checks
if $DECKY_LOADER_EXISTS; then
  if ! $NSL_PLUGIN_EXISTS; then
    zenity --info --text="Decky Loader is detected but no NSL plugin found. It will now be injected into Game Mode."
  fi
else
  zenity --error --text="Decky Loader not found. Please install it and re-run the script."
  exit 1
fi

# Version check
compare_versions
if [ $? -eq 0 ]; then
  show_message "No update needed. The plugin is already up-to-date."
else
  local_version=$(fetch_local_version)
  github_version=$(fetch_github_version)
  show_update_message "$local_version" "$github_version"

  if $NSL_PLUGIN_EXISTS; then
    show_message "NSL Plugin detected. Deleting and updating..."
    echo "$password" | sudo -S rm -rf "$LOCAL_DIR"
  fi

  show_message "Creating base directory and setting permissions..."

  echo "$password" | sudo -S mkdir -p "$LOCAL_DIR"
  echo "$password" | sudo -S chmod -R u+rw "$LOCAL_DIR"
  echo "$password" | sudo -S chown -R "$logged_in_user:$logged_in_user" "$LOCAL_DIR"

  curl -L "$REPO_URL" -o /tmp/NonSteamLaunchersDecky.zip
  unzip -o /tmp/NonSteamLaunchersDecky.zip -d /tmp/
  cp -r /tmp/NonSteamLaunchersDecky-main/* "$LOCAL_DIR"

  rm -rf /tmp/NonSteamLaunchersDecky*
fi

set -x
cd "$LOCAL_DIR"

# Ask to switch to Game Mode
zenity --question --text="Plugin installed or updated. Do you want to switch to Game Mode now?" --title="Switch to Game Mode?" --ok-label="Yes" --cancel-label="No"
if [ $? -eq 0 ]; then
  switch_to_game_mode
else
  show_message "Remaining in Desktop Mode."
fi
