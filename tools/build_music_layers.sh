#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# BUILD A LAYERED CUE FROM DEMUCS STEMS (2026-09-14)
#
# Turns a demucs output directory into the three OGG layers AudioBank expects:
#
#     <name>_bed.ogg     strings/brass/foundation — stands alone, index 0
#     <name>_perc.ogg    percussion               — index 1
#     <name>_choir.ogg   voices                   — index 2
#
# Usage:
#   tools/build_music_layers.sh <demucs_stem_dir> <name> [flat_track_for_compare]
#
# e.g. tools/build_music_layers.sh /tmp/stems_out/htdemucs combat combat
#
# WHY THREE AND NOT FOUR. Demucs' model is trained on pop and emits
# drums/bass/other/vocals. On orchestral material there is no bass-guitar-shaped
# source, so `bass` comes out far under the mix (measured -31.7 LUFS on the act-1
# track, 19.6 dB below the bed) — it is foundation you would never want ABSENT,
# not a layer you would ever want to toggle. It is folded into the bed. `vocals`
# catches choir, which IS a useful dramatic layer on this material.
#
# WHY ONE UNIFORM GAIN. The full arrangement is measured and a SINGLE gain
# applied to all three layers. Normalising each layer separately would rebalance
# the piece — the arrangement is precisely the thing being preserved. The check
# that it worked is printed at the end: the summed layers should land on the same
# integrated loudness as the flat track they replace.
#
# CHECK THE PER-STEM ENERGY REPORT before trusting the result. If `vocals` comes
# out 25+ dB under the bed, that track has no choir and a three-layer cue would
# ship with a dead index 2 — leave it out of AudioBank.LAYERED_CUES instead, and
# Combat falls back to the flat pool automatically.
# ---------------------------------------------------------------------------
set -uo pipefail

STEMS="${1:?usage: build_music_layers.sh <demucs_stem_dir> <name> [flat_track]}"
NAME="${2:?missing cue name}"
FLAT="${3:-$NAME}"
# TARGET defaults to the FLAT TRACK'S OWN measured loudness, not a global -16.
# The contract is "level-identical to the cue it replaces", and the library is
# not perfectly flat — combat_act3 sits at -16.50, so targeting -16 made its
# layered version 0.42 LU louder than the track it stands in for AND pushed the
# full arrangement to -1.13 dBTP, over the library's -1.5 ceiling. Matching the
# flat track fixes both at once. Override with TARGET_I= if you mean to.
OGG_QUALITY="${OGG_QUALITY:-5}"
OUT="assets/audio/music/layers"
MUSIC="assets/audio/music"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v ffmpeg >/dev/null || { echo "ffmpeg not on PATH"; exit 1; }
for s in other bass drums vocals; do
  [ -f "$STEMS/$s.wav" ] || { echo "missing stem: $STEMS/$s.wav"; exit 1; }
done
mkdir -p "$OUT"

meas() {  # echoes "I TP LRA"
  local j; j="$(ffmpeg -hide_banner -nostats -i "$1" -af loudnorm=print_format=json -f null - 2>&1 | tail -20)"
  echo "$(echo "$j" | sed -n 's/.*"input_i" *: *"\(.*\)".*/\1/p') \
$(echo "$j" | sed -n 's/.*"input_tp" *: *"\(.*\)".*/\1/p') \
$(echo "$j" | sed -n 's/.*"input_lra" *: *"\(.*\)".*/\1/p')"
}

if [ -z "${TARGET_I:-}" ]; then
  if [ -f "$MUSIC/$FLAT.ogg" ]; then
    read -r TARGET_I _ _ <<<"$(meas "$MUSIC/$FLAT.ogg")"
    echo "target = $FLAT.ogg's own loudness: $TARGET_I LUFS"
  else
    TARGET_I="-16"
    echo "no flat track $MUSIC/$FLAT.ogg — falling back to target $TARGET_I LUFS"
  fi
fi

echo "=== per-stem energy (is any layer dead?) ==="
declare -A SI
for s in other vocals drums bass; do
  read -r i _ _ <<<"$(meas "$STEMS/$s.wav")"; SI[$s]="$i"
  printf "  %-7s %s LUFS\n" "$s" "$i"
done
gap="$(awk -v a="${SI[other]}" -v b="${SI[vocals]}" 'BEGIN{printf "%.1f", a-b}')"
echo "  voices sit ${gap} dB under the bed"
if awk -v g="$gap" 'BEGIN{exit !(g>25.0)}'; then
  echo "  *** WARNING: >25 dB — this track probably has no choir. A three-layer"
  echo "      cue would ship with a dead index 2; consider leaving it unregistered."
