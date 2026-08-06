#!/usr/bin/env python3
"""Cut the four Manrope weights the app uses out of the variable font.

The web app asks Google Fonts for wght 400, 500, 600 and 700. Shipping the
variable file instead would be smaller, but its default instance is
ExtraLight and its family name is "Manrope ExtraLight" — so a lookup by
family name lands on a weight the design never uses. Static instances remove
the guesswork: each one has its own PostScript name and resolves the same
way on every iOS version.

    python3 tools/make-fonts.py

Manrope is under the SIL Open Font License 1.1; the licence ships beside the
fonts in SQIA/Resources/Fonts/.
"""

from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

WEIGHTS = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}

FONTS = Path(__file__).resolve().parent.parent / "SQIA/Resources/Fonts"
SOURCE = FONTS / "Manrope-Variable.ttf"


def cut(weight: int, style: str) -> Path:
    font = instancer.instantiateVariableFont(TTFont(SOURCE), {"wght": weight})
    family = "Manrope"
    full = f"{family} {style}"
    postscript = f"{family}-{style}"

    # Name the instance properly, or iOS resolves it by whatever the variable
    # font happened to call its default.
    name = font["name"]
    for record in list(name.names):
        if record.nameID == 1:
            name.setName(family, 1, record.platformID, record.platEncID, record.langID)
        elif record.nameID == 2:
            name.setName(style, 2, record.platformID, record.platEncID, record.langID)
        elif record.nameID == 4:
            name.setName(full, 4, record.platformID, record.platEncID, record.langID)
        elif record.nameID == 6:
            name.setName(postscript, 6, record.platformID, record.platEncID, record.langID)
    # Typographic family/subfamily would override the above; the four weights
    # are ordinary styles now, so drop them.
    for name_id in (16, 17):
        name.removeNames(name_id)

    out = FONTS / f"{postscript}.ttf"
    font.save(out)
    return out


if __name__ == "__main__":
    for weight, style in WEIGHTS.items():
        path = cut(weight, style)
        print(f"wrote {path.name} ({path.stat().st_size // 1024} KB)")
