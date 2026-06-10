#!/bin/sh
# Fully uninstalls diffy. Run with: sudo /usr/local/share/diffy/uninstall.sh
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo: sudo $0" >&2
    exit 1
fi

echo "Removing /usr/local/bin/diffy"
rm -f /usr/local/bin/diffy

echo "Removing /usr/local/share/diffy"
rm -rf /usr/local/share/diffy

echo "Forgetting installer receipt"
pkgutil --forget com.taskbase.diffy >/dev/null 2>&1 || true

# Per-user state (window size/position). Resolve the real user's home even
# though we run under sudo.
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(eval echo "~$REAL_USER")
PREFS="$REAL_HOME/Library/Preferences/diffy.plist"
if [ -f "$PREFS" ]; then
    echo "Removing $PREFS"
    rm -f "$PREFS"
fi

echo "diffy has been fully uninstalled."
