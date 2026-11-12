package game

// Energy, the bed and the mortgage (the user's design, November 11, 2026).
// - Picking a berry and dropping a load in the basket each cost energy, and standing still drains it
//   slowly, so it is the day's clock. With too little left the bush master cannot pick or sell and
//   has to go to bed. The shop sells more energy.
// - The bed is in the plot's bottom-left corner: walk into it to sleep. Sleeping ends the day:
//   energy is full again, the bushes are full by morning, and the night's interest is added.
// - The mortgage starts at 1,000,000 jools at 10% a year, charged each night as a 365th of that
//   (rounded up) and compounding. It is paid from the shop menu's "Pay mortgage" row, Left and
//   Right choosing the amount. Paying it to zero is the win: a "Paid off!" notice, then play goes on.

// Tuning (the energy numbers are Claude's placeholders).
ENERGY_START :: 100 // a day's energy before any upgrade
IDLE_DRAIN_SECONDS :: 10.0 // this long without a step or spending energy costs 1 (paused while a menu or notice is up)
IDLE_DRAIN_STEP :: 2.0 // seconds each Stamina upgrade adds to that
PICK_ENERGY :: 1 // per berry picked
DEPOSIT_ENERGY :: 1 // per trip to the basket, however many berries
MORTGAGE_START :: i64(1_000_000)
INTEREST_PERCENT_PER_YEAR :: 10
NIGHTS_PER_YEAR :: 365

// What "Pay mortgage" can pay, chosen with Left and Right; 0 is "all yer jools".
PAY_STEPS := [?]i64{10, 100, 1_000, 10_000, 100_000, 0}

Notice :: enum {
	None,
	Morning, // after a night's sleep: the day, the interest charged
	Paid_Off, // the mortgage reached zero
	Confirm_Reset, // "start over?", menu_row 0 is No, 1 is Yes
	System, // the Esc menu: Carry on, Sound on/off, Start over (menu_row)
}

SYSTEM_ROWS :: 3
SYSTEM_SOUND_ROW :: 1
SYSTEM_RESET_ROW :: 2

energy_max :: proc(g: ^Game) -> int {
	return ENERGY_START + g.energy_level * ENERGY_UPGRADE
}

// Seconds of standing still that cost 1 energy, with the Stamina upgrades.
idle_seconds :: proc(g: ^Game) -> f64 {
	return IDLE_DRAIN_SECONDS + f64(g.stamina_level) * IDLE_DRAIN_STEP
}

// Standing still: 1 energy every idle_seconds. A step (game.odin) or spending energy on a pick
// or a basket trip starts the count again (the user, November 12, 2026: slower, and spending resets it).
// Not while the shop menu or a notice is up. True when energy changed.
idle_drain :: proc(g: ^Game, dt: f64) -> bool {
	if g.menu_open || g.notice != .None || g.energy <= 0 {
		g.idle_timer = 0
		return false
	}
	g.idle_timer += dt
	changed := false
	every := idle_seconds(g)
	for g.idle_timer >= every && g.energy > 0 {
		g.idle_timer -= every
		g.energy -= 1
		changed = true
	}
	return changed
}

is_bed :: proc(g: ^Game, x, y: int) -> bool {
	return x == g.bed_x && y == g.bed_y
}

// True when the bush master has `cost` energy to spend; otherwise a "TIRED" pop.
spend_energy :: proc(g: ^Game, cost: int) -> bool {
	if g.energy < cost {
		add_pop(g, .Tired, 0, g.px, g.py)
		play(g, .Tired)
		return false
	}
	g.energy -= cost
	g.idle_timer = 0 // working is not idling
	return true
}

// One night's interest on `owed`: a 365th of 10%, rounded up.
nightly_interest :: proc(owed: i64) -> i64 {
	if owed <= 0 {
		return 0
	}
	den := i64(100 * NIGHTS_PER_YEAR)
	return (owed * INTEREST_PERCENT_PER_YEAR + den - 1) / den
}

