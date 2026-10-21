# Tracker

Goblin dailies, Palalumin quests, and AMAN training targets in one Vanacore panel. CatsEye XI only.

Seekey. Daily tracking began in Dewin's Goldilox addon.

https://github.com/seekey13/Tracker

## Install

Load `Tracker`. Unload `goldilox-ui` and `AMANTracker` first. Those addons read the same chat, so running them with Tracker records everything twice.

The first time a character logs in, Tracker copies that character's `Goldilox-UI` and `AMANTracker` settings. Later play is saved only in Tracker. The defaults profile is not a character and is left alone.

## Window

The panel lists Goblin Dailies, then Palalumin Quests, then AMAN Targets. A section hides once that work is finished. Each section sits apart from the next, so its rows stay with that header. Hold Shift to drag. The title, the close mark, the frame, the gaps between sections, and a collapsed section header fade out until the mouse is over the window. An open section stays opaque. Then the whole window comes back. The x closes the window until the next AMAN confirm, a restored hunt, or `/tracker ui`.

Closing the window is not remembered.

## Commands

- `/tracker` shows this help
- `/tracker ui` shows or hides the window
- `/tracker dailies` prints goblin and Palalumin status
- `/tracker clear` clears the AMAN regime only
- `/tracker debug` toggles death-packet logging
- `/tracker test <name>` checks a mob name against the regime
- `/at` accepts the same AMAN subcommands
- `/goldilox` and `/dailies` print status. Add `ui` to toggle the window

The day rolls at Japanese midnight. That clears the dailies and leaves the AMAN regime alone.

A goblin who says "Congratulations!" has finished that daily. That row leaves the panel. Once every daily is finished and the Goldilox reward is collected, the section hides.
