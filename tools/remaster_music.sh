#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# MUSIC LIBRARY RE-MASTER (2026-09-14)
#
# Levels the 49-track library to ONE integrated loudness and converts it to OGG
# Vorbis. Writes to a SIDE FOLDER — it never touches assets/audio/music — so the
# result can be auditioned against the original before anything is committed.
#
# WHY (all figures measured with ffmpeg loudnorm over the shipped assets):
#
#   1. LEVEL. The library spans -22.1 to -8.1 LUFS, a 13.9 LU range, and the
#      spread lives INSIDE the pools play_music_random draws from: the event
#      pool is 8.6 LU wide (event -18.1 vs event_b -9.5), the act-1 map pool
#      7.9 LU (map_b -22.1 vs map -14.2). 8 LU is roughly a doubling of
#      perceived loudness, so two visits to the same screen can differ by that
#      much at random. Nothing in the mix compensates, because nothing measures.
#
#   2. CLIPPING. Six tracks are mastered above 0 dBTP and clip on decode:
#      event_b +0.84, combat_act2_c +0.80, shop_c +0.59, combat_act2_d +0.23,
#      combat_act3_c +0.15, shop +0.14 dBTP.
#
#   3. LOOPING. MP3 carries encoder delay and end padding, and the format has no
#      standard way to record them, so a looped MP3 inserts a short silence at
#      the seam. The files are not even consistent about it: map.mp3 has a LAME
#      gapless header, combat.mp3 has none at all. OGG Vorbis defines its own
#      start and end precisely and the padding is trimmed on decode, which
#      removes the question rather than managing it. The project's own
#      MUSIC_CREDITS.md already recommends OGG; nobody did the conversion.
#
#   4. SIZE. 446 MB of 320 kbps MP3. OGG q5 lands at 215 MB (measured over all
#      49) for material no listener could distinguish under gameplay, and two
#      files carry embedded JPEG cover art (combat_act2_c, event_b) that is
#      decoded and discarded.
#
# METHOD — the transparent one first, with a narrow escape hatch.
#
# Each track is measured and a STATIC GAIN applied. No compression, no dynamics
# processing: ffmpeg's loudnorm in its normal (dynamic) mode would reshape the
# program and flatten the wide-range tracks, and combat_boss_d's 18.2 LU of
# range is the point of combat_boss_d.
#
# Static gain alone cannot fix a track that is quiet AND peaky — the peak hits
# the ceiling before the average reaches target. Four tracks were in that state
# (map_b, event, map_act3, map_e), and on the first pass this script backed the
# gain OFF for them, so three ended up QUIETER than they started and the four of
# them accounted for the entire residual spread.
#
# So: when static gain alone cannot reach target, a LOOK-AHEAD LIMITER is
# inserted ahead of it (alimiter, asc on, level=false — the default level=true
# auto-normalises back to 0 dB and would silently override the gain). This is
# the smallest honest intervention and it is what a mastering engineer would do.
# The loop converges on the target and the report prints how much peak reduction
# each track actually needed, which is the number to audit: MEASURED 2.1-4.2 dB
# on those four, costing at most 0.5 LU of loudness range (map_b 4.10 -> 4.00,
# event 12.80 -> 12.30). A track needing much more than ~4 dB is telling you it
# wants replacing, not processing.
#
# Set MAX_LIMIT_DB=0 to disable limiting entirely and get the original
# gain-only behaviour back.
#
# Usage:  tools/remaster_music.sh [target_LUFS] [out_dir]
#   defaults: -16 LUFS (near the library's current median, so the existing SFX
#   balance is preserved — the win here is CONSISTENCY, not absolute level) into
#   assets/audio/music_remastered/
#
# To adopt the result: audition it, then move the .ogg files into
# assets/audio/music/ and delete the .mp3s. AudioBank._resolve_music_path already
# prefers .ogg over .mp3, so the swap needs no code change.
# ---------------------------------------------------------------------------
set -uo pipefail

TARGET_I="${1:--16}"
# SRC_DIR override exists so this can be pointed at ORIGINALS recovered from git
# (`git show HEAD:assets/audio/music/x.mp3 > …`). Re-running it over an already
# re-mastered library would be a lossy-to-lossy transcode — always re-master
# from the source masters, never from the previous output.
SRC="${SRC_DIR:-assets/audio/music}"
OUT="${2:-assets/audio/music_remastered}"
CEILING_DBTP="-1.5"   # standard delivery ceiling; leaves room for codec overshoot
OGG_QUALITY="5"       # ~160 kbps VBR
MAX_LIMIT_DB="${MAX_LIMIT_DB:-5.0}"  # most peak reduction allowed; 0 disables limiting
LIMIT_CEIL_DB="-2.0"  # limiter threshold (SAMPLE peak) — sits below CEILING_DBTP
                      # on purpose, because alimiter measures sample peaks and
                      # inter-sample true peak runs higher. Verified by measuring
                      # the OUTPUT's true peak below, not by trusting the setting.
CONVERGE_PASSES=5

command -v ffmpeg >/dev/null || { echo "ffmpeg not on PATH"; exit 1; }
[ -d "$SRC" ] || { echo "no $SRC (run from the project root)"; exit 1; }
mkdir -p "$OUT"

measure() {  # $1 = file; echoes "I TP LRA"
  local j
  j="$(ffmpeg -hide_banner -nostats -i "$1" -af loudnorm=print_format=json -f null - 2>&1 | tail -20)"
  echo "$(echo "$j" | sed -n 's/.*"input_i" *: *"\(.*\)".*/\1/p') \
$(echo "$j" | sed -n 's/.*"input_tp" *: *"\(.*\)".*/\1/p') \
$(echo "$j" | sed -n 's/.*"input_lra" *: *"\(.*\)".*/\1/p')"
}

