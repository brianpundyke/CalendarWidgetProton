#!/usr/bin/env bash
# Install or update the Proton Agenda desktop widget for the current user.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/proton-agenda"
VENV="$HOME/.local/share/proton-agenda/venv"   # main.qml expects this exact path

echo "==> Python helper environment ($VENV)"
if [ ! -x "$VENV/bin/python" ]; then
    mkdir -p "$DATA"
    python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q --disable-pip-version-check --upgrade icalendar recurring-ical-events

echo "==> Checking the calendar can be read"
if "$VENV/bin/python" "$HERE/package/contents/code/agenda.py" --days 1 | grep -q '"error": ""'; then
    echo "    ok"
else
    echo "    warning: helper reported a problem (the widget will show the message)"
fi

echo "==> Plasma widget"
if kpackagetool6 -t Plasma/Applet --list | grep -qx 'local.protonagenda'; then
    kpackagetool6 -t Plasma/Applet --upgrade "$HERE/package"
    echo "    Updated. Restart Plasma to load the new version:"
    echo "      systemctl --user restart plasma-plasmashell"
else
    kpackagetool6 -t Plasma/Applet --install "$HERE/package"
    echo "    Installed. Right-click the desktop → Add or Manage Widgets → search \"Proton Agenda\"."
fi
