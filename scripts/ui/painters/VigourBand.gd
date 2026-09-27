## VigourBand — the saved run's health, as wax lying in a cut channel.
##
## Replaces a dotted-leader row on the title screen's CURRENT RUN plate:
##
##     HEALTH ................ 30 / 30
##
## WHY A LENGTH AND NOT ONLY A NUMERAL. Same argument as `RunRoad`: health has a
## known extent, so it can be encoded as position along a common scale, which is
## the most accurately decoded encoding there is (Cleveland & McGill, JASA
## 79(387), 1984). "22 / 30" is a pair of symbols that have to be read and then
## divided; a length is seen. THE NUMERAL STAYS — the band answers "am I in
## trouble" at a glance, the numeral answers "by exactly how much", and those are
## different questions. Dropping either is the mistake.
##
## THE LOW-HEALTH CUE IS NOT A COLOUR. Below `alarm_at` the wax lifts toward
## ember AND takes the same glare falloff the road's standard carries (Zavagno &
## Caputo, Perception 30(2), 2001) — but the LENGTH has already said it, so both
## are redundant reinforcement rather than the signal. A state carried only by
## hue is unreadable to a red-green colourblind player, and this is the one row
## on the plate where that would matter.
##
## THE MATERIAL IS THE GAME'S OWN. Hero HP is a pressed oxblood wax seal
## everywhere else in this game (WaxSeal, WoundSeal, the card stat seals), so the
## band is that same wax lying in a channel rather than a tinted `ProgressBar`
## track. A progress bar would be the only piece of web-page chrome on the
## screen, which is the exact sentence WoundSeal was written to end on the combat
## board.
##
## No `class_name`: preload under a same-name const like every painter here.
extends Control

const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")
const ChannelBand := preload("res://scripts/ui/painters/ChannelBand.gd")

## The plate the channel is cut into.
var plate := Color(0.105, 0.082, 0.062)
## Warm metal for the lit rim — never white (Cook & Torrance 1982; see ChannelBand).
var lit := Color(1.0, 0.88, 0.58)
## HEALTH_RED_DROP, the oxblood the hero's HP seal is pressed in.
var wax := Color(0.510, 0.137, 0.106)
## What the wax lifts toward when the run is in trouble.
var ember := Color(0.94, 0.42, 0.20)

var hp := 30
var max_hp := 30
## Fraction below which the run reads as in trouble. 0.35 rather than a half:
## at exactly half a bar reads as "middling", and the cue has to mean something.
var alarm_at := 0.35

## 15, matching RunRoad — see its BAND_H for the measurement. A channel narrower
## than about a dozen pixels has nowhere to put a wall, a floor and a rim, and
## collapses back into the flat band the construction exists to replace.
const BAND_H := 15.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func configure(current: int, maximum: int) -> void:
	hp = maxi(current, 0)
	max_hp = maxi(maximum, 1)
	queue_redraw()


func fraction() -> float:
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)


func _draw() -> void:
	if size.x < 40.0 or size.y < 6.0:
		return
	var band := Rect2(0.0, roundf((size.y - BAND_H) * 0.5), size.x, BAND_H)
	var f := fraction()
	var hurt := f <= alarm_at and f > 0.0

	ChannelBand.draw_lip(self, band, plate, lit)
	ChannelBand.draw_channel(self, band, plate, lit)

	var fill := wax.lerp(ember, 0.62) if hurt else wax
	if hurt:
		# The glare ramp, around the wax that is LEFT. Built as a polygon so the
		# sanctioned funnel does the falloff — see RunRoad._draw_standard.
		var w := maxf(band.size.x * f, 2.0)
		var lump := PackedVector2Array([
			band.position, band.position + Vector2(w, 0),
			band.position + Vector2(w, band.size.y),
			band.position + Vector2(0, band.size.y)])
		LayerStyle.outer_glow(self, lump, ember, 8.0, 0.22, 4)

	ChannelBand.draw_fill(self, band, f, fill, lit, 0.32)
