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
	// Every bush is reachable: the basket can still be walked to from the start.
	g.carried = 1
	pointer(&g, (PLOT_TX + g.basket_x) * TILE + 1, (PLOT_TY + g.basket_y) * TILE + 1, .Mouse)
	for _ in 0 ..< 300 {
		tick(&g, 0.05)
	}
	testing.expect_value(t, g.carried, 0)
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
	testing.expect_value(t, h.version, SAVE_VERSION)
	testing.expect_value(t, h.hands_level, 0)
}

@(test)
clicking_a_shop_row_buys :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 100
	pointer(&g, SHOP_X + 10, SHOP_ROW_Y + SHOP_ROW_H + 5, .Mouse)
	testing.expect_value(t, g.bush_count, 2)
}
