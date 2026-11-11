package game

// The rules: a fenced plot with one berry bush and a basket in the corner. The bush master picks
// berries (walk into the bush), carries them to the basket (walk into it) and gets a jool for every
// berry dropped in. Bushes grow their berries back over time. Real time: `tick` gets seconds.
// No core:os, no core:fmt; `itoa` makes numbers into text.

// Tuning.
BERRY_MAX :: 5 // berries a bush holds when full
REGROW_SECONDS :: 3.0 // seconds for a bush to grow one berry back
CARRY_MAX :: 5 // berries the bush master can hold at once
STEP_SECONDS :: 0.12 // seconds per tile when walking to a clicked spot
POP_SECONDS :: 0.8 // how long a "+1" floats

// The plot, in tiles inside the fence.
PLOT_W :: 14
PLOT_H :: 9
// Screen tile of the plot's top-left inside corner (the fence is one tile around it).
PLOT_TX :: 9
PLOT_TY :: 5

BUSH_CAP :: 16
POP_CAP :: 8

SAVE_VERSION :: 1

Command :: enum {
	North,
	South,
	West,
	East,
	Act, // pick from a bush or empty yer hands into the basket, whichever is next to you
}

Pointer :: enum {
	Mouse,
	Right_Mouse,
	Touch,
}

Bush :: struct {
	x, y:    int,
	berries: int,
	regrow:  f64, // seconds grown toward the next berry
}

Pop_Kind :: enum {
	Berry, // picked one
	Jools, // dropped berries in the basket
	Full, // hands full
}

Pop :: struct {
	kind:   Pop_Kind,
	amount: int,
	x, y:   int, // plot tile it rises from
	age:    f64, // seconds; a pop is gone once age >= POP_SECONDS
	live:   bool,
}

Game :: struct {
	version:            int,
	px, py:             int, // the bush master, in plot tiles
	carried:            int,
	jools:              int,
	picked:             int, // berries picked, ever
	bushes:             [BUSH_CAP]Bush,
	bush_count:         int,
	basket_x, basket_y: int,
	// A clicked spot to walk to; with `aim` set, act on what is there once beside it.
	walking:            bool,
	aim:                bool,
	tx, ty:             int,
	step_timer:         f64,
	pops:               [POP_CAP]Pop,
}

init_game :: proc(g: ^Game) {
	g^ = {}
	g.version = SAVE_VERSION
	g.basket_x, g.basket_y = PLOT_W - 1, PLOT_H - 1
	g.bushes[0] = {x = 3, y = 2, berries = BERRY_MAX}
	g.bush_count = 1
	g.px, g.py = PLOT_W / 2, PLOT_H / 2
}

in_plot :: proc(x, y: int) -> bool {
	return x >= 0 && y >= 0 && x < PLOT_W && y < PLOT_H
}

bush_at :: proc(g: ^Game, x, y: int) -> ^Bush {
	for i in 0 ..< g.bush_count {
		b := &g.bushes[i]
		if b.x == x && b.y == y {
			return b
		}
	}
	return nil
}

is_basket :: proc(g: ^Game, x, y: int) -> bool {
	return x == g.basket_x && y == g.basket_y
}

blocked :: proc(g: ^Game, x, y: int) -> bool {
	return !in_plot(x, y) || bush_at(g, x, y) != nil || is_basket(g, x, y)
}

add_pop :: proc(g: ^Game, kind: Pop_Kind, amount, x, y: int) {
	slot := 0
	oldest := -1.0
	for p, i in g.pops {
		if !p.live {
			slot = i
			break
		}
		if p.age > oldest {
			oldest = p.age
			slot = i
		}
	}
	g.pops[slot] = {
		kind   = kind,
		amount = amount,
		x      = x,
		y      = y,
		live   = true,
	}
}

// Picks one berry off `b`, if there is one and room in yer hands.
pick :: proc(g: ^Game, b: ^Bush) {
	if g.carried >= CARRY_MAX {
		add_pop(g, .Full, 0, g.px, g.py)
		return
	}
	if b.berries <= 0 {
		return
	}
	if b.berries == BERRY_MAX {
		b.regrow = 0 // the clock starts when the first berry goes
	}
	b.berries -= 1
	g.carried += 1
	g.picked += 1
	add_pop(g, .Berry, 1, b.x, b.y)
}

// Drops everything carried into the basket: a jool a berry.
deposit :: proc(g: ^Game) {
	if g.carried <= 0 {
		return
	}
	g.jools += g.carried
	add_pop(g, .Jools, g.carried, g.basket_x, g.basket_y)
	g.carried = 0
}

// Acts on the tile (x, y) beside the bush master: pick if a bush, deposit if the basket.
act_on :: proc(g: ^Game, x, y: int) -> bool {
	if b := bush_at(g, x, y); b != nil {
		pick(g, b)
		return true
	}
	if is_basket(g, x, y) {
		deposit(g)
		return true
	}
	return false
}

// One step; walking into a bush picks, walking into the basket deposits.
move :: proc(g: ^Game, dx, dy: int) {
	nx, ny := g.px + dx, g.py + dy
	if act_on(g, nx, ny) {
		return
	}
	if !blocked(g, nx, ny) {
		g.px, g.py = nx, ny
	}
}

DIRS := [4][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}

