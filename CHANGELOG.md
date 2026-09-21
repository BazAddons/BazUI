## 017

**Your settings were still going missing. Update.**

Version 015 moved BazUI's settings somewhere WoW: Forever will actually
read them back. It worked, and then on some characters it quietly stopped.

The reason is that Forever does not have one saved-variables bug, it has
two, and they are not always both switched on. On this build a character's
own file often loads perfectly well while the account file — the one
holding your profiles, your bars, your layout, all of it — does not.
BazUI only ever checked the first, decided the client was healthy, and
handed everything back. The settings then lived nowhere at all and reset
on the next reload.

It looked like a problem with new characters. It was not. A character that
had never been written to got the right answer by luck; one that had been
around a while got the wrong one, and because the account file is shared,
that one character was enough to take the rest of your account with it.

Both files are now asked about separately, and each is looked after on its
own answer. Nothing to switch on, and nothing to redo.

### Fixed

- **Other addons' settings stopped being kept**, for the same reason one
  level up. The list of addons BazUI was carrying was stored inside its
  own account table, so handing that table back deleted the list — and an
  addon that is not on the list is not looked after. The list now lives on
  its own, where nothing else can take it with it. **If TomTom or another
  addon has been forgetting itself, switch it back on** in Quality of Life
  > Other addons' settings; the switch is off rather than broken.
- **A guest addon no longer waits on BazUI's own file.** Whether the game
  hands us our settings says nothing about whether it hands TomTom its
  own, and the two are asked separately now. TomTom alone keeps three
  files and they can fail one at a time.
- **Dragging an ability off one of the game's own action bars** threw an
  error on the vehicle and encounter bars, tens of times a fight. BazUI
  was listening on Blizzard's buttons to notice the drag, and on this
  client that is enough to stop the game handing its own cooldowns to its
  own code. It asks the cursor instead, which is better anyway: it covers
  every bar in the game rather than the ones we knew the names of.

### Notes

- `/baz sv` now reports the two files separately, along with the key this
  character is stored under and whether anything is actually in it. If
  settings ever go missing again, that is the command to run.
- The day Forever reads a file properly, BazUI hands that file's copy back
  and stops keeping it — one file at a time, on its own. Guests go home at
  the first logout after. There is nothing to undo.
