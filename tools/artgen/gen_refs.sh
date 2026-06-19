#!/usr/bin/env bash
# Regenerate detailed black-background renders for the 28 building types shown in the HTML
# (Sprites/Buildings/refs). 3 candidates each -> Sprites/Buildings/raw/<btype>_<i>.png.
set -e
cd "$(dirname "$0")"
N="${1:-3}"
TYPES="apothecary apple_orchard armory bakery barracks blacksmith brewery church \
dairy_farm gatehouse granary guildhall hovel inn iron_mine keep market mill \
siege_workshop stone_quarry stone_wall tannery trading_post village_hall \
watchtower well wheat_farm woodcutter_camp"
for bt in $TYPES; do
  echo "=== $bt ==="
  python3 gen.py "$bt" "$N"
done
echo "ALL DONE"
