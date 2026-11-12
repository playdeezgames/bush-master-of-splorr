package game

// The shop: a $ in the plot's top-right corner. Walking into it opens a menu: Up and Down choose a
// row, OK (Space) buys it or leaves, Cancel (Esc) leaves. It sells bigger hands (carry one more
// berry), more energy (every day), stamina (a slower idle drain), a better price per berry and a new bush, each dearer with every one bought, and takes mortgage payments (Left and
// Right choose how much; home.odin).

// Tuning. Prices are Claude's placeholders, for the user to change.
HANDS_PRICE_START :: 10 // jools for the first hand upgrade
HANDS_PRICE_GROWTH_NUM :: 3 // each one after costs 3/2 of the last (rounded up)
HANDS_PRICE_GROWTH_DEN :: 2
HANDS_MAX_LEVEL :: 30
ENERGY_UPGRADE :: 20 // energy added to every day per upgrade
ENERGY_PRICE_START :: 30 // jools for the first energy upgrade
ENERGY_PRICE_GROWTH_NUM :: 6 // each one after costs 6/5 of the last (rounded up)
ENERGY_PRICE_GROWTH_DEN :: 5
ENERGY_MAX_LEVEL :: 60
STAMINA_PRICE_START :: 40 // jools for the first slower idle drain (the user, November 12, 2026)
STAMINA_PRICE_GROWTH_NUM :: 3 // each one after costs 3/2 of the last (rounded up)
STAMINA_PRICE_GROWTH_DEN :: 2
STAMINA_MAX_LEVEL :: 20 // home.odin: each adds IDLE_DRAIN_STEP seconds
PRICE_PRICE_START :: 250 // jools for the first +1 jool a berry (the dearest upgrade, the user's ask)
PRICE_PRICE_GROWTH :: 2 // each one after costs twice the last
PRICE_MAX_LEVEL :: 20
BUSH_PRICE_START :: 50 // jools for the first extra bush
BUSH_PRICE_GROWTH :: 2 // each one after costs twice the last

// Where bought bushes go, in order (plot tiles). Spaced so a path always goes round them and the
// basket corner stays clear. The first is the bush the plot starts with.
BUSH_SPOTS := [?][2]int{{3, 2}, {6, 2}, {9, 2}, {3, 5}, {6, 5}, {9, 5}, {12, 2}, {12, 5}}

Shop_Item :: enum {
	Hands,
	Energy,
	Stamina,
	Price,
	Bush,
}

// The menu's rows: the items, Pay mortgage, then Leave.
PAY_ROW :: len(Shop_Item)
LEAVE_ROW :: PAY_ROW + 1
SHOP_ROWS :: LEAVE_ROW + 1

carry_max :: proc(g: ^Game) -> int {
	return CARRY_START + g.hands_level
}

// Jools a berry dropped in the basket earns.
berry_price :: proc(g: ^Game) -> int {
	return JOOLS_PER_BERRY + g.price_level
}

// The price of the next one of `item`, and whether there is a next one.
price :: proc(g: ^Game, item: Shop_Item) -> (int, bool) {
	switch item {
	case .Hands:
		if g.hands_level >= HANDS_MAX_LEVEL {
			return 0, false
		}
		p := HANDS_PRICE_START
		for _ in 0 ..< g.hands_level {
			p = (p * HANDS_PRICE_GROWTH_NUM + HANDS_PRICE_GROWTH_DEN - 1) / HANDS_PRICE_GROWTH_DEN
		}
		return p, true
	case .Energy:
		if g.energy_level >= ENERGY_MAX_LEVEL {
			return 0, false
		}
		p := ENERGY_PRICE_START
		for _ in 0 ..< g.energy_level {
			p = (p * ENERGY_PRICE_GROWTH_NUM + ENERGY_PRICE_GROWTH_DEN - 1) / ENERGY_PRICE_GROWTH_DEN
		}
		return p, true
	case .Stamina:
		if g.stamina_level >= STAMINA_MAX_LEVEL {
			return 0, false
		}
		p := STAMINA_PRICE_START
		for _ in 0 ..< g.stamina_level {
			p = (p * STAMINA_PRICE_GROWTH_NUM + STAMINA_PRICE_GROWTH_DEN - 1) / STAMINA_PRICE_GROWTH_DEN
		}
		return p, true
	case .Price:
		if g.price_level >= PRICE_MAX_LEVEL {
			return 0, false
		}
		p := PRICE_PRICE_START
		for _ in 0 ..< g.price_level {
			p *= PRICE_PRICE_GROWTH
		}
		return p, true
	case .Bush:
		if g.bush_count >= len(BUSH_SPOTS) {
			return 0, false
		}
		p := BUSH_PRICE_START
		for _ in 1 ..< g.bush_count {
			p *= BUSH_PRICE_GROWTH
		}
		return p, true
	}
	return 0, false
}

// The next free bush spot, skipping one the bush master stands on.
free_bush_spot :: proc(g: ^Game) -> (int, int, bool) {
	for s in BUSH_SPOTS {
		if bush_at(g, s.x, s.y) == nil && !(g.px == s.x && g.py == s.y) && !is_basket(g, s.x, s.y) && !is_shop(g, s.x, s.y) && !is_bed(g, s.x, s.y) {
			return s.x, s.y, true
		}
	}
	return 0, 0, false
}

deny_row :: proc(g: ^Game, item: Shop_Item) {
	g.deny = 1 + int(item)
	g.deny_timer = 0.5
}

buy :: proc(g: ^Game, item: Shop_Item) -> bool {
	cost, ok := price(g, item)
	if !ok || g.jools < cost {
		deny_row(g, item)
		return false
	}
	switch item {
	case .Hands:
		g.hands_level += 1
	case .Energy:
		g.energy_level += 1
		g.energy += ENERGY_UPGRADE // today gets the extra too
	case .Stamina:
		g.stamina_level += 1
	case .Price:
		g.price_level += 1
	case .Bush:
		x, y, free := free_bush_spot(g)
		if !free || g.bush_count >= BUSH_CAP {
			deny_row(g, item)
			return false
		}
		g.bushes[g.bush_count] = {x = x, y = y} // planted bare; it grows its berries
		g.bush_count += 1
		add_pop(g, .New_Bush, 0, x, y)
	}
	g.jools -= cost
	return true
}

open_shop :: proc(g: ^Game) {
	g.menu_open = true
	g.menu_row = 0
	g.deny = 0
}

shop_command :: proc(g: ^Game, c: Command) {
	switch c {
	case .North:
		g.menu_row = (g.menu_row + SHOP_ROWS - 1) % SHOP_ROWS
	case .South:
		g.menu_row = (g.menu_row + 1) % SHOP_ROWS
	case .West:
		if g.menu_row == PAY_ROW {
			g.pay_step = (g.pay_step + len(PAY_STEPS) - 1) % len(PAY_STEPS)
		}
	case .East:
		if g.menu_row == PAY_ROW {
			g.pay_step = (g.pay_step + 1) % len(PAY_STEPS)
		}
	case .Act:
		switch g.menu_row {
		case LEAVE_ROW:
			g.menu_open = false
		case PAY_ROW:
			pay_mortgage(g)
		case:
			buy(g, Shop_Item(g.menu_row))
		}
	case .Cancel:
		g.menu_open = false
	}
}
