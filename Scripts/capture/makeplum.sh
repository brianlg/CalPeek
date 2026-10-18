#!/bin/zsh
# Scales the supplied desktop image to the display's backing size (3600x2338),
# scale-to-fill and centre-cropped exactly as macOS lays out a wallpaper.
#
# compose_scene regresses the captured menu bar against this file pixel for
# pixel, so it must be the same size as the framebuffer, not the size of the
# source art. The supplied 2880x1800 file (ground.png) is neither.
set -e
source "${0:A:h}/common.sh"
SRC=${1:-$CAPTURE_DIR/ground.png}
W=3600 H=2338
sw=$(sips -g pixelWidth "$SRC" | tail -1 | tr -dc 0-9)
sh=$(sips -g pixelHeight "$SRC" | tail -1 | tr -dc 0-9)
# scale to fill: whichever axis needs the larger factor wins
rw=$(( (W * sh + sw - 1) / sw ))
if (( rw >= H )); then RESAMPLE="--resampleWidth $W"; else RESAMPLE="--resampleHeight $H"; fi
sips $=RESAMPLE "$SRC" --out plum.png >/dev/null
sips -c $H $W plum.png >/dev/null
echo "plum.png $(sips -g pixelWidth -g pixelHeight plum.png | tail -2 | tr -dc '0-9\n' | tr '\n' 'x' | sed 's/x$//')"
