package game

// The rules: a fenced plot with one berry bush and a basket in the corner. The bush master picks
// berries (walk into the bush), carries them to the basket (walk into it) and gets jools for every
// berry dropped in. Bushes grow their berries back over time. Real time: `tick` gets seconds.
// The shop (shop.odin) is a $ in the top-right corner: walk into it for a menu of bigger hands, more
// energy, stamina, a better price, more bushes and paying the mortgage. Energy, the bed and the mortgage are in home.odin.
// Controls are only the four directions, OK (Space) and Cancel (Esc).
// No core:os, no core:fmt; `itoa` makes numbers into text.

// Tuning.
BERRY_MAX :: 5 // berries a bush holds when full
REGROW_SECONDS :: 3.0 // seconds for a bush to grow one berry back
JOOLS_PER_BERRY :: 1 // before any "Better price" upgrade (shop.odin)
CARRY_START :: 5 // berries the bush master can hold at first (the shop adds more)
POP_SECONDS :: 0.8 // how long a "+1" floats

// The plot, in tiles inside the fence.
PLOT_W :: 14
PLOT_H :: 9
// Screen tile of the plot's top-left inside corner (the fence is one tile around it).
PLOT_TX :: 9
PLOT_TY :: 5

BUSH_CAP :: 16
POP_CAP :: 8

SAVE_VERSION :: 6 // older saves still load: see load_game

Command :: enum {
	North,
	South,
	West,
	East,
	Act, // OK: pick, deposit or open the shop beside you; in the shop menu, choose the row
	Cancel, // leave the shop menu; on the plot, ask to start over
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
	Tired, // not enough energy
	New_Bush, // a bush just planted
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
	// Click-to-walk, removed November 11, 2026; kept so older saves keep their layout.
	unused_walk:        [2]bool,
	unused_target:      [2]int,
	unused_timer:       f64,
	pops:               [POP_CAP]Pop,
	// Added with the shop (version 2). New fields go at the end so older saves are a prefix.
	hands_level:        int, // hand upgrades bought
	deny:               int, // shop row flashing "not enough jools" (0 none, 1 + Shop_Row)
	deny_timer:         f64,
	// Added with the shop menu (version 3).
	shop_x, shop_y:     int, // the $ tile
	menu_open:          bool,
	menu_row:           int,
	// Added with energy, the bed and the mortgage (version 4).
	bed_x, bed_y:       int,
	energy:             int,
	day:                int,
	mortgage:           i64, // jools owed
	last_interest:      i64, // charged last night, for the morning notice
	pay_step:           int, // index into PAY_STEPS
	notice:             Notice,
	// Added with the energy upgrade and the idle drain (version 5).
	energy_level:       int, // energy upgrades bought
	idle_timer:         f64, // seconds stood still toward the next point of drain
	// Added with the better price per berry and stamina (version 6).
	price_level:        int, // price upgrades bought: each is +1 jool a berry
	stamina_level:      int, // stamina upgrades bought: each slows the idle drain
}

init_game :: proc(g: ^Game) {
	g^ = {}
	g.version = SAVE_VERSION
	g.basket_x, g.basket_y = PLOT_W - 1, PLOT_H - 1
	g.shop_x, g.shop_y = PLOT_W - 1, 0
	start_home(g)
	g.bushes[0] = {x = 3, y = 2, berries = BERRY_MAX}
	g.bush_count = 1
	g.px, g.py = PLOT_W / 2, PLOT_H / 2
}

