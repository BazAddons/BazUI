# One placement system

## Decided: no. Two systems, and the reason is a real one

**2026-09-21.** The unification below is not being built. The distinction
between the two systems is not an accident of history, it is a distinction
between two shapes of thing:

- **Elastic.** No natural size. Fills a host's width, reflows as a grid,
  stretching is the entire point. Action bars, unit bars, aura rows.
  `Dock` exists to make elastic things share an edge.
- **Intrinsic.** One correct size. Wants shelf space, not a share of an
  edge. The clock, the repair icon, a strip of minimap buttons. The drawer
  exists to give intrinsic things a shelf, and it **scales** them to fit
  rather than stretching them - `scale = usableWidth / designWidth`.

Merging the two would mean every element carrying machinery for a shape it
is not. An action bar in a drawer would be scaled when it wants to reflow;
a clock on a dock edge would be stretched when it wants to be left alone.

**The micro menu is intrinsic** - nine fixed round buttons, no natural
stretch - so it becomes a **drawer widget**, not a bar. That removes the
third partial copy of the placement machinery, which was the only
duplication actually worth removing.

The rest of this note is kept as the record of why the bigger change was
considered and rejected, and as the description of what each system is for.

---

*Everything below was the case for unifying. It is no longer the plan.*

## The observation

Bars and widgets are the same thing wearing two different coats. A bar that
is not docked is a frame with content and a saved position. A widget that is
not in a drawer is a frame with content and a saved position. Everything
that makes one of them *placeable* is the same work, and BazUI currently
does that work three times.

## What exists today

**`Core/Dock.lua` — 1,252 lines.** Already a Core system, already shared.
Used by Bars, Auras and UnitFrames. It knows about:

- four edges, with the axis derived from the edge rather than assumed
- two follower behaviours: `stretch` (fill the host across the line) and
  `align` (keep your size, sit at an end or the middle)
- chains — a follower of a follower resolves by walking down from the host
- a chain hiding as a unit, and a hidden follower either closing the gap or
  holding its place
- named hosts (`RegisterHost`), pending attachment resolved when a host
  appears later
- floating, which it already treats as *docked to nothing*

**`Modules/Drawers/WidgetHost.lua` — 1,285 lines.** An entirely separate
placement engine. Its own `FloatWidget` / `DockWidget`, its own
`SaveFloatingPosition` / `PlaceFloating`, its own `Reflow` / `DoReflow`,
its own drag-to-reorder (`StartDrag` / `DragStep` / `StopDrag` /
`MoveInStack` / `SwapWidgetOrder`), its own stack ordering. It does not
reference `BazUI.Dock` once.

**`Modules/MicroMenu/` — 787 lines.** A third, partial copy: position,
orientation, button size, spacing, mouseover fade with its own animation
loop, reset, and an Edit Mode registration. No docking at all, which is
why the micro menu cannot sit under an action bar and follow it.

Three engines, and the newest one is the least capable.

## What is actually shared

Every placeable thing in the addon needs the same seven things:

| | |
|---|---|
| **A home** | floating on the screen, or hosted by something |
| **A position** | saved, restored, and correct across UI scales |
| **A scale** | its own, independent of its host |
| **An identity in Edit Mode** | overlay, handle, label, inspector |
| **Settings** | read through the profile, rebuilt on a profile switch |
| **Visibility** | conditions, fade, chain-hiding |
| **A background** | the suite's panel, or none |

None of that is about *what the thing draws*. It is all about placement, and
it is written out three times.

## What is genuinely different — and must stay different

The **host**, not the element.

- A **dock stack** arranges edge-to-edge along an axis, with the follower
  fitted to the host's stack as it stood when that follower docked. That
  ticket model is subtle, hard-won, and the source of at least two
  previously-fixed bugs. It must survive verbatim.
- A **drawer** arranges in rows inside a panel, with drag-to-reorder and a
  reflow pass.

Those are two real layout strategies and both are earned. Unifying the
*element* does not require unifying the *host*.

## The proposal

**An element knows how to be an element. A host knows how to arrange.**

An element asks "who hosts me?" and gets one of three answers: the screen,
a dock stack, or a drawer. The host does the arranging; the element carries
the seven things above and nothing else.

`Dock` is already most of the way there — it has named hosts, it already
treats floating as a kind of docking, and its follower behaviour is already
declared per-follower (`stretch` / `align`). A drawer becomes a **third
arrangement mode** (`flow`) on the same engine, rather than a second engine.

That is the whole idea. Everything below is consequence.

### The one property that has to be new

**`secure`** — does this element carry secure children?

Action bar buttons cannot be reparented or arranged in combat. Most widgets
can. Today each module remembers this for itself, which is why the deferral
logic is written separately in `WidgetHost:DockWidget`, in the bars, and in
the quest timer rescue. As an element property, the placement system defers
once, in one place, and every caller inherits it.

## Sequencing

A half-landed unification is worse than either system, so the order matters
more than the speed.

**1. Extract, move nothing.** Pull the seven shared behaviours into an
element layer. Both existing engines keep working, untouched, on top of it.
No user-visible change; nothing to test in game beyond "still fine".

**2. Drawer widgets first.** They are the safe ones — no secure children,
no combat constraint, and a drawer that misbehaves costs a reload rather
than a fight. If the abstraction is wrong, this is where it shows, and it
shows cheaply. `WidgetHost`'s reflow becomes the `flow` arrangement mode.

**3. Bars second.** This is where the dock ticket model and the secure
rules get exercised. Dock itself barely changes; what changes is that bars
stop owning their own float/position/EditMode code and take the element
layer's.

**4. The micro menu last, as the acceptance test.** It becomes an element
with a fixed-button provider — no drag assignment, no paging, no flyouts —
and inherits docking, background, visibility and the inspector for free.

**If step 4 takes more than an afternoon, the abstraction was wrong.** That
is the point of doing it last and the reason not to do it first.

## What has to not break

Written down because each of these was expensive to learn once:

- **The dock ticket.** A follower is fitted to the host's stack as it stood
  when that follower docked, not as it stands now.
- **The drop keeps the promise.** The landing line shown during a drag is
  binding; re-asking after the frame has moved is how a shown snap silently
  missed.
- **Reflow re-entrancy.** A handler that triggers a reflow from inside a
  reflow lets the stale outer pass win.
- **Live profile switch.** A switch replaces settings tables but not
  frames. `ApplySettings` must build *and* prune, and nothing may hold a def
  table across it — which means the element layer must not cache one either.
- **Secure frames in combat.** Cannot be made, moved or shown. Build ahead
  of time out of combat; refresh contents but defer arrangement.

## Cost, honestly

Steps 1 and 2 are the bulk and are low-risk. Step 3 touches the most
load-bearing code in the addon. Step 4 is small if the first three were
right.

This is not a refactor that pays for itself in lines removed. It pays when
the fifth placeable thing costs an hour instead of a module, and when a
placement bug is fixed once instead of three times — which has already
happened twice this month, in the inspector rebuild and in the Edit Mode
overlay restore.

## The argument against

Two systems is annoying. Three is a pattern. But both existing systems
currently work, and BazUI has a live release cadence. If the answer is "not
now", the honest smaller move is to leave Bars and Drawers alone and make
the **micro menu** adopt one of them rather than keeping its own third copy
— which removes the newest duplication without touching either engine.
