#+build !js
package game

import "core:os"
import "core:testing"

_ :: os

DUMP_PLAY :: #config(DUMP_PLAY, "")
DUMP_SHOP :: #config(DUMP_SHOP, "")
DUMP_MORNING :: #config(DUMP_MORNING, "")

// Writes a frame mid-play to a PPM, for screenshots: -define:DUMP_PLAY=<path.ppm>
@(test)
dump_play :: proc(t: ^testing.T) {
	when DUMP_PLAY != "" {
		g: Game
		init_game(&g)
		g.bushes[0].berries = 3
		g.px, g.py = 9, 6
		g.carried = 2
		g.jools = 74
		g.hands_level = 2
		g.bushes[1] = {x = 6, y = 2, berries = 4}
		g.bush_count = 2
		g.energy = 62
		g.day = 3
		g.mortgage = 1_000_548
		add_pop(&g, .Jools, 3, g.basket_x, g.basket_y)
		g.pops[0].age = 0.3
		f := new(Frame)
		defer free(f)
		draw_game(f, &g)
		resolve(f)
		out := make([dynamic]u8)
		defer delete(out)
		header := "P6\n384 216\n255\n"
		append(&out, ..transmute([]u8)header)
		for c in f.rgba {
			append(&out, u8(c), u8(c >> 8), u8(c >> 16))
		}
		testing.expect(t, os.write_entire_file(DUMP_PLAY, out[:]) == nil)
	}
}

write_ppm :: proc(path: string, f: ^Frame) -> bool {
	out := make([dynamic]u8)
	defer delete(out)
	header := "P6\n384 216\n255\n"
	append(&out, ..transmute([]u8)header)
	for c in f.rgba {
		append(&out, u8(c), u8(c >> 8), u8(c >> 16))
	}
	return os.write_entire_file(path, out[:]) == nil
}

// The shop menu open, with the bush row chosen and short of jools: -define:DUMP_SHOP=<path.ppm>
@(test)
dump_shop :: proc(t: ^testing.T) {
	when DUMP_SHOP != "" {
		g: Game
		init_game(&g)
		g.jools = 74
		g.hands_level = 2
		g.bushes[1] = {x = 6, y = 2, berries = 4}
		g.bush_count = 2
		g.px, g.py = g.shop_x - 1, g.shop_y
		command(&g, .East)
		command(&g, .South)
		command(&g, .South)
		command(&g, .South)
		command(&g, .South)
		command(&g, .Act)
		f := new(Frame)
		defer free(f)
		draw_game(f, &g)
		resolve(f)
		testing.expect(t, write_ppm(DUMP_SHOP, f))
	}
}

// The morning notice after a night's sleep: -define:DUMP_MORNING=<path.ppm>
@(test)
dump_morning :: proc(t: ^testing.T) {
	when DUMP_MORNING != "" {
		g: Game
		init_game(&g)
		g.jools = 31
		g.energy = 0
		g.px, g.py = g.bed_x + 1, g.bed_y
		command(&g, .West)
		f := new(Frame)
		defer free(f)
		draw_game(f, &g)
		resolve(f)
		testing.expect(t, write_ppm(DUMP_MORNING, f))
	}
}
