#+build !js
package game

import "core:testing"

// A plot with a port and a robot, the bush master out of the way.
robot_game :: proc(g: ^Game) {
	init_game(g)
	g.px, g.py = 10, 7
	testing_must(add_port(g))
	testing_must(add_robot(g))
}

testing_must :: proc(ok: bool, loc := #caller_location) {
	assert(ok, "setup failed", loc)
}

@(test)
a_robot_needs_a_port :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 10_000
	testing.expect(t, robot_needs_port(&g), "no port yet")
	testing.expect(t, !buy(&g, .Robot), "refused without a port")
	testing.expect_value(t, g.deny, 1 + int(Shop_Item.Robot))
	testing.expect_value(t, g.jools, 10_000)
	testing.expect(t, buy(&g, .Port), "port")
	testing.expect_value(t, g.jools, 10_000 - PORT_PRICE_START)
	testing.expect(t, buy(&g, .Robot), "robot")
	testing.expect_value(t, g.robot_count, 1)
	testing.expect(t, robot_needs_port(&g), "the next robot needs another port")
	testing.expect(t, !buy(&g, .Robot), "second robot refused")
	r := g.robots[0]
	testing.expect(t, beside(&r, g.ports[0].x, g.ports[0].y), "starts beside its port")
	testing.expect_value(t, r.battery, robot_battery_max(&g))
	testing.expect(t, blocked(&g, g.ports[0].x, g.ports[0].y), "ports are in the way")
}

@(test)
a_robot_picks_and_sells :: proc(t: ^testing.T) {
	g: Game
	robot_game(&g)
	g.ports[0].charge = PORT_STORE
	tick_for(&g, 60)
	testing.expect(t, g.jools > 0, "robot sold berries")
	testing.expect(t, g.picked > 0, "robot picked")
	testing.expect_value(t, g.carried, 0) // the bush master did nothing
}

@(test)
a_robot_goes_home_before_it_runs_flat :: proc(t: ^testing.T) {
	g: Game
	robot_game(&g)
	g.robot_speed_level = ROBOT_SPEED_MAX_LEVEL
	lowest := 999.0
	went_home := false
	for _ in 0 ..< 3000 {
		tick(&g, 0.1)
		r := &g.robots[0]
		lowest = min(lowest, r.battery)
		went_home ||= r.going_home
	}
	testing.expect(t, went_home, "it went home to charge")
	testing.expect(t, lowest >= 0, "never below empty")
	// It never stalled away from home: a flat robot is beside its port or still has charge.
	r := &g.robots[0]
	testing.expect(t, r.battery >= ROBOT_STEP_COST || beside(r, g.ports[0].x, g.ports[0].y), "not stranded")
}

@(test)
ports_gather_sun_only_by_day :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	testing_must(add_port(&g))
	tick_for(&g, 10)
	day := g.ports[0].charge
	testing.expect(t, day > 0, "day sun")
	g.energy = 0 // night: the bush master is spent
	tick_for(&g, 10)
	testing.expect_value(t, g.ports[0].charge, day)
	testing.expect(t, is_night(&g), "night")
}

@(test)
robots_charge_from_their_port :: proc(t: ^testing.T) {
	g: Game
	robot_game(&g)
	r := &g.robots[0]
	r.battery = 1
	r.going_home = true
	g.ports[0].charge = 20
	tick_for(&g, 1)
	testing.expect(t, r.battery > 1, "charging")
	testing.expect(t, g.ports[0].charge < 20, "from the port's store")
	testing.expect(t, r.going_home, "not full yet, still charging")
}

@(test)
robot_upgrades :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	g.jools = 100_000
	speed, battery, carry := robot_speed(&g), robot_battery_max(&g), robot_carry_max(&g)
	testing.expect(t, buy(&g, .Robot_Speed), "speed")
	testing.expect(t, buy(&g, .Robot_Battery), "battery")
	testing.expect(t, buy(&g, .Robot_Carry), "carry")
	testing.expect(t, robot_speed(&g) > speed, "faster")
	testing.expect(t, robot_battery_max(&g) > battery, "bigger battery")
	testing.expect_value(t, robot_carry_max(&g), carry + 1)
	p, _ := price(&g, .Robot_Speed)
	testing.expect_value(t, p, (ROBOT_SPEED_PRICE_START * 3 + 1) / 2)
}

@(test)
the_shop_menu_scrolls :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	open_shop(&g)
	command(&g, .North) // wraps to Leave, the last row
	testing.expect_value(t, g.menu_row, LEAVE_ROW)
	testing.expect_value(t, g.menu_top, SHOP_ROWS - MENU_SHOWN)
	command(&g, .South) // back to the top
	testing.expect_value(t, g.menu_row, 0)
	testing.expect_value(t, g.menu_top, 0)
}

@(test)
version_6_save_loads :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	g.version = 6
	g.price_level = 2
	buf: [SAVE_CAP]u8
	save_game(&g, buf[:])
	testing.expect(t, load_game(&h, buf[:SAVE_V6_SIZE]), "v6 save loads")
	testing.expect_value(t, h.price_level, 2)
	testing.expect_value(t, h.port_count, 0)
	testing.expect_value(t, h.robot_count, 0)
}

@(test)
solar_rate_upgrade_fills_ports_faster :: proc(t: ^testing.T) {
	g: Game
	init_game(&g)
	testing_must(add_port(&g))
	g.jools = 1000
	testing.expect(t, buy(&g, .Solar), "bought")
	testing.expect_value(t, g.jools, 1000 - SOLAR_PRICE_START)
	testing.expect_value(t, port_sun_rate(&g), PORT_SUN_PER_SECOND + PORT_SUN_UPGRADE)
	tick_for(&g, 4)
	testing.expect(t, g.ports[0].charge > 4 * PORT_SUN_PER_SECOND + 0.5, "faster than before")
	g.energy = 0
	before := g.ports[0].charge
	tick_for(&g, 4)
	testing.expect_value(t, g.ports[0].charge, before) // still nothing at night
}

@(test)
version_7_save_loads :: proc(t: ^testing.T) {
	g, h: Game
	init_game(&g)
	g.version = 7
	add_port(&g)
	buf: [SAVE_CAP]u8
	save_game(&g, buf[:])
	testing.expect(t, load_game(&h, buf[:SAVE_V7_SIZE]), "v7 save loads")
	testing.expect_value(t, h.port_count, 1)
	testing.expect_value(t, h.solar_level, 0)
}
