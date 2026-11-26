class_name LabelLayout
extends RefCounted
## Places name labels next to their seats so that no label overlaps another label, a seat or a table.
## Each label goes straight out from its seat (away from the table); when that spot is taken it tries
## a little further out, up to TIERS times, and is left out when nothing fits.
## Pure geometry in screen pixels, so the tests check it without drawing anything.

const TIERS := 3


## items: one Dictionary per label, in priority order (the first ones get the best spots):
##   "anchor": Vector2, the seat centre; "radius": float, the seat radius;
##   "dir": Vector2, the unit direction away from the table; "size": Vector2, the label box.
## discs: circles to keep clear, as Vector3(x, y, radius) (the seats, round table tops).
## blocks: rectangles to keep clear (long and head table tops).
## gap: the space between a seat and its label.
## Returns one Rect2 per item; a Rect2 with no area means the label is left out.
static func place(items: Array[Dictionary], discs: PackedVector3Array, blocks: Array[Rect2], gap: float) -> Array[Rect2]:
	var placed: Array[Rect2] = []
	var out: Array[Rect2] = []
	for item in items:
		var spot := _find_spot(item, discs, blocks, placed, gap)
		out.append(spot)
		if spot.has_area():
			placed.append(spot)
	return out


static func _find_spot(item: Dictionary, discs: PackedVector3Array, blocks: Array[Rect2], placed: Array[Rect2], gap: float) -> Rect2:
	var size: Vector2 = item.size
	var dir: Vector2 = item.dir.normalized() if item.dir != Vector2.ZERO else Vector2.DOWN
	var half := size / 2.0
	# How far the box reaches back towards the seat, measured along dir.
	var back := absf(dir.x) * half.x + absf(dir.y) * half.y
	var start: float = item.radius + gap + back
	for tier in TIERS:
		var center: Vector2 = item.anchor + dir * (start + tier * (size.y + gap))
		var box := Rect2(center - half, size)
		if _is_free(box, discs, blocks, placed):
			return box
	return Rect2()


static func _is_free(box: Rect2, discs: PackedVector3Array, blocks: Array[Rect2], placed: Array[Rect2]) -> bool:
	for other in placed:
		if box.intersects(other):
			return false
	for block in blocks:
		if box.intersects(block):
			return false
	for d in discs:
		if rect_hits_circle(box, Vector2(d.x, d.y), d.z):
			return false
	return true


## True when a rectangle and a circle overlap (touching edges do not count).
static func rect_hits_circle(box: Rect2, center: Vector2, radius: float) -> bool:
	var closest := center.clamp(box.position, box.end)
	return closest.distance_squared_to(center) < radius * radius
