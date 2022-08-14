# An editor for plain text.

Not very useful by itself, but it's a fork of [lines.love](http://akkartik.name/lines.html)
that you can take in other directions besides line drawings, while easily
sharing patches between forks.

Designed above all to be easy to modify and give you early warning if your
modifications break something.

## Invocation

To run from the terminal, [pass this directory to LÖVE](https://love2d.org/wiki/Getting_Started#Running_Games),
optionally with a file path to edit.

Alternatively, turn it into a .love file you can double-click on:
```
$ zip -r /tmp/text.love *.lua
```

By default, it reads/writes the file `lines.txt` in your default
user/home directory (`https://love2d.org/wiki/love.filesystem.getUserDirectory`).

To open a different file, drop it on the app window.

## Keyboard shortcuts

While editing text:
* `ctrl+f` to find patterns within a file
* `ctrl+c` to copy, `ctrl+x` to cut, `ctrl+v` to paste
* `ctrl+z` to undo, `ctrl+y` to redo
* `ctrl+=` to zoom in, `ctrl+-` to zoom out, `ctrl+0` to reset zoom
* `alt+right`/`alt+left` to jump to the next/previous word, respectively

Exclusively tested so far with a US keyboard layout. If
you use a different layout, please let me know if things worked, or if you
found anything amiss: http://akkartik.name/contact

## Known issues

* No support yet for Unicode graphemes spanning multiple codepoints.

* No support yet for right-to-left languages.

* Undo/redo may be sluggish in large files. Large files may grow sluggish in
  other ways. Works well in all circumstances with files under 50KB.

* If you kill the process, say by force-quitting because things things get
  sluggish, you can lose data.

* Long wrapping lines can't yet distinguish between the cursor at end of one
  screen line and start of the next, so clicking the mouse to position the
  cursor can very occasionally do the wrong thing.

* Touchpads can drag the mouse pointer using a light touch or a heavy click.
  On Linux, drags using the light touch get interrupted when a key is pressed.
  You'll have to press down to drag.

* Can't scroll while selecting text with mouse.

* No scrollbars yet. That stuff is hard.

## Mirrors and Forks

This repo is a fork of lines.love at [http://akkartik.name/lines.html](http://akkartik.name/lines.html).
Updates to it can be downloaded from the following mirrors:

* https://codeberg.org/akkartik/text.love
* https://repo.or.cz/text.love.git
* https://tildegit.org/akkartik/text.love
* https://git.tilde.institute/akkartik/text.love
* https://git.sr.ht/~akkartik/text.love
* https://notabug.org/akkartik/text.love
* https://github.com/akkartik/text.love
* https://pagure.io/text.love

Further forks are encouraged. If you show me your fork, I'll link to it here.

## Feedback

[Most appreciated.](http://akkartik.name/contact)
