#!/usr/bin/env bash
# Converts the weapon textures from _src_pubg (TGA) into assets/arsenal/tex:
#   <id>_d.jpg   base colour
#   <id>_n.png   normal map, green flipped (the sources use the DirectX convention, Godot the OpenGL one)
#   <id>_rma.jpg roughness (R), metallic (G), ambient occlusion (B)
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC=_src_pubg
OUT=assets/arsenal/tex
mkdir -p "$OUT"
while read -r id dir pre; do
  t="$SRC/$dir/Texture/$pre"
  convert "$t"_D.tga -quality 92 "$OUT/${id}_d.jpg"
  convert "$t"_N.tga -channel G -negate +channel "$OUT/${id}_n.png"
  if [ -f "$t"_RMA.tga ]; then convert "$t"_RMA.tga -quality 95 "$OUT/${id}_rma.jpg"
  else convert "$t"_RM.tga -quality 95 "$OUT/${id}_rma.jpg"; fi
done <<'LIST'
akm AKM T_WEP_AK47
aug AUG T_WEP_AUG
awm AWM T_WEP_AWM
groza Groza T_WEP_GROZA
k98 K98k T_WEP_98k
m16 M16A4 T_WEP_M16A4
m24 M24 T_WEP_M24
m416 M416 T_WEP_M416
mk14 MK14 T_WEP_MK14
mini14 Mini14 T_WEP_Mini14
scar SCAR-L T_WEP_SCAR
sks SKS WEP_SKS
slr SLR T_WEP_SLR
vss VSS T_WEP_VSS
win94 Win1894 T_WEP_Win1894
LIST
echo "textures written to $OUT"
