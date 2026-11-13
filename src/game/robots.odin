package game

// Robots and solar charging ports (the user's design, November 12, 2026).
// - A robot needs a solar charging port: each port keeps one robot, so robots are never more than
//   ports. Ports stand along the top of the plot.
// - A port gathers sunlight into its store during the day. Day and night follow the bush master:
//   while they have energy it is day; at 0 energy it is night and the ports gather nothing.
// - A robot runs on its battery: each step, each berry picked and each trip to the basket costs
//   charge. It picks the nearest bush with berries, takes a load to the basket, and heads home to
//   its port to charge from the port's store before it runs flat. A robot waiting on an empty port
//   (at night, say) waits.
// - The shop sells ports, a faster solar rate, robots, and robot speed, battery and carrying upgrades (shop.odin).
// Robots walk through the bush master and each other; bushes, the basket, the shop, the bed and the
// ports are in their way.

// Tuning (Claude's placeholders).
PORT_CAP :: 4
ROBOT_CAP :: PORT_CAP
PORT_STORE :: 100.0 // charge a port can hold
PORT_SUN_PER_SECOND :: 0.5 // charge a port gathers each second of day, before upgrades
PORT_SUN_UPGRADE :: 0.25 // each Solar rate upgrade adds this (the user, November 13, 2026)
PORT_FEED_PER_SECOND :: 6.0 // charge a port gives its robot each second
ROBOT_BATTERY_START :: 60 // battery before upgrades
ROBOT_BATTERY_UPGRADE :: 15
ROBOT_SPEED_START :: 1.0 // steps (or picks, or drops) a second
ROBOT_SPEED_UPGRADE :: 0.5
ROBOT_CARRY_START :: 2 // berries a robot holds before upgrades
ROBOT_STEP_COST :: 1.0 // charge per step, per berry picked and per basket trip

// Where ports go, in order: the top row, a gap between each so the way round stays open.
PORT_SPOTS := [PORT_CAP][2]int{{0, 0}, {2, 0}, {4, 0}, {6, 0}}

Port :: struct {
	x, y:   int,
	charge: f64,
}

Robot :: struct {
	x, y:       int,
	battery:    f64,
	carried:    int,
	going_home: bool, // low on charge: heading to its port, then charging till full
	step_timer: f64, // toward the next step
}

port_sun_rate :: proc(g: ^Game) -> f64 {
	return PORT_SUN_PER_SECOND + f64(g.solar_level) * PORT_SUN_UPGRADE
}

robot_battery_max :: proc(g: ^Game) -> f64 {
	return f64(ROBOT_BATTERY_START + g.robot_battery_level * ROBOT_BATTERY_UPGRADE)
}

robot_speed :: proc(g: ^Game) -> f64 {
	return ROBOT_SPEED_START + f64(g.robot_speed_level) * ROBOT_SPEED_UPGRADE
}

robot_carry_max :: proc(g: ^Game) -> int {
	return ROBOT_CARRY_START + g.robot_carry_level
}

// Night is when the bush master has no energy left (the user's definition).
is_night :: proc(g: ^Game) -> bool {
	return g.energy <= 0
}

port_at :: proc(g: ^Game, x, y: int) -> int {
	for i in 0 ..< g.port_count {
		if g.ports[i].x == x && g.ports[i].y == y {
			return i
		}
	}
	return -1
}

robot_at :: proc(g: ^Game, x, y: int) -> bool {
	for i in 0 ..< g.robot_count {
		if g.robots[i].x == x && g.robots[i].y == y {
			return true
		}
	}
	return false
}

// Somewhere nobody is standing and nothing is built: for a new bush or port.
spot_free :: proc(g: ^Game, x, y: int) -> bool {
	return !blocked(g, x, y) && !(g.px == x && g.py == y) && !robot_at(g, x, y)
}

free_port_spot :: proc(g: ^Game) -> (int, int, bool) {
	for s in PORT_SPOTS {
		if spot_free(g, s.x, s.y) {
			return s.x, s.y, true
		}
	}
	return 0, 0, false
}

// A robot can stand here: in the plot, with nothing built on it.
robot_walkable :: proc(g: ^Game, x, y: int) -> bool {
	return !blocked(g, x, y)
}

Dist_Map :: [PLOT_W * PLOT_H]int

Target :: enum {
	Berries, // any bush with a berry on it
	Basket,
	Home, // the robot's own port
}

is_target :: proc(g: ^Game, x, y: int, target: Target, home: int) -> bool {
	switch target {
	case .Berries:
		b := bush_at(g, x, y)
		return b != nil && b.berries > 0
	case .Basket:
		return is_basket(g, x, y)
	case .Home:
		return port_at(g, x, y) == home
	}
	return false
}

// Steps from every tile to standing beside a target (0 is beside one); -1 where none can be reached.
dist_map :: proc(g: ^Game, target: Target, home: int, d: ^Dist_Map) {
	queue: [PLOT_W * PLOT_H]int
	head, tail := 0, 0
	for i in 0 ..< len(d) {
		d[i] = -1
	}
	for y in 0 ..< PLOT_H {
		for x in 0 ..< PLOT_W {
			if !robot_walkable(g, x, y) {
				continue
			}
			for dir in DIRS {
				if in_plot(x + dir.x, y + dir.y) && is_target(g, x + dir.x, y + dir.y, target, home) {
					d[y * PLOT_W + x] = 0
					queue[tail] = y * PLOT_W + x
					tail += 1
					break
				}
			}
		}
	}
	for head < tail {
		at := queue[head]
		head += 1
		x, y := at % PLOT_W, at / PLOT_W
		for dir in DIRS {
			nx, ny := x + dir.x, y + dir.y
			if !in_plot(nx, ny) || !robot_walkable(g, nx, ny) || d[ny * PLOT_W + nx] >= 0 {
				continue
			}
			d[ny * PLOT_W + nx] = d[at] + 1
			queue[tail] = ny * PLOT_W + nx
			tail += 1
		}
	}
}

