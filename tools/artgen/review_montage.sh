#!/usr/bin/env bash
# Build labeled review montages of the raw candidates for the 28 ref building types,
# so the best index per type can be chosen before keying into Sprites/Buildings/refs.
# Output: /tmp/refrender/review_<page>.png  (each cand labeled <btype>_<i>)
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RAW="$ROOT/Sprites/Buildings/raw"
OUT=/tmp/refrender
mkdir -p "$OUT/thumbs"
TYPES="apothecary apple_orchard armory bakery barracks blacksmith brewery church \
dairy_farm gatehouse granary guildhall hovel inn iron_mine keep market mill \
siege_workshop stone_quarry stone_wall tannery trading_post village_hall \
watchtower well wheat_farm woodcutter_camp"
labels=()
for bt in $TYPES; do
  for i in 0 1 2; do
    f="$RAW/${bt}_${i}.png"
    [ -f "$f" ] || continue
    t="$OUT/thumbs/${bt}_${i}.png"
    magick "$f" -resize 230x230 -background black -gravity center -extent 230x230 \
      -fill yellow -pointsize 18 -gravity south -annotate +0+2 "${bt}_${i}" "$t"
    labels+=("$t")
  done
done
# 6 columns per page; split into pages of 36 thumbs
magick montage "${labels[@]}" -tile 6x -geometry +3+3 -background gray20 "$OUT/review.png"
echo "wrote $OUT/review.png (and review-N.png if multipage)"
