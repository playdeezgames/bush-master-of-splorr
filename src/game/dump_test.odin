#+build !js
package game

import "core:os"
import "core:testing"

_ :: os

DUMP_PLAY :: #config(DUMP_PLAY, "")

// Writes a frame mid-play to a PPM, for screenshots: -define:DUMP_PLAY=<path.ppm>
@(test)
dump_play :: proc(t: ^testing.T) {
	when DUMP_PLAY != "" {
		g: Game
		init_game(&g)
		g.bushes[0].berries = 3
		g.px, g.py = 9, 6
		g.carried = 2
		g.jools = 17
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
