## 025

- Added **AGN (Azeroth Navigation System)**, a standalone navigation module with its own waypoints and a rotating brass-and-brown arrow styled for Forever. TomTom and Zygor are optional.
- Paste Wowhead-style `/way` commands directly, including zone names or `#mapID`. Also supports `/tway`, `/tomtomway`, `/wayb`, `/cway`, waypoint listing/removal, and multiline commands through `/ttpaste`. Use `/agn help` for AGN commands.
- Quest tracker circles now select quest destinations directly in AGN. Notification waypoint actions also use AGN when enabled.
- Optional TomTom and Zygor integrations feed one AGN display and hide their original arrows. Zygor targets show a source label and retain guide instructions without flickering between instructions and coordinate names.
- Explicit quest and coordinate selections stay selected when background quest tracking changes. Protected speed values no longer cause ETA errors.
- AGN is click-through. Hold **Shift** to drag it, and use `/agn clear` to clear navigation.
- Module changes now prompt to **Reload now** or wait, using a secure reload button to avoid the blocked-action error.
- Fixed combined action-bar modifiers such as **Ctrl+Shift+1** and **Alt+Ctrl+Shift+1**, including bindings saved by older versions.
