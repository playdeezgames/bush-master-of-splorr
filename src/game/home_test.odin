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

// Ticks `seconds` of real time in tenth-of-a-second frames.
tick_for :: proc(g: ^Game, seconds: f64) {
	for _ in 0 ..< int(seconds * 10 + 0.5) {
		tick(g, 0.1)
	}
}

@(test)
standing_still_drains_energy :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	tick_for(&g, 5 * IDLE_DRAIN_SECONDS + 0.1) // a frame spare: tenths do not add up exactly
	testing.expect_value(t, g.energy, ENERGY_START - 5)
	// A step starts the count again: nearly a drain's worth, a step, nearly again costs nothing.
	g.idle_timer = 0
	before := g.energy
	tick_for(&g, IDLE_DRAIN_SECONDS - 0.1)
	command(&g, .North)
	tick_for(&g, IDLE_DRAIN_SECONDS - 0.1)
	testing.expect_value(t, g.energy, before)
}

@(test)
spending_energy_starts_the_idle_count_again :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.px, g.py = 3, 3 // below the first bush at (3, 2)
	tick_for(&g, IDLE_DRAIN_SECONDS - 0.1)
	command(&g, .Act) // pick: 1 energy, and the count restarts
	testing.expect_value(t, g.energy, ENERGY_START - PICK_ENERGY)
	tick_for(&g, IDLE_DRAIN_SECONDS - 0.1)
	testing.expect_value(t, g.energy, ENERGY_START - PICK_ENERGY)
	tick_for(&g, 0.2)
	testing.expect_value(t, g.energy, ENERGY_START - PICK_ENERGY - 1)
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
	tick_for(&g, 3 * IDLE_DRAIN_SECONDS)
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

@(test)
version_5_save_loads :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	g.version = 5
	g.energy_level = 3
	buf: [SAVE_CAP]u8
	save_game(&g, buf[:])
	testing.expect(t, load_game(&h, buf[:SAVE_V5_SIZE]), "v5 save loads")
	testing.expect_value(t, h.energy_level, 3)
	testing.expect_value(t, h.price_level, 0)
	testing.expect_value(t, berry_price(&h), 1)
	testing.expect_value(t, h.stamina_level, 0)
}

@(test)
stamina_slows_the_idle_drain :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	first, _ := price(&g, .Stamina)
	testing.expect_value(t, first, STAMINA_PRICE_START)
	g.jools = first
	testing.expect(t, buy(&g, .Stamina), "bought")
	testing.expect_value(t, idle_seconds(&g), IDLE_DRAIN_SECONDS + IDLE_DRAIN_STEP)
	tick_for(&g, IDLE_DRAIN_SECONDS + 0.5)
	testing.expect_value(t, g.energy, ENERGY_START) // not yet
	tick_for(&g, IDLE_DRAIN_STEP)
	testing.expect_value(t, g.energy, ENERGY_START - 1)
	g.stamina_level = STAMINA_MAX_LEVEL
	_, more := price(&g, .Stamina)
	testing.expect(t, !more, "maxed")
}

@(test)
esc_asks_before_starting_over :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 500
	g.day = 9
	g.hands_level = 3
	g.muted = true
	ask := proc(g: ^Game) {
		command(g, .Cancel) // the Esc menu
		command(g, .North) // up wraps to Start over
		command(g, .Act)
	}
	command(&g, .Cancel)
	testing.expect_value(t, g.notice, Notice.System)
	command(&g, .Cancel)
	ask(&g)
	testing.expect_value(t, g.notice, Notice.Confirm_Reset)
	testing.expect_value(t, g.menu_row, 0) // No is chosen first
	command(&g, .Act) // No: nothing lost
	testing.expect_value(t, g.notice, Notice.None)
	testing.expect_value(t, g.jools, 500)
	ask(&g)
	command(&g, .South)
	command(&g, .Cancel) // Esc backs out even with Yes chosen
	testing.expect_value(t, g.jools, 500)
	px := g.px
	ask(&g)
	command(&g, .South) // moves the choice, not the bush master
	testing.expect_value(t, g.px, px)
	command(&g, .Act) // Yes
	fresh: Game
	init_game(&fresh)
	fresh.muted = true // the only thing kept
	testing.expect(t, g == fresh, "a fresh plot")
}

@(test)
a_save_never_reopens_the_start_over_question :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	ask_reset(&g)
	buf: [SAVE_CAP]u8
	n := save_game(&g, buf[:])
	testing.expect(t, load_game(&h, buf[:n]), "loads")
	testing.expect_value(t, h.notice, Notice.None)
}

@(test)
sounds_queue_unless_muted :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.px, g.py = 3, 3 // below the bush
	command(&g, .Act)
	testing.expect_value(t, g.sound_count, 1)
	testing.expect_value(t, g.sounds[0], Sound.Pick)
	g.sound_count = 0
	// Mute from the Esc menu.
	command(&g, .Cancel)
	command(&g, .South)
	command(&g, .Act)
	testing.expect(t, g.muted, "muted")
	command(&g, .Cancel)
	g.sound_count = 0
	command(&g, .Act)
	testing.expect_value(t, g.carried, 2)
	testing.expect_value(t, g.sound_count, 0)
	// And back on; the switch itself is heard.
	command(&g, .Cancel)
	command(&g, .South)
	command(&g, .East)
	testing.expect(t, !g.muted, "sound on")
	testing.expect_value(t, g.sounds[g.sound_count - 1], Sound.Move)
}
