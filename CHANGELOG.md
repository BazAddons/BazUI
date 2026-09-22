## 021

**A new module, cast bars on nameplates, and several things that had quietly
never worked.**

### Floating Text — new module

Numbers rising off the fight: what you hit for, what hit you, what you
healed, and the misses and dodges in between, in BazUI's own font.

- **Two areas**, Incoming on the left and Outgoing on the right, each placed
  by dragging it in Edit Mode. Which one a number lands in is not a guess:
  the game says who *took* the hit.
- **Colour by direction**, which is the thing a screen full of white numbers
  cannot tell you — your damage and damage to you are different colours, and
  so are heals in each direction. Damage schools override where a spell has
  one.
- **Crits** drawn larger and optionally marked with stars, because size alone
  only reads as a crit when there is an ordinary hit beside it.
- **Merging**, off by default, for when the same mob is hitting you four
  times a second. Crits are never merged — folding one into a total throws
  away exactly the thing you wanted to see.
- **The game's own numbers can be turned off**, both the scrolling text and
  the ones drawn over the mob. Those are two different settings in the game
  and turning one off leaves the other running, which is why this needs two
  switches.

It starts **off**. It draws over the middle of the screen, and a module that
begins doing that unannounced is one you go hunting for the switch to.

### Nameplate cast bars — new

A bar under the plate while a unit is casting, coloured by whether you can
do anything about it:

- **Green** — you can interrupt this, right now.
- **Amber** — you could, but your interrupt is still on cooldown.
- **Red** — this one cannot be interrupted by anyone.

Your interrupt comes from your **spellbook** rather than your class, so a
warrior gets Pummel or Shield Bash depending on what is in their hands, and a
druid only counts Feral Charge while in bear form. There is a spell-ID
override if yours is not on the list.

On a class with no interrupt — a hunter, a paladin — **green never appears**,
because there is nothing for it to mean. Casts show in a plain colour and
only the ones nobody can stop are marked red.

### Fixed

- **The dockable target cast bar never appeared.** It asked whether the unit
  was casting in a way the game refuses to answer for anyone but you, took
  that refusal as "not casting", and stayed hidden forever. It works now, and
  wears the same three interrupt colours as the nameplate bars.
- **Raid target markers never showed.** The skull, cross and square are
  picked from a number the game will not hand over, and BazUI gave up rather
  than draw the wrong one. The right symbol appears now.
- **Six of the eight unit bar wordings collapsed into "current / max".**
  Name, Level, Name and level and Current all show properly again. The three
  that need a percentage still cannot always have one, but each now falls
  back to the nearest thing it can say rather than all of them landing on the
  same answer.
- **A unit's level vanished from its bar** whenever the game would not let
  the name and the level be joined together. Both show.
- **Numbers in the aura rows** could sit on top of each other — two hits in
  the same instant rise at the same speed from the same line, so they stayed
  exactly parallel. They are spaced apart in time now, and the rise
  separates them.

### Changed

- **Cast bars, aura rows and floating text all follow your skin**, including
  when you change it.
- The **manual** and several settings descriptions were rewritten. A few had
  drifted into explaining how things work rather than what you will see.
