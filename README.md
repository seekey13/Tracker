# Tracker

Goblin dailies, Palalumin quests, the Aether Traveler's weekly item, and AMAN training targets in one Vanacore panel. CatsEye XI only.

Seekey. Daily tracking began in Dewin's Goldilox addon.

https://github.com/seekey13/Tracker

## Install

Load `Tracker`. Unload `goldilox-ui` and `AMANTracker` first. Those addons read the same chat, so running them with Tracker records everything twice.

The first time a character logs in, Tracker copies that character's `Goldilox-UI` and `AMANTracker` settings. Later play is saved only in Tracker. The defaults profile is not a character and is left alone.

## Window

The panel lists Goblin Dailies, then Palalumin Quests, then Aether Traveler, then AMAN Targets. A section hides once that work is finished. Each section sits apart from the next, so its rows stay with that header. Hold Shift to drag. The title, the close mark, the frame, the gaps between sections, and a collapsed section header fade out until the mouse is over the window. An open section stays opaque. Then the whole window comes back. The cog left of the x opens the settings: a scale slider, 0.5x to 2x, and the Mirror setting. The window takes the new size once the slider is let go, and the size is saved for the character. Mirror is Off, Leader, or Follower; a click sets and saves it. The x closes the window until the next AMAN confirm, a restored hunt, or `/tracker ui`.

Closing the window is not remembered.

## Commands

- `/tracker` shows this help
- `/tracker ui` shows or hides the window
- `/tracker dailies` prints goblin, Palalumin, and Aether Traveler status
- `/tracker clear` clears the AMAN regime only
- `/tracker debug` toggles death-packet logging
- `/tracker test <name>` checks a mob name against the regime
- `/tracker mirror` picks one box's AMAN page on every box. See Mirror below
- `/at` accepts the same AMAN subcommands
- `/goldilox` and `/dailies` print status. Add `ui` to toggle the window

The day rolls at Japanese midnight. That clears the dailies and leaves the AMAN regime alone.

A goblin who says "Congratulations!" or "You've already completed this quest today!" has finished that daily. That row leaves the panel. Once every daily is finished and the Goldilox reward is collected, the section hides.

The Aether Traveler in Port Jeuno wants three of one item each week. Hear his weekly special and the item shows under Aether Traveler with how many you carry. Within 3 yalms of him with all three, a Trade button hands them over. Once he keeps them, the row asks "Store Aether Fragments?" with how many his reward added, and its Trade button hands those fragments back to him to keep. Once he keeps them, or they leave your inventory, the section hides. The request is kept until midnight Monday, Japanese time.

## Mirror

Pick an AMAN page on one character and every other box on the same PC picks it too. It is off until turned on, for each character.

Set it from the cog while the window is showing, or by command. On the character you drive:

```
/tracker mirror leader
/tracker mirror on
```

On every other box:

```
/tracker mirror follower
/tracker mirror on
```

Stand each box within 6 yalms of a Field Manual or Grounds Tome in the same zone. They need not share one manual. Pick a page on the leader. When its menu closes, each follower talks to its own book and sends the same answers, about a second behind. A follower's book never opens on its screen, so nothing is left to close. The repeat box carries over, and so does food or a buff bought from the book. A page pick also carries the leader's targets, and each follower's AMAN section shows them once its pick goes through.

A leader never follows, and leader is the role a character starts with. A follower never sends.

- `/tracker mirror` shows the role, the settings, and the channel file
- `/tracker mirror on` and `off` turn it on or off for this character
- `/tracker mirror leader` and `follower` set the role
- `/tracker mirror only <name>` follows that leader alone. `any` follows every leader
- `/tracker mirror strict on` or `off`. On by default
- `/tracker mirror stop` stops following the current pick
- `/tracker mirror dump` toggles packet logging

Only a talk to a Field Manual or Grounds Tome is recorded. Trades, shops, and other npcs are never sent. Backing out of the book sends nothing.

With strict on, the leader sends a pick only when the book printed its "placed here by the A.M.A.N." line, and a follower answers only when its book opens the same menu the leader's did. A follower with a hunt in progress gets a cancel prompt where the page list should be. That prompt opens differently, so the follower backs out of it. Strict off drops both checks.

A follower does nothing, and says why, when it is in another zone, has no book within 6 yalms, is already in a menu, or the pick is more than 20 seconds old. A pick it skips is not tried again; pick again on the leader. When its menu is not the one the leader answered, it backs out and picks nothing.

Levels may differ. Page N is the same page for every level in a zone. A follower outside the page's level range registers it and earns no credit, and says so.

Ashita has no way for one client to message another, so the leader writes each pick to `config\addons\Tracker\mirror_channel.txt` and followers read that file. Boxes on another PC, or run from another Ashita folder, do not see it.

A follower sends packets the player did not, and none of this has run on a live client yet. The first time, try it on two characters at a cheap book with `/tracker mirror dump` on.
