class_name GuestImport
extends RefCounted
## Reads a pasted guest list into a plan. One guest per line: "Name, group, diet", or tab-separated
## columns as copied from a spreadsheet. Cells may be quoted the CSV way ("Lee, Ann" or "say ""hi""").
## "Group:" on its own line sets the group for the lines below it. A line with "&" or "and" between
## first names ("Tom & Lisa Meyer") adds a couple, and "+1" at the end adds a guest of theirs.

const HEADER_WORDS := ["name", "guest", "guests", "names"]
## The most lines one quoted cell may span before its opening quote counts as a typo.
const MAX_ROW_LINES := 5


## Adds the guests of a list. Returns the ids added.
static func import_text(plan: Seating, text: String) -> Array[int]:
	return read(plan, text).added


## Adds the guests of a list. Returns {"added": [ids], "full": true when the guest limit cut it short}.
static func read(plan: Seating, text: String) -> Dictionary:
	var added: Array[int] = []
	var full := false
	var group := ""
	var header_checked := false
	for raw in rows(text):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.ends_with(":") and not line.contains(",") and not line.contains("\t"):
			group = line.trim_suffix(":").strip_edges()
			continue
		var cells := split_row(line)
		if not header_checked:
			header_checked = true
			if cells[0].to_lower() in HEADER_WORDS:
				continue
		if cells[0] == "":
			continue
		var line_group := cells[1] if cells.size() > 1 and cells[1] != "" else group
		var diet := cells[2] if cells.size() > 2 else ""
		var ids := _add_household(plan, cells[0], line_group, diet)
		if ids.is_empty():
			full = true
			break
		added.append_array(ids)
	return {"added": added, "full": full}


## The rows of a list, one per line, except that a quoted cell with a line break in it (as a
## spreadsheet writes it) keeps its row together, the line break read as a space. A quote that never
## closes within MAX_ROW_LINES lines is taken as a typo, and those lines stay rows of their own.
static func rows(text: String) -> PackedStringArray:
	var lines := text.replace("\r", "").split("\n")
	var out := PackedStringArray()
	var i := 0
	while i < lines.size():
		var joined := lines[i]
		var end := i
		while _scan(joined)[1] and end + 1 < lines.size() and end - i + 1 < MAX_ROW_LINES:
			end += 1
			joined += " " + lines[end]
		if _scan(joined)[1]:
			# The quote never closes: a typo, so this line stands alone.
			out.append(lines[i])
			i += 1
		else:
			out.append(joined)
			i = end + 1
	return out


## Splits one line into cells: on tabs when it has any (a spreadsheet copy), on commas otherwise.
## A cell in double quotes keeps its commas, and "" inside it is one quote.
static func split_row(line: String) -> Array[String]:
	return _scan(line)[0]


## Reads a line cell by cell. Returns [cells, true when a quoted cell is still open at the end].
static func _scan(line: String) -> Array:
	var separator := "\t" if line.contains("\t") else ","
	var cells: Array[String] = []
	var cell := ""
	var quoted := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if quoted:
			if c != "\"":
				cell += c
			elif i + 1 < line.length() and line[i + 1] == "\"":
				cell += "\""
				i += 1
			else:
				quoted = false
		elif c == "\"" and cell.strip_edges() == "":
			quoted = true
			cell = ""
		elif c == separator:
			cells.append(cell.strip_edges())
			cell = ""
		else:
			cell += c
		i += 1
	cells.append(cell.strip_edges())
	return [cells, quoted]


## Adds one line's guests: one person, a couple, and a "+1". Adds nobody when they do not all fit.
static func _add_household(plan: Seating, text: String, group: String, diet: String) -> Array[int]:
	var ids: Array[int] = []
	var name := text
	var plus := RegEx.create_from_string("\\s*\\+\\s*1\\s*$")
	var plus_one := plus.search(name) != null
	if plus_one:
		name = plus.sub(name, "")
	var pair := RegEx.create_from_string("^(\\S+)\\s+(?:&|and|und|et|y)\\s+(\\S+)(?:\\s+(.+))?$")
	var m := pair.search(name)
	var needed := (2 if m else 1) + (1 if plus_one else 0)
	if plan.room_for_guests() < needed:
		return ids
	if m:
		var surname := m.get_string(3)
		var first := m.get_string(1) + ("" if surname == "" else " " + surname)
		var second := m.get_string(2) + ("" if surname == "" else " " + surname)
		var a := plan.add_guest(first, group, diet)
		ids.append(a)
		ids.append(plan.add_guest(second, group, diet, plan.get_guest(a).party))
	else:
		ids.append(plan.add_guest(name, group, diet))
	if plus_one:
		ids.append(plan.add_guest("Guest of %s" % plan.get_guest(ids[0]).name, group, "", plan.get_guest(ids[0]).party))
	return ids
