#!/bin/zsh
# Cuts the two recorded takes into the finished app preview.
#
#   capture.sh video   (or cut_video.sh [out.mp4] to re-cut existing takes)
#
# Trims each take, normalises to 1920x1080/30fps CFR (screencapture records
# variable-rate at up to 120), joins them, fades the captions over the top, and
# encodes to what App Store Connect accepts: H.264 high, yuv420p, faststart.
# App previews must run 15-30s; this lands around 24.
set -e
source "${0:A:h}/common.sh"
OUT=${1:-$ASSETS/CalPeek-AppPreview-1920x1080.mp4}
RAW=vid_raw
W=1920 H=1080 FPS=30

# The recording is 3600x2026 -- an 1800x1013pt region at 2x, i.e. the whole
# width of the display. Framed at that scale the popover is about a fifth of
# the frame and the rest is empty ground. So the finished video is a 16:9 crop
# of the right-hand 1200pt: it keeps the menu bar, the glyph and the clock at
# the frame's right edge exactly as they sit on a real Mac, puts the popover a
# little right of centre, and leaves the left third clear for the captions.
# Downscaling 2400 -> 1920 renders the popover at about 1.6x its physical size,
# which is roughly the proportion the old composited cut used.
FRAME="crop=2400:1350:1200:0"

# Head trims drop the recorder's spin-up AND the beat before the cursor starts
# moving -- opening on a still, empty desktop wastes the only two seconds an
# App Store preview reliably gets watched. Tail trims drop the hold after the
# last action. Tune these two lines rather than re-shooting. App previews must
# also come in under 30s, so total length is a hard constraint, not a taste.
A_IN=1.60  A_OUT=10.4
B_IN=0.30  B_OUT=19.8

