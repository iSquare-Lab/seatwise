class_name SeatingSolver
extends RefCounted
## "Seat everyone": seats every guest who waits, household by household, then improves the whole plan
## by swapping seats (simulated annealing, cooling down round by round), and ends with a pass that tries
## every swap. Locked guests never move.
##
## It works in small steps so the App can draw the tables filling up: call step() until it returns
## false (progress() says how far it is). run() does all steps at once; the tests and
## Seating.auto_seat() use that, so they check exactly what the App runs.
##
## The inner loop works on packed arrays of guest indexes (not dictionaries) so it is fast in the browser.

const ROUNDS := 40
const STEPS_PER_ROUND := 280
const START_TEMPERATURE := 20.0
## The final pass tries every pair of movable seats, so it only runs up to this many.
const POLISH_LIMIT := 160

## Costs the solver minimises. Keeping people apart and households together matter most.
const COST_APART := 400.0
const COST_PARTY_SPLIT := 120.0
const BONUS_PARTY_NEIGHBOUR := 10.0
const BONUS_SAME_GROUP := 3.0
const COST_MIXED_GROUP := 1.0
const COST_LONELY := 6.0

var plan: Seating
var rounds: int
var steps_per_round: int
var _rng := RandomNumberGenerator.new()
var _round := 0
var _prepared := false
var _finished := false

# Packed state, indexed by guest position in plan.guests and table position in plan.tables.
var _n := 0
var _tcount := 0
var _group := PackedInt32Array()
var _party := PackedInt32Array()
var _avoid := PackedByteArray()
## _seats[t] holds guest indexes, -1 for an empty seat; _pairs[t] the neighbouring seat pairs, flattened.
var _seats: Array[PackedInt32Array] = []
var _pairs: Array[PackedInt32Array] = []
var _lonely_ok := PackedByteArray()
## Guests per household per table: _ptc[party * _tcount + table].
var _ptc := PackedInt32Array()
## The seats that may change: table index and seat index.
var _mt := PackedInt32Array()
var _ms := PackedInt32Array()
var _costs := PackedFloat64Array()


func _init(seating: Seating, seed_value: int = 1, round_count: int = ROUNDS, steps: int = STEPS_PER_ROUND) -> void:
	plan = seating
	rounds = maxi(0, round_count)
	steps_per_round = maxi(0, steps)
	_rng.seed = seed_value


## Does the next piece of work and writes the result into the plan. The first call seats everyone
## who waits, each later call runs one round of swaps, and the last one tries every swap.
## Returns true while there is more to do.
func step() -> bool:
	if _finished:
		return false
	if not _prepared:
		place_unseated(plan)
		_prepare()
		_prepared = true
	elif _round < rounds:
		anneal(steps_per_round, temperature(_round))
		_round += 1
	else:
		polish()
		_finished = true
	_write_back()
	return not _finished


## How much of the work is done, from 0 to 1.
func progress() -> float:
	if _finished:
		return 1.0
	if not _prepared:
		return 0.0
	return float(_round + 1) / float(rounds + 2)


## Runs every step and returns the final score (lower is better).
func run() -> float:
	while step():
		pass
	return total()


## The temperature of a round: hot at first (worse swaps are often kept, to get out of dead ends),
## zero in the last round.
func temperature(round_index: int) -> float:
	return lerpf(START_TEMPERATURE, 0.0, float(round_index) / maxf(1.0, rounds - 1.0))


## The score of a plan as it is (lower is better), with the costs the solver uses.
static func score(seating: Seating) -> float:
	return SeatingSolver.new(seating).total()


## The score of the plan as the solver sees it now.
func total() -> float:
	if not _prepared:
		_prepare()
	var sum := 0.0
	for ti in _tcount:
		sum += _costs[ti]
	for p in _ptc.size() / maxi(1, _tcount):
		sum += _party_cost(p)
	return sum


# ------------------------------------------------------------------ Placing who waits

