# Unit Frames: the bar and dock redesign

Status: agreed in principle, not started.

## The idea

Every readout the player watches becomes a bar in the XP bar's clothing.
Health, power, cast, experience, reputation. A bar either floats where
you put it, or docks to the edge of an action bar or another bar.

There is no portrait, no frame artwork and no geometry measured off a
PNG. The current frames are pinned to `playerFrame.png` through fourteen
numbers in `Layout.lua`, and every change means going back to the image.
Bespoke graphics buy one good-looking frame and cost flexibility
everywhere else; a system that draws bars buys the opposite, and the
rest of the suite already reads that way.

## What a dockable is

One contract, two behaviours against a host:

| Behaviour | Who uses it | What it does |
|---|---|---|
| Stretch | bars | Takes the host's width, sits on its top or bottom edge |
| Align | auras | Sits left, right or centre within the host's width |

A host is an action bar, another dockable, or nothing (floating).

Everything about auras that is configurable today stays configurable:
per-row count, rows, growth, size. Alignment is where the block sits,
which is independent of how it lays itself out.

## Rules

- **A chain hides as a unit.** Target power docked to target health
  disappears when target health does.
- **A hidden bar closes the gap**, unless it is told to hold its place.
  That is a switch per bar, on by default for the cast bar and off for
  everything else: the cast bar is the only one that appears and vanishes
  several times a minute, which is when a shifting layout is worst.
- **Configuration is out of combat only**, refused with a message, the
  way Bars already refuses resizing. Nobody needs to re-dock their health
  bar mid-fight, and the rule means no deferred-apply machinery for
  settings at all.
- **One builder, the unit is a parameter.** Player and target are the
  same code rather than the two near-duplicates of 390 and 423 lines they
  are now. Pet, target of target and party become cheap afterwards.

## The two things the combat rule does not cover

Configuration being out of combat handles everything the player changes.
It does not touch what the game changes mid-fight, and both of these have
to be built the right way from the start:

1. **A centred aura row moves whenever the aura count changes**, which is
   constantly, in combat. A secure frame cannot be repositioned then. The
   answer is to put the secure header inside an ordinary frame and move
   that: an unprotected parent can be repositioned in combat even when
   its children are protected. Left and right alignment need none of
   this, so if centring ever misbehaves it degrades to a fixed edge.
2. **A target bar appears and disappears with the target.** That is the
   gap rule above, and it resolves in a layout pass, not a settings one.

## What the portrait was doing

Worth listing, because it all has to land somewhere:

- The unit's image. Gone, deliberately.
- The casting liquid. Becomes its own bar.
- **Click to target, and the unit right-click menu.** This is the hidden
  one. It means unit bars must be secure unit buttons, which brings the
  same combat rules the flyouts have. Designed in from the start, not
  added afterwards.
- The unit's name, level and classification. Bar text.

## Bar text

The XP bar's model is the starting point: always, on hover, or never. A
health bar has more to say than an XP bar, so it needs a choice of what
as well as when: name, current, max, percent, or a combination.

## Build order

Dictated by the aura headers, which are secure and anchored to
`BazUIPlayerFrame` today.

1. One bar widget, promoted from the XP bar's implementation. We
   currently have two, the XP bar's and `Theme.CreateStatBar`; this makes
   one canonical instead of letting them drift.
2. The dock system: hosts publish width and visibility, dockables attach
   with an edge and a mode, chains resolve in order.
3. Player health, power and cast as dockables. XP and reputation move
   onto the same system.
4. Target, same code with the unit as a parameter.
5. Auras re-anchored, with the unprotected wrapper for centring.
   **Done**, with one correction to the plan. Rows are dockables you
   create: the header sits inside an ordinary frame, and that frame
   docks. Centring is a SetSize on that frame as icons arrive - but an
   unprotected wrapper buys a parent you may move, not one you may move
   at any time. A secure header anchored to it makes resizing it a
   protected action, blocked in combat like any other. Rows therefore
   keep the size the fight started with and take the new one when it
   ends; left and right aligned rows never needed it, since they grow
   from their anchored end.
6. Retire the artwork, `Layout.lua`, `TargetLayout.lua` and the design
   PNGs. **Done.** `Player.lua`, `Target.lua`, `Casting.lua`, both
   layout tables and fourteen art files are gone, and with them the
   module's whole settings page bar two toggles: everything else it
   offered described a portrait frame nothing draws any more. The
   addon's 26 lint warnings went with them, as predicted, since all of
   them were globals those frames created in XML.

## Open

Nothing blocking. The nameplate module is untouched by this and keeps
its own styling.
