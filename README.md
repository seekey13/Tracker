# Tracker

Goblin dailies, Palalumin quests, and AMAN training targets in one Vanacore panel. CatsEye XI only.

Seekey. Daily tracking began in Dewin's Goldilox addon.

https://github.com/seekey13/Tracker

## Install

Load `Tracker`. Unload `goldilox-ui` and `AMANTracker` first. Those addons read the same chat, so running them with Tracker records everything twice.

The first time a character logs in, Tracker copies that character's `Goldilox-UI` and `AMANTracker` settings. Later play is saved only in Tracker. The defaults profile is not a character and is left alone.

## Window

The panel lists Goblin Dailies, then Palalumin Quests, then AMAN Targets. A section hides once that work is finished. Hold Shift to drag. The cog beside the close mark opens a 0–100 background opacity slider. Text, links, and the teal meters stay solid when the background fades. The x closes the window until the next AMAN confirm, a restored hunt, or `/tracker ui`.

Opacity is remembered. Closing the window is not.

## Commands

- `/tracker` shows this help
- `/tracker ui` shows or hides the window
- `/tracker opacity N` sets background opacity from 0 to 100
- `/tracker dailies` prints goblin and Palalumin status
- `/tracker clear` clears the AMAN regime only
- `/tracker debug` toggles death-packet logging
- `/tracker test <name>` checks a mob name against the regime
- `/at` accepts the same AMAN subcommands
- `/goldilox` and `/dailies` print status. Add `ui` to toggle the window

The day rolls at Japanese midnight. That clears the dailies and leaves the AMAN regime and the opacity alone.
