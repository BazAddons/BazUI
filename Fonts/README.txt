BazUI - your own font
=====================

Drop a font file in this folder, name it Custom.ttf, and BazUI will offer
it in Settings > BazUI > General > Interface font as "Your own font".

    Interface\AddOns\BazUI\Fonts\Custom.ttf

You probably do not need this
-----------------------------

If text is coming out as rows of empty boxes, try the current version
first. BazUI picks a face to suit whatever alphabet the text is written
in, out of the ones your client already has, and that covers Cyrillic,
Korean, Chinese and Japanese without you doing anything at all. The font
list in Settings > BazUI > General offers whichever of the game's faces
your client can draw your language with.

This folder is for the two things that does not cover:

  - Greek. Nothing the game ships carries it, so a font of your own is
    the only fix.

  - Wanting a particular font because you like it. Nothing to do with
    alphabets; some people just want their own.

Two things worth knowing
------------------------

1.  The game reads fonts when it starts. After you put the file here you
    have to quit to the desktop and start the game again - a /reload is
    not enough, and the font will simply not appear in the list until
    you do.

2.  It must be a TrueType file (.ttf), and a plain one. The game will
    not load an OpenType file (.otf), and it will not load a "variable"
    font either - see the note under Noto below, because that is the
    easiest way to end up with a file that quietly does nothing.

A recommendation
----------------

DejaVu Sans is the easy answer. Latin, Cyrillic and Greek in one file,
free to use and redistribute, and it downloads as ordinary static .ttf
files with nothing to pick between.

    https://dejavu-fonts.github.io/

Take DejaVuSans.ttf from the zip and rename it to Custom.ttf.

Noto Sans is the other good answer, and covers more:

    https://fonts.google.com/noto/specimen/Noto+Sans

One catch, and it is the thing that catches everybody. Unzip what you
download and look for a folder called "static". If it is there, the file
sitting outside it is a *variable* font and the game will not load it -
you want a file from inside "static", such as NotoSans-Regular.ttf.
Rename that to Custom.ttf.

For Korean, Chinese or Japanese, the same site has Noto Sans KR, Noto
Sans SC and Noto Sans JP. Same steps, same catch.

Checking it worked
------------------

Type /baz fonts in game. That panel writes sample text in several
alphabets, in BazUI's face and in the one it would borrow, and says
which file each came from. The top of it says whether your own font
loaded.

If it says your font is not there after a restart, the usual causes are
the name (it must be exactly Custom.ttf), the format (.otf will not
load), or a variable font from the Noto download.
