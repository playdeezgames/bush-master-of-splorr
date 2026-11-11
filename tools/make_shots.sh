#!/usr/bin/env bash
# Renders real frames natively (the frame-dump tests in src/game/dump_test.odin) and writes
# assets/screenshots/01-play.png, 02-shop.png (the 384x216 screen, scaled 3x) and assets/portal.png (480x360, the
# plot cropped, for the oeuvre-of-splorr portal). Needs Pillow.
set -euo pipefail
cd "$(dirname "$0")/.."
D="$(mktemp -d)"
odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1 -define:DUMP_PLAY="$D/play.ppm" -define:DUMP_SHOP="$D/shop.ppm" -define:ODIN_TEST_NAMES=game.dump_play,game.dump_shop >/dev/null 2>&1
python3 -I - "$D" <<'PY'
import os, sys
from PIL import Image
d = sys.argv[1]
im = Image.open(os.path.join(d, "play.ppm"))
im.resize((384 * 3, 216 * 3), Image.NEAREST).save("assets/screenshots/01-play.png")
Image.open(os.path.join(d, "shop.ppm")).resize((384 * 3, 216 * 3), Image.NEAREST).save("assets/screenshots/02-shop.png")
# The fenced plot is tiles 8..23 across and 4..14 down; a 4:3 window around it, doubled.
im.crop((72, 36, 312, 216)).resize((480, 360), Image.NEAREST).save("assets/portal.png")
print("assets/screenshots/01-play.png, 02-shop.png, assets/portal.png")
PY
rm -rf "$D"
