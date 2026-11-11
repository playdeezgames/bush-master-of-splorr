package game

// Draws the plot, the fence, the bushes and their berries, the basket, the bush master, the
// tallies and the floating "+1"s.

// Where a bush's berries sit on its 12x12 picture, one per berry it holds.
BERRY_SPOTS := [BERRY_MAX][2]int{{3, 2}, {7, 3}, {2, 6}, {8, 7}, {5, 8}}

// Scattered grass outside the fence, from a fixed pattern so it never flickers.
grass_here :: proc(cx, cy: int) -> bool {
	h := u32(cx * 73856093) ~ u32(cy * 19349663)
	h ~= h >> 13
	h *= 0x5bd1e995
	h ~= h >> 15
	return h % 5 == 0
}

tile_px :: proc(x, y: int) -> (int, int) {
	return (PLOT_TX + x) * TILE, (PLOT_TY + y) * TILE
}

print_centered :: proc(f: ^Frame, text: string, y: int, color: u8) {
	print(f, text, (SCREEN_W - text_width(text)) / 2, y, color)
}

draw_game :: proc(f: ^Frame, g: ^Game) {
	cls(f, COLOR_BLACK)
	// Outside: grass.
	for cy in 0 ..< SCREEN_H / TILE {
		for cx in 0 ..< SCREEN_W / TILE {
			// Not behind the title, the tallies or the hints.
			if cy >= PLOT_TY - 2 && cy <= PLOT_TY + PLOT_H && grass_here(cx, cy) {
				draw_gfx(f, .Grass, cx * TILE, cy * TILE, COLOR_TEAL)
			}
		}
	}
	// The plot: dirt, cleared of grass.
	fill_rect(f, PLOT_TX * TILE, PLOT_TY * TILE, PLOT_W * TILE, PLOT_H * TILE, COLOR_DARK)
	for y in 0 ..< PLOT_H {
		for x in 0 ..< PLOT_W {
			if (x * 7 + y * 3) % 5 == 0 {
				sx, sy := tile_px(x, y)
				draw_gfx(f, .Specks, sx, sy, COLOR_MID)
			}
		}
	}
	// The fence, one tile around the plot.
	for x in -1 ..= PLOT_W {
		sx, sy := tile_px(x, -1)
		fill_rect(f, sx, sy, TILE, TILE, COLOR_BLACK)
		draw_gfx(f, .Fence, sx, sy, COLOR_WHITE)
		sx, sy = tile_px(x, PLOT_H)
		fill_rect(f, sx, sy, TILE, TILE, COLOR_BLACK)
		draw_gfx(f, .Fence, sx, sy, COLOR_WHITE)
	}
	for y in 0 ..< PLOT_H {
		sx, sy := tile_px(-1, y)
		fill_rect(f, sx, sy, TILE, TILE, COLOR_BLACK)
		draw_gfx(f, .Fence, sx, sy, COLOR_WHITE)
		sx, sy = tile_px(PLOT_W, y)
		fill_rect(f, sx, sy, TILE, TILE, COLOR_BLACK)
		draw_gfx(f, .Fence, sx, sy, COLOR_WHITE)
	}
	// Bushes, with a red dot per berry.
	for i in 0 ..< g.bush_count {
		b := g.bushes[i]
		sx, sy := tile_px(b.x, b.y)
		draw_gfx(f, .Bush, sx, sy, COLOR_GREEN)
		for k in 0 ..< b.berries {
			s := BERRY_SPOTS[k]
			fill_rect(f, sx + s.x, sy + s.y, 2, 2, COLOR_RED)
			set_px(f, sx + s.x, sy + s.y, COLOR_ORANGE) // a glint
		}
	}
	// The basket.
	{
		sx, sy := tile_px(g.basket_x, g.basket_y)
		draw_gfx(f, .Basket, sx, sy, COLOR_BROWN)
	}
	// The shop: a bold yellow $ in a yellow frame.
	{
		sx, sy := tile_px(g.shop_x, g.shop_y)
		draw_frame(f, sx, sy, TILE, TILE, COLOR_YELLOW)
		print(f, "$", sx + 3, sy + 2, COLOR_YELLOW)
		print(f, "$", sx + 4, sy + 2, COLOR_YELLOW)
	}
	// The bush master, with what they carry as dots over their head.
	{
		sx, sy := tile_px(g.px, g.py)
		draw_gfx(f, .Player, sx, sy, COLOR_WHITE)
		for k in 0 ..< g.carried {
			fill_rect(f, sx + 1 + k * 2, sy - 3, 2, 2, k % 2 == 0 ? COLOR_RED : COLOR_ORANGE)
		}
	}
	// Floating tallies.
	for p in g.pops {
		if !p.live {
			continue
		}
		sx, sy := tile_px(p.x, p.y)
		rise := int(p.age / POP_SECONDS * 12)
		buf: [16]u8
		switch p.kind {
		case .Berry:
			print(f, "+1", sx, sy - 8 - rise, COLOR_RED)
		case .Jools:
			w := print(f, "+", sx - 6, sy - 8 - rise, COLOR_YELLOW)
			print(f, itoa(buf[:], p.amount), sx - 6 + w, sy - 8 - rise, COLOR_YELLOW)
		case .Full:
			print(f, "FULL!", sx - 9, sy - 8 - rise, COLOR_ORANGE)
		case .New_Bush:
			print(f, "NEW!", sx - 6, sy - 8 - rise, COLOR_LIME)
		}
	}
	// Title and tallies.
	print_centered(f, "BUSH MASTER of SPLORR!!", 6, COLOR_LIME)
	buf: [16]u8
	{
		x := PLOT_TX * TILE - TILE
		y := 26
		draw_gfx(f, .Jools, x, y - 2, COLOR_YELLOW)
		x += TILE + 3
		x += print(f, "Jools ", x, y, COLOR_LIGHT)
		print(f, itoa(buf[:], g.jools), x, y, COLOR_YELLOW)
	}
	{
		x := (PLOT_TX + PLOT_W - 6) * TILE
		y := 26
		draw_gfx(f, .Berry, x, y - 2, COLOR_RED)
		x += TILE + 3
		x += print(f, "Held ", x, y, COLOR_LIGHT)
		x += print(f, itoa(buf[:], g.carried), x, y, g.carried >= carry_max(g) ? COLOR_ORANGE : COLOR_RED)
		print(f, itoa(buf[:], carry_max(g)), x + print(f, "/", x, y, COLOR_MID), y, COLOR_MID)
	}
	// How to play.
	hy := (PLOT_TY + PLOT_H + 1) * TILE + 6
	print_centered(f, "Walk into a bush to pick, the basket to sell,", hy, COLOR_LIGHT)
	print_centered(f, "and the $ to shop. A jool a berry.", hy + 10, COLOR_LIGHT)
	print_centered(f, "Arrows or WASD to walk, Space for OK, Esc to cancel.", hy + 20, COLOR_MID)
	if g.menu_open {
		draw_shop_menu(f, g)
	}
}

