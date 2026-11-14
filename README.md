# Proton Agenda – Plasma 6 desktop widget

Shows upcoming appointments from a Proton Calendar share link as a list grouped by day.

## How it works
- `package/contents/code/agenda.py` downloads the iCal feed, expands recurring events
  (`recurring-ical-events`) and prints JSON. With no custom link set, it reads the link from
  KOrganizer's Akonadi iCal subscription (`~/.config/akonadi_ical_resource_*rc`, key `Path`).
- The last good download is cached at `~/.cache/proton-agenda/calendar.ics` for offline use.
- `package/contents/ui/main.qml` runs the helper on a timer and draws the list.
- Python libraries live in a private venv at `~/.local/share/proton-agenda/venv`.

## Install / update
    ./install.sh
After an update: `systemctl --user restart plasma-plasmashell`.

Then right-click the desktop → *Add or Manage Widgets* → **Proton Agenda**.

## Settings (right-click widget → Configure)
Days to show (14), refresh interval (15 min), dim finished events, optional custom link.

## Test without adding to the desktop
    plasmawindowed local.protonagenda

## Uninstall
    kpackagetool6 -t Plasma/Applet --remove local.protonagenda
    rm -rf ~/.local/share/proton-agenda ~/.cache/proton-agenda
