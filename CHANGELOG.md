## 011

**Cyrillic, Korean, Chinese and Japanese text reads properly now.** 010
tried to fix this by falling back to "the game's font" when BazUI's own
could not spell something - but the game has a different font per
language, and the English client's has no Cyrillic in it either, so that
fixed nothing. BazUI now picks a face to suit the alphabet the text is
actually written in, out of the faces your client already has. A Russian
name in an English client draws as a name. Nothing to set up.

Greek is the one alphabet left, because no font the game ships carries
it. There is a Fonts folder in the addon now if you want to supply your
own; the note inside explains it and suggests one.

### New

- **`/baz fonts`** writes sample text in eight alphabets, in BazUI's face
  and in the one it would borrow, and names the file each came from. If
  text is coming out as empty boxes, this says exactly where the problem
  is.
- **Your own font.** Drop a .ttf into the addon's Fonts folder as
  Custom.ttf and it joins the font list. Read the note in that folder
  first - the game only loads fonts when it starts, so it takes a
  restart rather than a reload.
- **Drawer widgets have buttons on their title bars.** Hover one and you
  get move up, move down, collapse and a red cross to take the widget off
  that drawer. Everything is where it was; the controls only appear under
  the cursor.

### Fixed

- **Options buttons that appeared to do nothing.** A button that redrew
  its own page was being drawn over by the page as it had been a moment
  earlier, so the thing it had just done was invisible - making a drawer
  and having the list still show the old one, for instance. Every page is
  affected; the drawers page is where it showed.
- **Making a new drawer, bar or unit frame bar now opens its settings**
  rather than leaving you to find it in the list.
- **Dragging a widget to reorder it did nothing.** It turned the title bar
  green and then put the widget back where it started, every time.
- **Minimap buttons vanished until a reload** if you collapsed the widget
  and opened it again.