draw_frame :: proc(f: ^Frame, x, y, w, h: int, c: u8) {
	fill_rect(f, x, y, w, 1, c)
	fill_rect(f, x, y + h - 1, w, 1, c)
	fill_rect(f, x, y, 1, h, c)
	fill_rect(f, x + w - 1, y, 1, h, c)
}

// The shop menu over the plot: a row per item with its price (yellow when affordable, red while
// flashing "not enough"), then Leave. The chosen row has a > and a lighter band.
MENU_W :: 252
MENU_H :: 78
MENU_X :: (SCREEN_W - MENU_W) / 2
MENU_Y :: PLOT_TY * TILE + 6

draw_shop_menu :: proc(f: ^Frame, g: ^Game) {
	fill_rect(f, MENU_X, MENU_Y, MENU_W, MENU_H, COLOR_BLACK)
	draw_frame(f, MENU_X, MENU_Y, MENU_W, MENU_H, COLOR_YELLOW)
	buf: [16]u8
	x0 := MENU_X + 10
	print(f, "$ THE SHOP", x0, MENU_Y + 6, COLOR_YELLOW)
	{
		n := itoa(buf[:], g.jools)
		w := text_width("Jools ") + text_width(n)
		x := MENU_X + MENU_W - 10 - w
		x += print(f, "Jools ", x, MENU_Y + 6, COLOR_LIGHT)
		print(f, n, x, MENU_Y + 6, COLOR_YELLOW)
	}
	for row in 0 ..< SHOP_ROWS {
		y := MENU_Y + 22 + row * 12
		chosen := row == g.menu_row
		if chosen {
			fill_rect(f, MENU_X + 4, y - 2, MENU_W - 8, 11, COLOR_DARK)
			print(f, ">", x0, y, COLOR_WHITE)
		}
		label_color: u8 = chosen ? COLOR_WHITE : COLOR_LIGHT
		if row == LEAVE_ROW {
			print(f, "Leave", x0 + 10, y, label_color)
			continue
		}
		item := Shop_Item(row)
		switch item {
		case .Hands:
			// "Bigger hands (holds 5)"
			x := x0 + 10 + print(f, "Bigger hands", x0 + 10, y, label_color)
			x += print(f, " (holds ", x, y, COLOR_MID)
			x += print(f, itoa(buf[:], carry_max(g)), x, y, COLOR_MID)
			print(f, ")", x, y, COLOR_MID)
		case .Bush:
			// "New bush (have 1 of 8)"
			x := x0 + 10 + print(f, "New bush", x0 + 10, y, label_color)
			x += print(f, " (have ", x, y, COLOR_MID)
			x += print(f, itoa(buf[:], g.bush_count), x, y, COLOR_MID)
			x += print(f, " of ", x, y, COLOR_MID)
			x += print(f, itoa(buf[:], len(BUSH_SPOTS)), x, y, COLOR_MID)
			print(f, ")", x, y, COLOR_MID)
		}
		cost, ok := price(g, item)
		right := MENU_X + MENU_W - 10
		if !ok {
			t := item == .Bush ? "plot full" : "maxed"
			print(f, t, right - text_width(t), y, COLOR_MID)
			continue
		}
		color: u8 = g.jools >= cost ? COLOR_YELLOW : COLOR_MID
		if g.deny == 1 + int(item) {
			color = COLOR_RED
		}
		n := itoa(buf[:], cost)
		x := right - text_width(n) - text_width(" J")
		x += print(f, n, x, y, color)
		print(f, " J", x, y, color)
	}
	hint := g.deny != 0 ? "Not enough jools!" : "Up/Down choose, Space buys, Esc leaves."
	hc: u8 = g.deny != 0 ? COLOR_RED : COLOR_MID
	print(f, hint, MENU_X + (MENU_W - text_width(hint)) / 2, MENU_Y + MENU_H - 14, hc)
}
