## 010

**BazUI is readable on Russian, Korean and Chinese clients.** It shipped
with a font that has a Latin alphabet in it and nothing else, and used
that font for every label it drew - so on those clients the whole addon
came out as rows of empty boxes. It now notices that its own face cannot
spell the language the client is in, and uses the game's font instead.

**And you can choose the font.** One list in Settings, holding the face
BazUI ships and the faces the game does. It only offers what your client
actually has: a Russian client is offered the Cyrillic cuts of Morpheus
and Skurri, a Korean one the faces Korean is written in, and neither is
offered BazUI's own.

### Changed

- **The "Use the BazUI font" tick box is now an entry in that list.** One
  decision, one control. Whatever you had set carries over.
- **"Game default" leaves text alone** rather than forcing one file on
  everything - a damage number and a chat line do not wear the same face
  in the game either, and now they still do not.