## Seats everyone who is not seated yet, household by household, at the table that suits them best
## (room for the whole household, people from their group, nobody they must avoid).
static func place_unseated(seating: Seating) -> void:
	var lookup := {}
	for g in seating.guests:
		lookup[g.id] = g
	var households := seating.parties()
	var waiting := seating.unseated()
	var done := {}
	# Biggest households first: they are the hardest to fit.
	var order: Array = []
	for id in waiting:
		var p: int = lookup[id].party
		if not done.has(p):
			done[p] = true
			order.append(p)
	order.sort_custom(func(a: int, b: int) -> bool: return households[a].size() > households[b].size() or (households[a].size() == households[b].size() and a < b))
	for p: int in order:
		var members: Array = households[p].filter(func(m: int) -> bool: return waiting.has(m))
		var best := -1
		var best_score := INF
		for ti in seating.tables.size():
			var t := seating.tables[ti]
			var free: int = t.guests.count(0)
			if free == 0:
				continue
			var s := 0.0
			if free < members.size():
				s += 1000.0 * (members.size() - free)
			for g: int in t.guests:
				if g == 0:
					continue
				for m: int in members:
					if seating.is_apart(g, m):
						s += COST_APART
					if lookup[g].group != "" and lookup[g].group == lookup[m].group:
						s -= BONUS_SAME_GROUP
					elif lookup[g].group != "" and lookup[m].group != "":
						s += COST_MIXED_GROUP
			# Prefer emptier tables a little, so groups get room to grow.
			s -= free * 0.2
			if s < best_score:
				best_score = s
				best = ti
		if best == -1:
			return
		var table := seating.tables[best]
		# Fill seats next to the household first, so it sits side by side.
		for m: int in members:
			var slot := _free_seat_near(table, members)
			if slot == -1:
				break
			table.guests[slot] = m


static func _free_seat_near(t: Dictionary, members: Array) -> int:
	var n: int = t.seats
	for i in n:
		if t.guests[i] == 0:
			var left: int = t.guests[(i - 1 + n) % n]
			var right: int = t.guests[(i + 1) % n]
			if members.has(left) or members.has(right):
				return i
	return t.guests.find(0)


# ------------------------------------------------------------------ Swapping seats

## Tries `steps` random swaps at a temperature (0 keeps only swaps that help).
func anneal(steps: int, temp: float) -> void:
	if not _prepared:
		_prepare()
		_prepared = true
	var movable := _mt.size()
	if movable < 2:
		return
	for i in steps:
		var ia := _rng.randi() % movable
		var ib := _rng.randi() % movable
		if ia != ib:
			_try(ia, ib, temp)
	_write_back()


## Tries every pair of movable seats and keeps each swap that helps, until a full pass finds none.
func polish() -> void:
	if not _prepared:
		_prepare()
		_prepared = true
	var movable := _mt.size()
	if movable < 2 or movable > POLISH_LIMIT:
		return
	for pass_index in 4:
		var better := false
		for ia in movable:
			for ib in range(ia + 1, movable):
				if _try(ia, ib, 0.0):
					better = true
		if not better:
			break
	_write_back()


func _prepare() -> void:
	var guests := plan.guests
	var tables := plan.tables
	_n = guests.size()
	_tcount = tables.size()
	var index := {}
	var group_ids := {}
	var party_ids := {}
	var locked := PackedByteArray()
	_group = PackedInt32Array()
	_party = PackedInt32Array()
	_group.resize(_n)
	_party.resize(_n)
	locked.resize(_n)
	for i in _n:
		var g := guests[i]
		index[g.id] = i
		if g.group == "":
			_group[i] = -1
		else:
			if not group_ids.has(g.group):
				group_ids[g.group] = group_ids.size()
			_group[i] = group_ids[g.group]
		if not party_ids.has(g.party):
			party_ids[g.party] = party_ids.size()
		_party[i] = party_ids[g.party]
		locked[i] = 1 if g.locked else 0
	_avoid = PackedByteArray()
	_avoid.resize(_n * _n)
	for pair in plan.apart:
		if index.has(pair.x) and index.has(pair.y):
			_avoid[index[pair.x] * _n + index[pair.y]] = 1
			_avoid[index[pair.y] * _n + index[pair.x]] = 1
	_seats.clear()
	_pairs.clear()
	_lonely_ok = PackedByteArray()
	_ptc = PackedInt32Array()
	_ptc.resize(party_ids.size() * _tcount)
	_mt = PackedInt32Array()
	_ms = PackedInt32Array()
	for ti in _tcount:
		var t := tables[ti]
		var row := PackedInt32Array()
		row.resize(t.seats)
		for si in t.seats:
			var id: int = t.guests[si]
			var gi: int = index.get(id, -1) if id != 0 else -1
			row[si] = gi
			if gi != -1:
				_ptc[_party[gi] * _tcount + ti] += 1
			if gi == -1 or locked[gi] == 0:
				_mt.append(ti)
				_ms.append(si)
		_seats.append(row)
		var flat := PackedInt32Array()
		for p in Seating.neighbours(t):
			flat.append(p.x)
			flat.append(p.y)
		_pairs.append(flat)
		_lonely_ok.append(1 if t.seats <= 2 else 0)
	_costs = PackedFloat64Array()
	_costs.resize(_tcount)
	for ti in _tcount:
		_costs[ti] = _table_cost(ti)