sleep :: proc(g: ^Game) {
	g.day += 1
	g.energy = energy_max(g)
	for i in 0 ..< g.bush_count {
		g.bushes[i].berries = BERRY_MAX
		g.bushes[i].regrow = 0
	}
	g.last_interest = nightly_interest(g.mortgage)
	g.mortgage += g.last_interest
	g.notice = .Morning
	play(g, .Sleep)
}

// What the chosen pay step pays: "all" is every jool on hand, a fixed step is that many; neither
// more than is owed.
pay_amount :: proc(g: ^Game) -> i64 {
	step := PAY_STEPS[clamp(g.pay_step, 0, len(PAY_STEPS) - 1)]
	if step == 0 {
		step = i64(g.jools)
	}
	return min(step, g.mortgage)
}

// Pays the chosen amount; refused (the row flashes) when the jools are short or there is nothing
// to pay.
pay_mortgage :: proc(g: ^Game) -> bool {
	amount := pay_amount(g)
	if amount <= 0 || i64(g.jools) < amount {
		g.deny = 1 + PAY_ROW
		g.deny_timer = 0.5
		play(g, .Deny)
		return false
	}
	g.jools -= int(amount)
	g.mortgage -= amount
	if g.mortgage == 0 {
		g.menu_open = false
		g.notice = .Paid_Off
		play(g, .Paid_Off)
	} else {
		play(g, .Pay)
	}
	return true
}

notice_command :: proc(g: ^Game, c: Command) {
	if g.notice == .Confirm_Reset {
		reset_command(g, c)
		return
	}
	if g.notice == .System {
		system_command(g, c)
		return
	}
	if c == .Act || c == .Cancel {
		g.notice = .None
		play(g, .Close)
	}
}

// The Esc menu on the plot: carry on, sound on or off, start over.
open_system_menu :: proc(g: ^Game) {
	g.notice = .System
	g.menu_row = 0
	play(g, .Open)
}

system_command :: proc(g: ^Game, c: Command) {
	switch c {
	case .North:
		g.menu_row = (g.menu_row + SYSTEM_ROWS - 1) % SYSTEM_ROWS
		play(g, .Move)
	case .South:
		g.menu_row = (g.menu_row + 1) % SYSTEM_ROWS
		play(g, .Move)
	case .West, .East:
		if g.menu_row == SYSTEM_SOUND_ROW {
			toggle_mute(g)
		}
	case .Act:
		switch g.menu_row {
		case SYSTEM_SOUND_ROW:
			toggle_mute(g)
		case SYSTEM_RESET_ROW:
			ask_reset(g)
		case:
			g.notice = .None
			g.menu_row = 0
			play(g, .Close)
		}
	case .Cancel:
		g.notice = .None
		g.menu_row = 0
		play(g, .Close)
	}
}

toggle_mute :: proc(g: ^Game) {
	g.muted = !g.muted
	play(g, .Move) // heard only when turning sound on
}

// Starts over, keeping only whether sound is muted.
reset_game :: proc(g: ^Game) {
	muted := g.muted
	init_game(g)
	g.muted = muted
	play(g, .Reset)
}

// Starting over (the user, November 12, 2026): from the Esc menu, asking first and warning that
// everything is forgotten. No is chosen to begin with; only Yes and Space wipe the game.
ask_reset :: proc(g: ^Game) {
	g.notice = .Confirm_Reset
	g.menu_row = 0
}

reset_command :: proc(g: ^Game, c: Command) {
	switch c {
	case .North, .South, .West, .East:
		g.menu_row = 1 - clamp(g.menu_row, 0, 1)
		play(g, .Move)
	case .Act:
		if g.menu_row == 1 {
			reset_game(g)
		} else {
			g.notice = .None
			play(g, .Close)
		}
	case .Cancel:
		g.notice = .None
		play(g, .Close)
	}
	if g.notice == .None {
		g.menu_row = 0
	}
}
