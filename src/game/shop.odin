package game

// The shop: a $ in the plot's top-right corner. Walking into it opens a menu: Up and Down choose a
// row, OK (Space) buys it or leaves, Cancel (Esc) leaves. It sells bigger hands (carry one more
// berry) and a new bush; both get dearer with every one bought.

// Tuning. Prices are Claude's placeholders, for the user to change.
HANDS_PRICE_START :: 10 // jools for the first hand upgrade
HANDS_PRICE_GROWTH_NUM :: 3 // each one after costs 3/2 of the last (rounded up)
HANDS_PRICE_GROWTH_DEN :: 2
HANDS_MAX_LEVEL :: 30
BUSH_PRICE_START :: 50 // jools for the first extra bush
BUSH_PRICE_GROWTH :: 2 // each one after costs twice the last

// Where bought bushes go, in order (plot tiles). Spaced so a path always goes round them and the
// basket corner stays clear. The first is the bush the plot starts with.
BUSH_SPOTS := [?][2]int{{3, 2}, {6, 2}, {9, 2}, {3, 5}, {6, 5}, {9, 5}, {12, 2}, {12, 5}}

Shop_Item :: enum {
	Hands,
	Bush,
}

// The menu's rows: the items, then Leave.
SHOP_ROWS :: len(Shop_Item) + 1
LEAVE_ROW :: len(Shop_Item)

carry_max :: proc(g: ^Game) -> int {
	return CARRY_START + g.hands_level
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
		if bush_at(g, s.x, s.y) == nil && !(g.px == s.x && g.py == s.y) && !is_basket(g, s.x, s.y) && !is_shop(g, s.x, s.y) {
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
	case .West, .East:
	case .Act:
		if g.menu_row == LEAVE_ROW {
			g.menu_open = false
		} else {
			buy(g, Shop_Item(g.menu_row))
		}
	case .Cancel:
		g.menu_open = false
	}
}