command :: proc(g: ^Game, c: Command) {
	g.walking = false
	switch c {
	case .North, .South, .West, .East:
		d := DIRS[int(c)]
		move(g, d.x, d.y)
	case .Act:
		// The basket first when carrying (that is where berries go), otherwise a bush.
		if g.carried > 0 {
			for d in DIRS {
				if is_basket(g, g.px + d.x, g.py + d.y) {
					deposit(g)
					return
				}
			}
		}
		for d in DIRS {
			if b := bush_at(g, g.px + d.x, g.py + d.y); b != nil {
				pick(g, b)
				return
			}
		}
		for d in DIRS {
			if is_basket(g, g.px + d.x, g.py + d.y) {
				deposit(g)
				return
			}
		}
	}
}

// A click or tap at framebuffer pixel (x, y): walk there, and act on a bush or the basket.
pointer :: proc(g: ^Game, x, y: int, kind: Pointer) {
	_ = kind
	tx := x / TILE - PLOT_TX
	ty := y / TILE - PLOT_TY
	if x < 0 || y < 0 || !in_plot(tx, ty) {
		return
	}
	g.tx, g.ty = tx, ty
	g.aim = blocked(g, tx, ty)
	g.walking = true
	g.step_timer = STEP_SECONDS // the first step goes at once
}

// Distance field from the target over open tiles (the target itself counts as open), so each step
// can go to the neighbour one closer. -1 is unreachable.
distances :: proc(g: ^Game, out: ^[PLOT_W * PLOT_H]int) {
	for &d in out {
		d = -1
	}
	queue: [PLOT_W * PLOT_H]int
	head, tail := 0, 0
	out[g.ty * PLOT_W + g.tx] = 0
	queue[tail] = g.ty * PLOT_W + g.tx
	tail += 1
	for head < tail {
		cur := queue[head]
		head += 1
		cx, cy := cur % PLOT_W, cur / PLOT_W
		for d in DIRS {
			nx, ny := cx + d.x, cy + d.y
			if !in_plot(nx, ny) || out[ny * PLOT_W + nx] >= 0 {
				continue
			}
			if blocked(g, nx, ny) && !(nx == g.px && ny == g.py) {
				continue
			}
			out[ny * PLOT_W + nx] = out[cur] + 1
			queue[tail] = ny * PLOT_W + nx
			tail += 1
		}
	}
}

walk_step :: proc(g: ^Game) {
	if g.px == g.tx && g.py == g.ty {
		g.walking = false
		return
	}
	dist: [PLOT_W * PLOT_H]int
	distances(g, &dist)
	here := dist[g.py * PLOT_W + g.px]
	if here < 0 {
		g.walking = false
		return
	}
	for d in DIRS {
		nx, ny := g.px + d.x, g.py + d.y
		if !in_plot(nx, ny) {
			continue
		}
		v := dist[ny * PLOT_W + nx]
		if v >= 0 && v < here {
			if nx == g.tx && ny == g.ty && g.aim {
				act_on(g, nx, ny)
				g.walking = false
			} else {
				g.px, g.py = nx, ny
			}
			return
		}
	}
	g.walking = false
}

// Advances real time by `dt` seconds. True when something on screen changed.
tick :: proc(g: ^Game, seconds: f64) -> bool {
	dt := clamp(seconds, 0, 0.25)
	changed := false
	for i in 0 ..< g.bush_count {
		b := &g.bushes[i]
		if b.berries >= BERRY_MAX {
			b.regrow = 0
			continue
		}
		b.regrow += dt
		if b.regrow >= REGROW_SECONDS {
			b.regrow -= REGROW_SECONDS
			b.berries += 1
			changed = true
		}
	}
	for &p in g.pops {
		if p.live {
			p.age += dt
			if p.age >= POP_SECONDS {
				p.live = false
			}
			changed = true
		}
	}
	if g.walking {
		g.step_timer += dt
		for g.walking && g.step_timer >= STEP_SECONDS {
			g.step_timer -= STEP_SECONDS
			walk_step(g)
			changed = true
		}
	}
	return changed
}

// Writes n in decimal into buf and returns it as a string.
itoa :: proc(buf: []u8, n: int) -> string {
	if len(buf) == 0 {
		return ""
	}
	v := n
	neg := v < 0
	if neg {
		v = -v
	}
	i := len(buf)
	for {
		i -= 1
		buf[i] = u8('0' + v % 10)
		v /= 10
		if v == 0 || i == 0 {
			break
		}
	}
	if neg && i > 0 {
		i -= 1
		buf[i] = '-'
	}
	return string(buf[i:])
}

// Saves are the Game's bytes; a save of another size or version is not read.
SAVE_CAP :: size_of(Game)

save_game :: proc(g: ^Game, out: []u8) -> int {
	if len(out) < size_of(Game) {
		return 0
	}
	src := ([^]u8)(g)[:size_of(Game)]
	return copy(out, src)
}

load_game :: proc(g: ^Game, data: []u8) -> bool {
	if len(data) != size_of(Game) {
		return false
	}
	tmp: Game
	copy(([^]u8)(&tmp)[:size_of(Game)], data)
	if tmp.version != SAVE_VERSION || tmp.bush_count < 1 || tmp.bush_count > BUSH_CAP {
		return false
	}
	g^ = tmp
	return true
}
