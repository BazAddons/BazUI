## 013

**You do not have to have a drawer any more.** Turn `Use drawers` off at
the top of Options > AddOns > BazUI > Drawers > General, and every widget
you switch on sits loose on the screen instead, wherever you drag it in
BazUI Edit Mode. The drawer, its tabs and its edge strip are not drawn.

Your drawers are kept exactly as they were, so switching it back on gives
you them back, widgets and all.

### New

- **A size for loose widgets.** Docked, a widget is scaled to fill the
  drawer's width, which is why it never had a size of its own. Out on the
  screen there is nothing to fill, so each one now carries a **Scale** -
  on its page under Widgets and on its BazUI Edit Mode panel, the same
  setting in both places. The minimap keeps its own **Map Scale** instead,
  because the map has to stay centered inside the ring drawn around it.
- **`/bwd float`** prints where each loose widget thinks it should be
  against where it actually is, and **`/bwd map`** does the same for the
  minimap in rather more detail.

### Fixed

- **Loose widgets came back centered on the screen after a reload.** They
  were placed once, at whatever point in the login each widget registered,
  and anything that anchored the frame afterwards won.
- **Scaling a loose widget moved it.** It slid down and left as it shrank
  and up and right as it grew. Positions are stored in screen pixels now,
  so a widget stays where you put it and grows about its own center.
- **A widget switched on but in no drawer simply vanished** - or worse,
  sat on the screen ignoring the drawer entirely. If one has gone missing,
  look under Drawers, then Widgets in this drawer.
- **The minimap did not resize when it moved in or out of a drawer**, and
  could come up with its map missing entirely.
- **A setting that should be grayed out now is.** This one is not about
  drawers: nothing in any BazUI settings page grayed itself out when the
  page was rebuilt, so controls that did not apply could still be changed.
  The drawer's appearance sliders were the obvious case, sitting live
  under a line saying the drawer was locked.
