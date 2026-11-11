#+build !js
package game

import "core:testing"

@(test)
starts_with_one_full_bush :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	testing.expect_value(t, g.bush_count, 1)
	testing.expect_value(t, g.bushes[0].berries, BERRY_MAX)
	testing.expect_value(t, g.jools, 0)
	testing.expect(t, is_basket(&g, PLOT_W - 1, PLOT_H - 1), "the basket is in the corner")
}

// Puts the bush master just right of the bush.
beside_bush :: proc(g: ^Game) {
	g.px, g.py = g.bushes[0].x + 1, g.bushes[0].y
}

@(test)
walking_into_the_bush_picks :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	beside_bush(&g)
	command(&g, .West)
	testing.expect_value(t, g.carried, 1)
	testing.expect_value(t, g.bushes[0].berries, BERRY_MAX - 1)
	testing.expect_value(t, g.px, g.bushes[0].x + 1) // did not walk into it
}

@(test)
hands_hold_only_carry_max :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	beside_bush(&g)
	for _ in 0 ..< BERRY_MAX + 3 {
		command(&g, .Act)
		tick(&g, REGROW_SECONDS) // keep the bush stocked
	}
	testing.expect_value(t, g.carried, CARRY_MAX)
}

@(test)
basket_pays_a_jool_a_berry :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.carried = 3
	g.px, g.py = g.basket_x - 1, g.basket_y
	command(&g, .East)
	testing.expect_value(t, g.carried, 0)
	testing.expect_value(t, g.jools, 3)
}

@(test)
bush_regrows_over_time :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.bushes[0].berries = 0
	tick(&g, REGROW_SECONDS * 0.5)
	testing.expect_value(t, g.bushes[0].berries, 0)
	for _ in 0 ..< 40 {
		tick(&g, 0.1)
	}
	testing.expect(t, g.bushes[0].berries >= 1, "a berry grew back")
	for _ in 0 ..< 400 {
		tick(&g, 0.1)
	}
	testing.expect_value(t, g.bushes[0].berries, BERRY_MAX)
}

@(test)
clicking_the_bush_walks_and_picks :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	b := g.bushes[0]
	pointer(&g, (PLOT_TX + b.x) * TILE + 5, (PLOT_TY + b.y) * TILE + 5, .Mouse)
	for _ in 0 ..< 200 {
		tick(&g, 0.05)
	}
	testing.expect_value(t, g.carried, 1)
	testing.expect(t, !g.walking, "stopped walking")
}

@(test)
clicking_the_basket_deposits :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.carried = 2
	pointer(&g, (PLOT_TX + g.basket_x) * TILE + 5, (PLOT_TY + g.basket_y) * TILE + 5, .Touch)
	for _ in 0 ..< 200 {
		tick(&g, 0.05)
	}
	testing.expect_value(t, g.jools, 2)
}

@(test)
save_round_trip :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	g.jools = 42
	g.carried = 2
	buf: [SAVE_CAP]u8
	n := save_game(&g, buf[:])
	testing.expect_value(t, n, SAVE_CAP)
	testing.expect(t, load_game(&h, buf[:n]), "loads")
	testing.expect_value(t, h.jools, 42)
	testing.expect(t, !load_game(&h, buf[:n - 1]), "a short save is refused")
}