dist_at :: proc(d: ^Dist_Map, x, y: int) -> int {
	return in_plot(x, y) ? d[y * PLOT_W + x] : -1
}

// One step downhill on the map. False when there is nowhere to go.
step_toward :: proc(g: ^Game, r: ^Robot, d: ^Dist_Map) -> bool {
	here := dist_at(d, r.x, r.y)
	for dir in DIRS {
		nx, ny := r.x + dir.x, r.y + dir.y
		n := dist_at(d, nx, ny)
		if n >= 0 && (here < 0 || n < here) && robot_walkable(g, nx, ny) {
			r.x, r.y = nx, ny
			r.battery -= ROBOT_STEP_COST
			return true
		}
	}
	return false
}

beside :: proc(r: ^Robot, x, y: int) -> bool {
	return abs(r.x - x) + abs(r.y - y) == 1
}

// What a robot does with one step's worth of time.
robot_act :: proc(g: ^Game, i: int) {
	r := &g.robots[i]
	if r.battery < ROBOT_STEP_COST {
		return // flat: it waits (it should have gone home first)
	}
	home: Dist_Map
	dist_map(g, .Home, i, &home)
	hd := dist_at(&home, r.x, r.y)
	// Enough left to get home, with a little to spare, or it goes now.
	if !r.going_home && hd >= 0 && r.battery < f64(hd + 2) * ROBOT_STEP_COST {
		r.going_home = true
	}
	if r.going_home {
		if hd > 0 {
			step_toward(g, r, &home)
		}
		return // beside the port, tick_robots charges it
	}
	berries: Dist_Map
	dist_map(g, .Berries, i, &berries)
	bd := dist_at(&berries, r.x, r.y)
	if r.carried >= robot_carry_max(g) || (r.carried > 0 && bd < 0) {
		basket: Dist_Map
		dist_map(g, .Basket, i, &basket)
		if dist_at(&basket, r.x, r.y) == 0 {
			robot_deposit(g, r)
		} else {
			step_toward(g, r, &basket)
		}
		return
	}
	if bd == 0 {
		for dir in DIRS {
			if b := bush_at(g, r.x + dir.x, r.y + dir.y); b != nil && b.berries > 0 {
				robot_pick(g, r, b)
				return
			}
		}
	}
	if bd > 0 {
		step_toward(g, r, &berries)
		return
	}
	// Nothing to pick: wait at home (and top up there).
	if hd > 0 {
		step_toward(g, r, &home)
	}
}

robot_pick :: proc(g: ^Game, r: ^Robot, b: ^Bush) {
	if b.berries == BERRY_MAX {
		b.regrow = 0
	}
	b.berries -= 1
	r.carried += 1
	r.battery -= ROBOT_STEP_COST
	g.picked += 1
	add_pop(g, .Berry, 1, b.x, b.y)
	play(g, .Robot_Pick)
}

robot_deposit :: proc(g: ^Game, r: ^Robot) {
	pay := r.carried * berry_price(g)
	g.jools += pay
	r.carried = 0
	r.battery -= ROBOT_STEP_COST
	add_pop(g, .Jools, pay, g.basket_x, g.basket_y)
	play(g, .Robot_Sell)
}

// Sun on the ports, ports feeding robots beside them, robots stepping. True when anything changed.
tick_robots :: proc(g: ^Game, dt: f64) -> bool {
	if g.port_count == 0 {
		return false
	}
	if !is_night(g) {
		for i in 0 ..< g.port_count {
			p := &g.ports[i]
			p.charge = min(p.charge + port_sun_rate(g) * dt, PORT_STORE)
		}
	}
	most := robot_battery_max(g)
	for i in 0 ..< g.robot_count {
		r := &g.robots[i]
		p := &g.ports[i]
		at_home := beside(r, p.x, p.y)
		if at_home && r.battery < most {
			feed := min(PORT_FEED_PER_SECOND * dt, p.charge, most - r.battery)
			r.battery += feed
			p.charge -= feed
		}
		if r.going_home && at_home {
			if r.battery >= most - 1e-6 {
				r.going_home = false // full: back to work
			} else {
				r.step_timer = 0
				continue // charging
			}
		}
		r.step_timer += dt * robot_speed(g)
		for r.step_timer >= 1 {
			r.step_timer -= 1
			robot_act(g, i)
		}
	}
	return true
}

// Builds the next port (bought in the shop).
add_port :: proc(g: ^Game) -> bool {
	x, y, ok := free_port_spot(g)
	if !ok || g.port_count >= PORT_CAP {
		return false
	}
	g.ports[g.port_count] = {x = x, y = y}
	g.port_count += 1
	return true
}

// A new robot, full of charge, beside the first port without one.
add_robot :: proc(g: ^Game) -> bool {
	if g.robot_count >= g.port_count {
		return false
	}
	p := g.ports[g.robot_count]
	for dir in ([4][2]int{{0, 1}, {1, 0}, {-1, 0}, {0, -1}}) {
		x, y := p.x + dir.x, p.y + dir.y
		if in_plot(x, y) && robot_walkable(g, x, y) {
			g.robots[g.robot_count] = {x = x, y = y, battery = robot_battery_max(g)}
			g.robot_count += 1
			return true
		}
	}
	return false
}
