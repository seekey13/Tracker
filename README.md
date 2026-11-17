# Tracker

Goblin dailies, Palalumin quests, the Aether Traveler's weekly item, AMAN training targets, and Magian trials in one Vanacore panel. CatsEye XI only.

Seekey. Daily tracking began in Dewin's Goldilox addon.

https://github.com/seekey13/Tracker

## Install

Load `Tracker`. Unload `goldilox-ui` and `AMANTracker` first. Those addons read the same chat, so running them with Tracker records everything twice.

The first time a character logs in, Tracker copies that character's `Goldilox-UI` and `AMANTracker` settings. Later play is saved only in Tracker. The defaults profile is not a character and is left alone.

## Window

The panel lists Goblin Dailies, then Palalumin Quests, then Aether Traveler, then AMAN Targets, then Trial. A section hides once that work is finished. Each section sits apart from the next, so its rows stay with that header. Hold Shift to drag. The title, the close mark, the frame, the gaps between sections, and a collapsed section header fade out until the mouse is over the window. An open section stays opaque. Then the whole window comes back. The cog left of the x opens a scale slider, 0.5x to 2x. The window takes the new size once the slider is let go, and the size is saved for the character. The x closes the window until the next AMAN confirm, a restored hunt, or `/tracker ui`.

Closing the window is not remembered.

## Commands

- `/tracker` shows this help
- `/tracker ui` shows or hides the window
- `/tracker dailies` prints goblin, Palalumin, and Aether Traveler status
- `/tracker clear` clears the AMAN regime only
- `/tracker debug` toggles death-packet logging
- `/tracker test <name>` checks a mob name against the regime
- `/tracker trial` prints Magian trial progress
- `/tracker trial <number> <total>` sets how many objectives a trial has in all
- `/tracker trial clear [number]` drops one trial, or every trial
- `/at` accepts the same AMAN subcommands
- `/goldilox` and `/dailies` print status. Add `ui` to toggle the window

The day rolls at Japanese midnight. That clears the dailies and leaves the AMAN regime alone.

A goblin who says "Congratulations!" or "You've already completed this quest today!" has finished that daily. That row leaves the panel. Once every daily is finished and the Goldilox reward is collected, the section hides.

The Aether Traveler in Port Jeuno wants three of one item each week. Hear his weekly special and the item shows under Aether Traveler with how many you carry. Within 3 yalms of him with all three, a Trade button hands them over. Once he keeps them, the row asks "Store Aether Fragments?" with how many his reward added, and its Trade button hands those fragments back to him to keep. Once he keeps them, or they leave your inventory, the section hides. The request is kept until midnight Monday, Japanese time.

Each Magian trial gets a row under Trial, such as Trial-1010, with the objectives done out of the total. The game's line, "Trial 1010: 155 objectives remain.", gives only what is left. The first line heard for a trial comes after its first objective, so Tracker takes the total as one more than that line leaves. For a trial that was already under way when Tracker first heard it, set the real total with `/tracker trial 1010 500`. "You have completed Trial 1010." fills the row and asks you to report to a Magian Moogle. A trade to a Magian Moogle drops every finished trial. Trials stay through the day roll.
