#+build !js
package game

import "core:testing"

@(test)
picking_and_selling_cost_energy :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.px, g.py = g.bushes[0].x + 1, g.bushes[0].y
	command(&g, .West)
	testing.expect_value(t, g.energy, ENERGY_START - PICK_ENERGY)
	g.px, g.py = g.basket_x - 1, g.basket_y
	command(&g, .East)
	testing.expect_value(t, g.energy, ENERGY_START - PICK_ENERGY - DEPOSIT_ENERGY)
	testing.expect_value(t, g.jools, 1)
}

@(test)
too_tired_to_pick_or_sell :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.energy = 0
	g.px, g.py = g.bushes[0].x + 1, g.bushes[0].y
	command(&g, .West)
	testing.expect_value(t, g.carried, 0)
	testing.expect_value(t, g.bushes[0].berries, BERRY_MAX)
	g.carried = 3
	g.px, g.py = g.basket_x - 1, g.basket_y
	command(&g, .East)
	testing.expect_value(t, g.carried, 3)
	testing.expect_value(t, g.jools, 0)
	// Still free to walk.
	command(&g, .North)
	testing.expect_value(t, g.py, g.basket_y - 1)
}

@(test)
sleeping_ends_the_day :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.energy = 0
	g.bushes[0].berries = 0
	g.px, g.py = g.bed_x + 1, g.bed_y
	command(&g, .West)
	testing.expect_value(t, g.day, 2)
	testing.expect_value(t, g.energy, ENERGY_START)
	testing.expect_value(t, g.bushes[0].berries, BERRY_MAX)
	testing.expect_value(t, g.notice, Notice.Morning)
	testing.expect_value(t, g.px, g.bed_x + 1) // did not walk onto the bed
	// 10% a year over 365 nights on 1,000,000: 273.97..., rounded up to 274.
	testing.expect_value(t, g.last_interest, i64(274))
	testing.expect_value(t, g.mortgage, MORTGAGE_START + 274)
	// The notice takes OK; directions do nothing meanwhile.
	command(&g, .North)
	testing.expect_value(t, g.notice, Notice.Morning)
	command(&g, .Act)
	testing.expect_value(t, g.notice, Notice.None)
}

@(test)
interest_compounds :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	for _ in 0 ..< NIGHTS_PER_YEAR {
		sleep(&g)
	}
	// A year of nightly compounding at 10% is a little over 10.5%.
	testing.expect(t, g.mortgage > 1_105_000 && g.mortgage < 1_106_000, "about 10.5% in a year")
}

open_pay_row :: proc(g: ^Game) {
	open_shop(g)
	g.menu_row = PAY_ROW
}

@(test)
paying_the_mortgage :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 250
	open_pay_row(&g)
	g.pay_step = 1 // 100
	command(&g, .Act)
	testing.expect_value(t, g.jools, 150)
	testing.expect_value(t, g.mortgage, MORTGAGE_START - 100)
	command(&g, .East) // 1,000: more than on hand
	command(&g, .Act)
	testing.expect_value(t, g.jools, 150)
	testing.expect_value(t, g.deny, 1 + PAY_ROW)
	command(&g, .West)
	command(&g, .West) // 10
	command(&g, .Act)
	testing.expect_value(t, g.jools, 140)
	g.pay_step = len(PAY_STEPS) - 1 // all
	command(&g, .Act)
	testing.expect_value(t, g.jools, 0)
	testing.expect_value(t, g.mortgage, MORTGAGE_START - 250)
	testing.expect(t, g.menu_open, "still shopping")
}

@(test)
paying_it_off_wins :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.mortgage = 40
	g.jools = 100
	open_pay_row(&g)
	g.pay_step = len(PAY_STEPS) - 1
	command(&g, .Act)
	testing.expect_value(t, g.mortgage, i64(0))
	testing.expect_value(t, g.jools, 60) // only what was owed
	testing.expect_value(t, g.notice, Notice.Paid_Off)
	testing.expect(t, !g.menu_open, "menu closed for the notice")
	command(&g, .Act)
	testing.expect_value(t, g.notice, Notice.None)
	sleep(&g)
	testing.expect_value(t, g.last_interest, i64(0))
	testing.expect_value(t, g.mortgage, i64(0))
}

@(test)
version_3_save_loads :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	g.version = 3
	g.jools = 12
	buf: [SAVE_CAP]u8
	save_game(&g, buf[:])
	testing.expect(t, load_game(&h, buf[:SAVE_V3_SIZE]), "v3 save loads")
	testing.expect_value(t, h.jools, 12)
	testing.expect_value(t, h.energy, ENERGY_START)
	testing.expect_value(t, h.day, 1)
	testing.expect_value(t, h.mortgage, MORTGAGE_START)
}

@(test)
energy_upgrade_raises_every_day :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 1000
	g.energy = 40
	first, _ := price(&g, .Energy)
	testing.expect_value(t, first, ENERGY_PRICE_START)
	testing.expect(t, buy(&g, .Energy), "bought")
	testing.expect_value(t, energy_max(&g), ENERGY_START + ENERGY_UPGRADE)
	testing.expect_value(t, g.energy, 40 + ENERGY_UPGRADE) // today gets it too
	second, _ := price(&g, .Energy)
	testing.expect(t, second > first, "dearer")
	sleep(&g)
	testing.expect_value(t, g.energy, ENERGY_START + ENERGY_UPGRADE)
}

@(test)
standing_still_drains_energy :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	// 10 seconds still, in small frames: 5 energy at 2 seconds each.
	for _ in 0 ..< 100 {
		tick(&g, 0.1)
	}
	testing.expect_value(t, g.energy, ENERGY_START - 5)
	// A step starts the count again: 1.9 seconds, a step, 1.9 seconds costs nothing.
	g.idle_timer = 0
	before := g.energy
	for _ in 0 ..< 19 {
		tick(&g, 0.1)
	}
	command(&g, .North)
	for _ in 0 ..< 19 {
		tick(&g, 0.1)
	}
	testing.expect_value(t, g.energy, before)
}

@(test)
no_drain_in_menus_or_at_zero :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	open_shop(&g)
	for _ in 0 ..< 100 {
		tick(&g, 0.1)
	}
	testing.expect_value(t, g.energy, ENERGY_START)
	g.menu_open = false
	g.energy = 1
	for _ in 0 ..< 100 {
		tick(&g, 0.1)
	}
	testing.expect_value(t, g.energy, 0)
}

@(test)
version_4_save_loads :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	g.version = 4
	g.mortgage = 999
	buf: [SAVE_CAP]u8
	save_game(&g, buf[:])
	testing.expect(t, load_game(&h, buf[:SAVE_V4_SIZE]), "v4 save loads")
	testing.expect_value(t, h.mortgage, i64(999))
	testing.expect_value(t, h.energy_level, 0)
}