fi

echo "=== building ==="
ffmpeg -v error -y -i "$STEMS/other.wav" -i "$STEMS/bass.wav" \
  -filter_complex "amix=inputs=2:normalize=0" "$TMP/bed.wav"
cp "$STEMS/drums.wav"  "$TMP/perc.wav"
cp "$STEMS/vocals.wav" "$TMP/choir.wav"

# ONE gain for all three, derived from the full arrangement.
ffmpeg -v error -y -i "$TMP/bed.wav" -i "$TMP/perc.wav" -i "$TMP/choir.wav" \
  -filter_complex "amix=inputs=3:normalize=0" "$TMP/full.wav"
read -r fi ftp _ <<<"$(meas "$TMP/full.wav")"
gain="$(awk -v t="$TARGET_I" -v i="$fi" 'BEGIN{printf "%.2f", t-i}')"
echo "  full arrangement $fi LUFS (TP $ftp) -> uniform gain ${gain} dB"

for l in bed perc choir; do
  ffmpeg -v error -y -i "$TMP/$l.wav" -af "volume=${gain}dB" \
    -c:a libvorbis -q:a "$OGG_QUALITY" "$OUT/${NAME}_${l}.ogg" \
    || { echo "encode failed: $l"; exit 1; }
done

echo "=== verify: the summed layers must match the flat track they replace ==="
ffmpeg -v error -y -i "$OUT/${NAME}_bed.ogg" -i "$OUT/${NAME}_perc.ogg" -i "$OUT/${NAME}_choir.ogg" \
  -filter_complex "amix=inputs=3:normalize=0" "$TMP/sum.wav"
read -r si stp slra <<<"$(meas "$TMP/sum.wav")"
printf "  layered (full)  I=%-8s TP=%-8s LRA=%s\n" "$si" "$stp" "$slra"
if [ -f "$MUSIC/$FLAT.ogg" ]; then
  read -r ci ctp clra <<<"$(meas "$MUSIC/$FLAT.ogg")"
  printf "  flat %-11s I=%-8s TP=%-8s LRA=%s\n" "$FLAT.ogg" "$ci" "$ctp" "$clra"
  awk -v a="$si" -v b="$ci" 'BEGIN{d=a-b; if(d<0)d=-d;
    printf "  delta %.2f LU  %s\n", d, (d<0.5 ? "OK — level-identical to what it replaces" : "*** CHECK: the layered cue is not the same level as the flat track")}'
fi
echo "=== intensity steps (should climb, and stay textural not a volume ramp) ==="
ffmpeg -v error -y -i "$OUT/${NAME}_bed.ogg" -i "$OUT/${NAME}_perc.ogg" \
  -filter_complex "amix=inputs=2:normalize=0" "$TMP/i1.wav"
read -r b0 _ _ <<<"$(meas "$OUT/${NAME}_bed.ogg")"
read -r b1 _ _ <<<"$(meas "$TMP/i1.wav")"
climb="$(awk -v a="$b0" -v b="$si" 'BEGIN{printf "%.2f", b-a}')"
printf "  bed only %-8s +perc %-8s full %-8s  (climb %s LU)\n" "$b0" "$b1" "$si" "$climb"
# The escalation is supposed to be TEXTURAL — you notice instruments arriving,
# not the volume knob turning. Past ~2 LU the bed-only state is audibly quiet
# rather than audibly sparse, which on a muster round reads as "the music is
# broken" instead of "the music is waiting". It is not automatically wrong on a
# boss cue (a hushed opening that crashes in is a real device), but it is a
# judgement someone should make deliberately rather than inherit.
if awk -v c="$climb" 'BEGIN{exit !(c>2.0)}'; then
  echo "  *** NOTE: climb >2 LU — this cue's bed-only state is quiet, not just"
  echo "      sparse. Usually means the choir carries the piece (check the"
  echo "      voices-under-bed figure above). Judge the muster round by ear."
fi
ls -la "$OUT/${NAME}"_*.ogg
echo
echo "Now add to AudioBank.LAYERED_CUES under key '$NAME' and run:"
echo "  Godot --headless --import --path \"D:\\Godot\""
echo "  Godot --headless --path \"D:\\Godot\" res://tools/_probe_music_layers.tscn"
