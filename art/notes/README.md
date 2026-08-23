# Note illustrations

The twelve marks a playing cell can take, one per grid column — `note-00` is
the leftmost column and the lowest note, `note-11` the rightmost.

Source art lives here; `tools/make-sprites.py` renders it into the atlas the
field samples, the same way `tools/make-icon.py` renders the app icon into
`SQIA/Resources/Assets.xcassets/`. Nothing in this folder ships in the app.

## What goes here

`note-00` … `note-11`, as PDF (vector, preferred) or PNG (512×512).

- Square canvas, transparent background.
- Centred on the canvas: the mark turns about the canvas centre, not its own
  optical centre, so a mark pushed off-centre will visibly wobble as it spins.
- A little margin at the edges — the mark grows on a hit, and the quad it is
  drawn into does not.
- A flat silhouette tints cleanly: the field's colour wave repaints the whole
  mark. Colour in the art itself survives, but the wave can then only wash
  over it.