// The version 4 fields' starting values (also given to older saves).
start_home :: proc(g: ^Game) {
	g.bed_x, g.bed_y = 0, PLOT_H - 1
	g.energy = ENERGY_START
	g.day = 1
	g.mortgage = MORTGAGE_START
	g.pay_step = len(PAY_STEPS) - 1 // "all"
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

is_shop :: proc(g: ^Game, x, y: int) -> bool {
	return x == g.shop_x && y == g.shop_y
}

blocked :: proc(g: ^Game, x, y: int) -> bool {
	return !in_plot(x, y) || bush_at(g, x, y) != nil || is_basket(g, x, y) || is_shop(g, x, y) || is_bed(g, x, y)
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
	if g.carried >= carry_max(g) {
		add_pop(g, .Full, 0, g.px, g.py)
		return
	}
	if b.berries <= 0 {
		return
	}
	if !spend_energy(g, PICK_ENERGY) {
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

// Drops everything carried into the basket: the berry price each (shop.odin).
deposit :: proc(g: ^Game) {
	if g.carried <= 0 {
		return
	}
	if !spend_energy(g, DEPOSIT_ENERGY) {
		return
	}
	pay := g.carried * berry_price(g)
	g.jools += pay
	add_pop(g, .Jools, pay, g.basket_x, g.basket_y)
	g.carried = 0
}

// Acts on the tile (x, y) beside the bush master: pick from a bush, deposit at the basket, open
// the shop.
act_on :: proc(g: ^Game, x, y: int) -> bool {
	if b := bush_at(g, x, y); b != nil {
		pick(g, b)
		return true
	}
	if is_basket(g, x, y) {
		deposit(g)
		return true
	}
	if is_shop(g, x, y) {
		open_shop(g)
		return true
	}
	if is_bed(g, x, y) {
		sleep(g)
		return true
	}
	return false
}

// One step; walking into a bush picks, into the basket deposits, into the $ opens the shop.
move :: proc(g: ^Game, dx, dy: int) {
	nx, ny := g.px + dx, g.py + dy
	if act_on(g, nx, ny) {
		return
	}
	if !blocked(g, nx, ny) {
		g.px, g.py = nx, ny
		g.idle_timer = 0
	}
}

DIRS := [4][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}

command :: proc(g: ^Game, c: Command) {
	if g.notice != .None {
		notice_command(g, c)
		return
	}
	if g.menu_open {
		shop_command(g, c)
		return
	}
	switch c {
	case .North, .South, .West, .East:
		d := DIRS[int(c)]
		move(g, d.x, d.y)
	case .Cancel:
		ask_reset(g)
	case .Act:
		// The basket first when carrying (that is where berries go), then a bush, then the shop.
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
			if act_on(g, g.px + d.x, g.py + d.y) {
				return
			}
		}
	}
}

// Advances real time by `seconds`. True when something on screen changed. Bushes keep growing
// while the shop menu is open.
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
	if idle_drain(g, dt) {
		changed = true
	}
	if g.deny != 0 {
		g.deny_timer -= dt
		if g.deny_timer <= 0 {
			g.deny = 0
		}
		changed = true
	}
	return changed
}

// Writes n in decimal into buf and returns it as a string.
itoa :: proc(buf: []u8, n: int) -> string {
	return itoa64(buf, i64(n))
}

itoa64 :: proc(buf: []u8, n: i64) -> string {
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

// Saves are the Game's bytes; a save of another size or version is not read. Fields are only ever
// added at the end of Game, so an older save is a prefix: version 1 (before the shop) ends at
// `hands_level`, version 2 (the shop panel) at `shop_x`, version 3 (the shop menu) at `bed_x`, version 4 (the mortgage)
// at `energy_level`, version 5 (the energy upgrade) at `price_level`. They load with the new fields defaulted.
SAVE_CAP :: size_of(Game)
SAVE_V1_SIZE :: int(offset_of(Game, hands_level))
SAVE_V2_SIZE :: int(offset_of(Game, shop_x))
SAVE_V3_SIZE :: int(offset_of(Game, bed_x))
SAVE_V4_SIZE :: int(offset_of(Game, energy_level))
SAVE_V5_SIZE :: int(offset_of(Game, price_level))

save_game :: proc(g: ^Game, out: []u8) -> int {
	if len(out) < size_of(Game) {
		return 0
	}
	src := ([^]u8)(g)[:size_of(Game)]
	return copy(out, src)
}

load_game :: proc(g: ^Game, data: []u8) -> bool {
	want: int
	switch len(data) {
	case size_of(Game):
		want = SAVE_VERSION
	case SAVE_V5_SIZE:
		want = 5
	case SAVE_V4_SIZE:
		want = 4
	case SAVE_V3_SIZE:
		want = 3
	case SAVE_V2_SIZE:
		want = 2
	case SAVE_V1_SIZE:
		want = 1
	case:
		return false
	}
	tmp: Game
	copy(([^]u8)(&tmp)[:size_of(Game)], data)
	if tmp.version != want || tmp.bush_count < 1 || tmp.bush_count > BUSH_CAP {
		return false
	}
	if want < 3 {
		tmp.shop_x, tmp.shop_y = PLOT_W - 1, 0
	}
	if want < 4 {
		start_home(&tmp)
	}
	tmp.version = SAVE_VERSION
	tmp.unused_walk = {}
	tmp.menu_open = false
	tmp.deny = 0
	if tmp.notice > max(Notice) || tmp.notice < min(Notice) || tmp.notice == .Confirm_Reset {
		tmp.notice = .None
	}
	g^ = tmp
	return true
}
