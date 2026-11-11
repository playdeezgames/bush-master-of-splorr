#+build !js
package game

import "core:testing"

@(test)
hands_cost_more_each_time :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 1000
	first, _ := price(&g, .Hands)
	testing.expect_value(t, first, HANDS_PRICE_START)
	testing.expect(t, buy(&g, .Hands), "bought")
	testing.expect_value(t, carry_max(&g), CARRY_START + 1)
	testing.expect_value(t, g.jools, 1000 - first)
	second, _ := price(&g, .Hands)
	testing.expect(t, second > first, "dearer")
}

@(test)
cannot_buy_without_jools :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = HANDS_PRICE_START - 1
	testing.expect(t, !buy(&g, .Hands), "refused")
	testing.expect_value(t, g.jools, HANDS_PRICE_START - 1)
	testing.expect_value(t, g.hands_level, 0)
	testing.expect_value(t, g.deny, 1 + int(Shop_Item.Hands))
}

@(test)
bushes_fill_the_spots_then_stop :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 1_000_000
	last := 0
	for _ in 1 ..< len(BUSH_SPOTS) {
		cost, ok := price(&g, .Bush)
		testing.expect(t, ok && cost > last, "dearer each time")
		last = cost
		testing.expect(t, buy(&g, .Bush), "planted")
	}
	testing.expect_value(t, g.bush_count, len(BUSH_SPOTS))
	_, ok := price(&g, .Bush)
	testing.expect(t, !ok, "plot full")
	testing.expect(t, !buy(&g, .Bush), "no more")
	// With every bush planted, the basket and the shop can still be reached from the start.
	testing.expect(t, reachable_beside(&g, g.basket_x, g.basket_y), "basket reachable")
	testing.expect(t, reachable_beside(&g, g.shop_x, g.shop_y), "shop reachable")
}

@(test)
new_bush_skips_the_bush_master :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 1000
	g.px, g.py = BUSH_SPOTS[1].x, BUSH_SPOTS[1].y
	testing.expect(t, buy(&g, .Bush), "planted")
	b := g.bushes[1]
	testing.expect(t, !(b.x == g.px && b.y == g.py), "not on the bush master")
	testing.expect_value(t, b.berries, 0)
}

@(test)
version_1_save_loads :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	g.version = 1
	g.jools = 9
	buf: [SAVE_CAP]u8
	save_game(&g, buf[:])
	testing.expect(t, load_game(&h, buf[:SAVE_V1_SIZE]), "old save loads")
	testing.expect_value(t, h.jools, 9)
	testing.expect(t, is_shop(&h, PLOT_W - 1, 0), "the shop is placed")
	testing.expect_value(t, h.version, SAVE_VERSION)
	testing.expect_value(t, h.hands_level, 0)
}

// True when an open tile next to (tx, ty) can be walked to from the bush master.
reachable_beside :: proc(g: ^Game, tx, ty: int) -> bool {
	seen: [PLOT_W * PLOT_H]bool
	queue: [PLOT_W * PLOT_H][2]int
	head, tail := 0, 1
	queue[0] = {g.px, g.py}
	seen[g.py * PLOT_W + g.px] = true
	for head < tail {
		c := queue[head]
		head += 1
		if abs(c.x - tx) + abs(c.y - ty) == 1 {
			return true
		}
		for d in DIRS {
			n := [2]int{c.x + d.x, c.y + d.y}
			if blocked(g, n.x, n.y) || seen[n.y * PLOT_W + n.x] {
				continue
			}
			seen[n.y * PLOT_W + n.x] = true
			queue[tail] = n
			tail += 1
		}
	}
	return false
}

@(test)
walking_into_the_shop_opens_the_menu :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.px, g.py = g.shop_x - 1, g.shop_y
	command(&g, .East)
	testing.expect(t, g.menu_open, "menu open")
	testing.expect_value(t, g.px, g.shop_x - 1) // did not walk onto it
	// Directions move the cursor, not the bush master.
	command(&g, .South)
	testing.expect_value(t, g.menu_row, 1)
	command(&g, .West)
	testing.expect_value(t, g.px, g.shop_x - 1)
	command(&g, .Cancel)
	testing.expect(t, !g.menu_open, "Esc leaves")
}

@(test)
menu_buys_with_ok_and_leaves :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 60
	open_shop(&g)
	command(&g, .Act) // row 0: hands
	testing.expect_value(t, g.hands_level, 1)
	testing.expect(t, g.menu_open, "stays open after buying")
	command(&g, .South)
	command(&g, .Act) // row 1: a bush for 50, but only 50 left
	testing.expect_value(t, g.bush_count, 2)
	command(&g, .Act) // the next bush costs 100: refused
	testing.expect_value(t, g.bush_count, 2)
	testing.expect_value(t, g.deny, 1 + int(Shop_Item.Bush))
	command(&g, .North)
	command(&g, .North) // wraps round to Leave
	testing.expect_value(t, g.menu_row, LEAVE_ROW)
	command(&g, .Act)
	testing.expect(t, !g.menu_open, "Leave closes it")
}

@(test)
version_2_save_loads :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	g.version = 2
	g.jools = 33
	g.hands_level = 2
	buf: [SAVE_CAP]u8
	save_game(&g, buf[:])
	testing.expect(t, load_game(&h, buf[:SAVE_V2_SIZE]), "v2 save loads")
	testing.expect_value(t, h.hands_level, 2)
	testing.expect_value(t, h.shop_x, PLOT_W - 1)
	testing.expect_value(t, h.shop_y, 0)
}
