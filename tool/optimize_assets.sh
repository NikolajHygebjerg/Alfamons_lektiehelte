#!/usr/bin/env bash
# Nedskalerer bitmaps og fjerner tunge kort-SVG'er når raster findes.
# Kør fra projektrod: bash tool/optimize_assets.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Max længste kant (px). Kort / UI: 1200 er rigeligt til tablet @3x.
MAX_RASTER=1200
# Miniaturer i trace/bogstaver
MAX_BOGSTAV=512

removed=0
maybe_rm() {
  local f="$1"
  if [[ -f "$f" ]]; then
    rm -f "$f"
    echo "Fjernet: $f"
    removed=$((removed + 1))
  fi
}

echo "== Fjerner redundante SVG'er (PNG/JPG bruges af appen) =="
for svg in assets/*.svg; do
  [[ -e "$svg" ]] || continue
  base="${svg%.svg}"
  bn=$(basename "$svg")

  # Kort: altid raster først i AlfamonCard
  if [[ "${bn}" == *kort* ]] || [[ "${bn}" == *Kort* ]]; then
    if [[ -f "${base}.webp" || -f "${base}.png" || -f "${base}.jpg" ]]; then
      maybe_rm "$svg"
    fi
    continue
  fi

  # moent / kiste: kode bruger .png
  if [[ "$bn" == "moent.svg" || "$bn" == "kiste.svg" ]]; then
    if [[ -f "${base}.webp" || -f "${base}.png" ]]; then
      maybe_rm "$svg"
    fi
  fi
done

# Ældre A-elgor-filer med små bogstavers PNG
for n in 3 4; do
  if [[ -f "assets/aelgorkort${n}.webp" || -f "assets/aelgorkort${n}.png" ]]; then
    maybe_rm "assets/Aelgorkort${n}.svg"
  fi
done

# Dublet: trace bruger Atiach1.png fra pakken, ikke denne gigantiske SVG i assets
maybe_rm "assets/Atiach1.svg"

echo "== Nedskalerer PNG/JPEG (sips -Z) =="
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  case "$f" in
    *bogstaver*)
      max="$MAX_BOGSTAV"
      ;;
    *)
      max="$MAX_RASTER"
      ;;
  esac
  w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/ {print $2}')
  if [[ "$w" == "<nil>" ]] || [[ -z "$w" ]]; then
    continue
  fi
  m=$w
  [[ "${h:-0}" -gt "$m" ]] && m=$h
  if [[ "$m" -gt "$max" ]]; then
    sips -Z "$max" "$f" >/dev/null
    echo "  -Z $max: $f"
  fi
  # Lettere JPEG: genkode efter eventuel nedskalering
  if [[ "$f" == *.jpg ]] || [[ "$f" == *.jpeg ]] || [[ "$f" == *.JPG ]]; then
    sips -s format jpeg -s formatOptions 82 "$f" >/dev/null 2>&1 || true
  fi
done < <(find assets packages/alfamon_trace/Assets -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) ! -name '.DS_Store')

du -sh assets packages/alfamon_trace/Assets 2>/dev/null || true
echo "Færdig. Fjernede $removed SVG-fil(er)."