printf "%-22s %7s %7s %7s %7s %6s  %s\n" FILE "I(in)" gain "I(out)" "TP(out)" dLRA note
printf -- "---------------------------------------------------------------------------------\n"

for f in "$SRC"/*.mp3 "$SRC"/*.ogg "$SRC"/*.wav; do
  [ -e "$f" ] || continue
  base="$(basename "${f%.*}")"

  read -r in_i in_tp in_lra <<<"$(measure "$f")"
  if [ -z "$in_i" ] || [ "$in_i" = "-inf" ]; then
    printf "%-22s %7s %7s %7s %7s %6s  SKIPPED (unmeasurable)\n" "$base" - - - - -
    continue
  fi

  gain="$(awk -v t="$TARGET_I" -v i="$in_i" 'BEGIN{printf "%.2f", t-i}')"
  note=""
  # Would a plain static gain breach the ceiling? If so this track is
  # quiet-and-peaky and needs the limiter; otherwise gain alone is transparent
  # and we do not touch the dynamics at all.
  hdr="$(awk -v c="$CEILING_DBTP" -v tp="$in_tp" -v g="$gain" 'BEGIN{printf "%.2f", c-(tp+g)}')"
  need_limit=0
  awk -v h="$hdr" 'BEGIN{exit !(h<0)}' && need_limit=1
  if [ "$need_limit" = 1 ] && awk -v m="$MAX_LIMIT_DB" 'BEGIN{exit !(m<=0)}'; then
    # limiting disabled — fall back to the old behaviour and say so
    gain="$(awk -v g="$gain" -v h="$hdr" 'BEGIN{printf "%.2f", g+h}')"
    need_limit=0
    note="gain reduced to hold ${CEILING_DBTP} dBTP (limiting off)"
  fi

  lim_db="$LIMIT_CEIL_DB"
  for pass in $(seq 1 "$CONVERGE_PASSES"); do
    if [ "$need_limit" = 1 ]; then
      lim="$(awk -v d="$lim_db" 'BEGIN{printf "%.4f", 10^(d/20)}')"
      chain="volume=${gain}dB,alimiter=limit=${lim}:attack=5:release=50:level=false:asc=true"
    else
      chain="volume=${gain}dB"
    fi
    # -vn strips embedded cover art (combat_act2_c and event_b carry JPEGs).
    ffmpeg -v error -y -i "$f" -map 0:a:0 -vn -af "$chain" \
      -c:a libvorbis -q:a "$OGG_QUALITY" "$OUT/$base.ogg" \
      || { echo "  encode failed: $base"; continue 2; }
    read -r out_i out_tp out_lra <<<"$(measure "$OUT/$base.ogg")"
    # VERIFY, DO NOT ASSUME (2026-09-14). The gain-only path used to break here
    # on the theory that in_tp + gain lands under the ceiling by construction. It
    # does — before encoding. Vorbis overshoots true peak a little, so seven
    # tracks shipped between -1.42 and -0.97 dBTP against a -1.5 target on the
    # first pass, all of them "gain reduced to hold the ceiling" cases, i.e. the
    # ones the arithmetic was supposedly protecting. Measure the OUTPUT and, if
    # it overshot, engage the limiter and converge like everything else.
    if [ "$need_limit" = 0 ]; then
      awk -v p="$out_tp" -v c="$CEILING_DBTP" 'BEGIN{exit !(p>c)}' || break
      awk -v m="$MAX_LIMIT_DB" 'BEGIN{exit !(m<=0)}' && break   # limiting disabled
      need_limit=1
      # Restore the full target gain: it was backed off to respect a ceiling the
      # limiter is now going to hold properly.
      gain="$(awk -v t="$TARGET_I" -v i="$in_i" 'BEGIN{printf "%.2f", t-i}')"
      continue
    fi
    # converged? within 0.3 LU of target AND under the true-peak ceiling.
    awk -v a="$out_i" -v t="$TARGET_I" -v p="$out_tp" -v c="$CEILING_DBTP" \
      'BEGIN{exit !((a-t<0.3)&&(a-t>-0.3)&&(p<=c))}' && break
    # peak still over: pull the limiter threshold down. Otherwise chase the
    # loudness the limiter just removed.
    awk -v p="$out_tp" -v c="$CEILING_DBTP" 'BEGIN{exit !(p>c)}' \
      && lim_db="$(awk -v d="$lim_db" 'BEGIN{printf "%.2f", d-0.5}')"
    gain="$(awk -v g="$gain" -v a="$out_i" -v t="$TARGET_I" 'BEGIN{printf "%.2f", g+(t-a)}')"
  done

  if [ "$need_limit" = 1 ]; then
    # How much peak reduction did this actually cost? Anything past MAX_LIMIT_DB
    # is flagged: that track wants replacing, not processing.
    red="$(awk -v a="$in_tp" -v g="$gain" -v n="$out_tp" 'BEGIN{printf "%.1f", (a+g)-n}')"
    note="limited ${red} dB"
    awk -v r="$red" -v m="$MAX_LIMIT_DB" 'BEGIN{exit !(r>m)}' \
      && note="$note  *** OVER ${MAX_LIMIT_DB} dB — consider replacing this track ***"
  fi
  dlra="$(awk -v a="$in_lra" -v b="$out_lra" 'BEGIN{printf "%+.1f", b-a}')"
  printf "%-22s %7s %7s %7s %7s %6s  %s\n" \
    "$base" "$in_i" "$gain" "$out_i" "$out_tp" "$dlra" "$note"
done

echo
echo "wrote OGG to $OUT/"
du -ch "$OUT"/*.ogg 2>/dev/null | tail -1
echo "original:"
du -ch "$SRC"/*.mp3 2>/dev/null | tail -1
