# Unit Frames

A unit is drawn as bars you make yourself. Health, power, casting,
experience and reputation are one implementation with a `kind` on it, so
every one of them can float at a saved position or dock to an action bar
or to another bar, above or below. A docked bar takes its host's width
and hides when its host hides, all the way up the chain.

There is no portrait and no frame around anything, which is what makes
them dockable in the first place. `REDESIGN.md` has the reasoning and
the build order.

Open `/bazframes`, or Settings > AddOns > BazUI > Unit Frames. The page
itself is two toggles, because everything about a particular bar belongs
to that bar: its name, what it reads, which unit, where it docks and on
which edge, width, height, when its text shows and what that text says.
Edit those on the Bars page, or by selecting the bar in Edit Mode.

In Edit Mode, Create makes a bar, and dragging one near the edge of an
action bar or another bar docks it there; a line shows where it will
land before you let go. Health and power bars are secure unit buttons,
so left-click targets and right-click opens the unit menu, and every
change is made out of combat only.

Whatever you make a bar for replaces the game's own version of it: a
player health bar hides the stock player frame, a cast bar hides the
stock cast bar, an experience bar hides the stock one and takes its Edit
Mode entry with it. Delete the bar and the game's comes back. Nothing
about that is a setting, since the answer is readable from the bars you
have.