# The recording is 3600x2026 (an 1800x1013pt region at 2x); 16:9 of 3600 is
# 2025, so one row comes off the bottom before the downscale.
#
# It also carries macOS's screen-recording indicator in the menu bar, which the
# OS will not let anything suppress. find_dot locates it per take (its x
# moves with the clock's text width) and it is painted over with a narrow
# column of clear menu bar stretched across it -- the bar is a smooth
# horizontal gradient there, so the patch is invisible. Done at 3600 wide,
# before the downscale, so no softened edge survives into the result.
norm_filter () {   # norm_filter <take.mov>
  local f=$(mktemp -t dotprobe).png
  ffmpeg -v error -y -ss 3.0 -i $1 -frames:v 1 $f
  local out=$(find_dot $f 2>/dev/null) ; rm -f $f
  # fps first, then pixels. screencapture records at up to 120fps; scaling
  # 7-megapixel frames to 1080p and *then* throwing three quarters of them away
  # costs four times what it needs to and pins every core for minutes.
  if [[ -z $out ]]; then
    # No indicator in this take -- don't fabricate a patch over clean bar.
    echo "[0:v]fps=${FPS},${FRAME},scale=${W}:${H}:flags=lanczos,format=yuv420p[v]"
    return
  fi
  local -a lines; lines=(${(f)out})
  local n=${#lines}
  # One patch per indicator. Patching is done on the FULL frame, before the
  # crop, because find_dot reports x in full-frame coordinates.
  local g="[0:v]fps=${FPS},split=$((n + 1))[b0]"
  local i
  for (( i = 1; i <= n; i++ )); do g+="[s$i]"; done
  g+=";"
  for (( i = 1; i <= n; i++ )); do
    local l=(${=lines[$i]})
    g+="[s$i]crop=6:${l[4]}:${l[3]}:0,scale=${l[2]}:${l[4]}[p$i];"
  done
  local prev="b0"
  for (( i = 1; i <= n; i++ )); do
    local l=(${=lines[$i]})
    g+="[$prev][p$i]overlay=${l[1]}:0[o$i];"
    prev="o$i"
  done
  g+="[$prev]${FRAME},scale=${W}:${H}:flags=lanczos,format=yuv420p[v]"
  echo $g
}

for t in A B; do
  [[ -f $RAW/$t.mov ]] || { echo "ABORT: $RAW/$t.mov missing -- run capture.sh video"; exit 1; }
done

ffmpeg -v error -y -ss $A_IN -to $A_OUT -i $RAW/A.mov -filter_complex "$(norm_filter $RAW/A.mov)" \
  -map "[v]" -an -c:v libx264 -crf 12 -preset ultrafast $RAW/a_norm.mp4
ffmpeg -v error -y -ss $B_IN -to $B_OUT -i $RAW/B.mov -filter_complex "$(norm_filter $RAW/B.mov)" \
  -map "[v]" -an -c:v libx264 -crf 12 -preset ultrafast $RAW/b_norm.mp4

DA=$(ffprobe -v error -show_entries format=duration -of csv=p=0 $RAW/a_norm.mp4)
DB=$(ffprobe -v error -show_entries format=duration -of csv=p=0 $RAW/b_norm.mp4)
TOTAL=$(printf '%.2f' $((DA + DB)))
echo "take A ${DA}s + take B ${DB}s = ${TOTAL}s"

printf "file '%s'\nfile '%s'\n" "$PWD/$RAW/a_norm.mp4" "$PWD/$RAW/b_norm.mp4" > $RAW/list.txt
ffmpeg -v error -y -f concat -safe 0 -i $RAW/list.txt -c copy $RAW/joined.mp4

# Captions, timed off the actual take lengths so a re-trim cannot desync them.
# Each is a pre-rendered transparent PNG (caption) faded in and out, rather
# than ffmpeg drawtext, so the type stays real SF Pro semibold.
caption $RAW/cap1.png 'Your month.\nOne click away.'
caption $RAW/cap2.png "Peek at any day's schedule."
caption $RAW/cap3.png 'Create events and reminders\nin seconds.'

# Anchored to the beats they describe, not spread evenly. Take B's create form
# does not open until about 10s into that take, so a "Create events..." caption
# on the old even spacing sat over four seconds of browsing, promising one
# thing while showing another.
C1_A=1.00                              C1_B=$(printf '%.2f' $((DA - 0.35)))
C2_A=$(printf '%.2f' $((DA + 1.2)))    C2_B=$(printf '%.2f' $((DA + 9.4)))
C3_A=$(printf '%.2f' $((DA + 10.0)))   C3_B=$(printf '%.2f' $((TOTAL - 0.25)))
FADE=0.45

# Each caption is a still image looped for the length of the video, faded in
# and out on its alpha channel. `enable=between(...)` alone would pop them on
# and off; the fade filters are what make them read as titles.
cap () {  # cap <input index> <start> <end> <label>
  echo "[$1]format=rgba,loop=loop=-1:size=1:start=0,setpts=N/${FPS}/TB,\
fade=t=in:st=$2:d=${FADE}:alpha=1,fade=t=out:st=$(printf '%.2f' $(($3 - FADE))):d=${FADE}:alpha=1[$4]"
}

FC="$(cap 1 $C1_A $C1_B c1);$(cap 2 $C2_A $C2_B c2);$(cap 3 $C3_A $C3_B c3);"
# shortest=1 on EVERY overlay. The caption streams are `loop=-1`, i.e. endless;
# an overlay without it takes the longest input, so the encode never terminates
# -- the first cut of this wrote 35 minutes of video before it was noticed.
# -t is the belt to that pair of braces.
FC+="[0][c1]overlay=0:0:shortest=1[v1];[v1][c2]overlay=0:0:shortest=1[v2];"
FC+="[v2][c3]overlay=0:0:shortest=1[v3];[v3]format=yuv420p[v]"

# A SILENT AUDIO TRACK IS NOT OPTIONAL. App Store Connect rejects a preview
# with no audio stream, and the message it gives is misleading -- "Your app
# preview contains unsupported or corrupted audio", which reads as a problem
# with audio that is present rather than the absence of any. The 1.0 preview
# that Apple accepted carried AAC stereo at 44.1kHz; silence compresses to
# about 2kbps, so it costs nothing.
ffmpeg -v error -y -i $RAW/joined.mp4 -i $RAW/cap1.png -i $RAW/cap2.png -i $RAW/cap3.png \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -filter_complex "$FC" -map "[v]" -map 4:a -t $TOTAL \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 18 \
  -c:a aac -b:a 128k -movflags +faststart "$OUT"

echo "wrote $OUT ($(du -h "$OUT" | cut -f1), ${TOTAL}s)"
# Fail loudly here rather than in App Store Connect three uploads later.
ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$OUT" \
  | grep -q aac || { echo "ABORT: $OUT has no audio track; App Store Connect will reject it"; exit 1; }