func _write_back() -> void:
	if not _prepared:
		return
	for ti in _tcount:
		var row: PackedInt32Array = _seats[ti]
		var t := plan.tables[ti]
		for si in row.size():
			t.guests[si] = plan.guests[row[si]].id if row[si] != -1 else 0


## A score for one table: lower is better.
func _table_cost(ti: int) -> float:
	var row: PackedInt32Array = _seats[ti]
	var n := _n
	var cost := 0.0
	var seated := 0
	var size := row.size()
	for i in size:
		var a := row[i]
		if a == -1:
			continue
		seated += 1
		var ga := _group[a]
		var base := a * n
		for j in range(i + 1, size):
			var b := row[j]
			if b == -1:
				continue
			if _avoid[base + b] == 1:
				cost += COST_APART
			var gb := _group[b]
			if ga != -1 and gb != -1:
				cost += -BONUS_SAME_GROUP if ga == gb else COST_MIXED_GROUP
	var flat: PackedInt32Array = _pairs[ti]
	for k in range(0, flat.size(), 2):
		var x := row[flat[k]]
		var y := row[flat[k + 1]]
		if x != -1 and y != -1 and _party[x] == _party[y]:
			cost -= BONUS_PARTY_NEIGHBOUR
	if seated == 1 and _lonely_ok[ti] == 0:
		cost += COST_LONELY
	return cost


func _party_cost(p: int) -> float:
	var used := 0
	var base := p * _tcount
	for ti in _tcount:
		if _ptc[base + ti] > 0:
			used += 1
	return COST_PARTY_SPLIT * maxi(0, used - 1)


## Swaps two movable seats when that lowers the score (or, while hot, sometimes when it does not).
## Returns true when the swap made the plan strictly better.
func _try(ia: int, ib: int, temp: float) -> bool:
	var tcount := _tcount
	var ta := _mt[ia]
	var sa := _ms[ia]
	var tb := _mt[ib]
	var sb := _ms[ib]
	var ga: int = _seats[ta][sa]
	var gb: int = _seats[tb][sb]
	if ga == gb:
		return false
	var same_table := ta == tb
	var pa := _party[ga] if ga != -1 else -1
	var pb := _party[gb] if gb != -1 else -1
	var before := _costs[ta] + (0.0 if same_table else _costs[tb])
	if not same_table:
		if pa != -1:
			before += _party_cost(pa)
		if pb != -1 and pb != pa:
			before += _party_cost(pb)
	_seats[ta][sa] = gb
	_seats[tb][sb] = ga
	if not same_table:
		if pa != -1:
			_ptc[pa * tcount + ta] -= 1
			_ptc[pa * tcount + tb] += 1
		if pb != -1:
			_ptc[pb * tcount + tb] -= 1
			_ptc[pb * tcount + ta] += 1
	var cost_a := _table_cost(ta)
	var cost_b := cost_a if same_table else _table_cost(tb)
	var after := cost_a + (0.0 if same_table else cost_b)
	if not same_table:
		if pa != -1:
			after += _party_cost(pa)
		if pb != -1 and pb != pa:
			after += _party_cost(pb)
	var delta := after - before
	if delta < -0.0001 or (temp > 0.0 and (delta <= 0.0 or _rng.randf() < exp(-delta / temp))):
		_costs[ta] = cost_a
		_costs[tb] = cost_b
		return delta < -0.0001
	_seats[ta][sa] = ga
	_seats[tb][sb] = gb
	if not same_table:
		if pa != -1:
			_ptc[pa * tcount + ta] += 1
			_ptc[pa * tcount + tb] -= 1
		if pb != -1:
			_ptc[pb * tcount + tb] += 1
			_ptc[pb * tcount + ta] -= 1
	return false
