package game

// Software renderer: a 384x216 landscape screen of palette indices, resolved to RGBA for the page.
// Pictures are Urizen 12x12 masks (gfx.odin), text is the 6x8 DINOBYTE font (font.odin), colours
// are the Sweetie-16 palette.

SCREEN_W :: 384
SCREEN_H :: 216

TILE :: 12
GLYPH_W :: 6
GLYPH_H :: 8

Frame :: struct {
	px:   [SCREEN_W * SCREEN_H]u8, // palette indices
	rgba: [SCREEN_W * SCREEN_H]u32, // 0xAABBGGRR (little-endian R,G,B,A bytes)
}

PALETTE := [16]u32 {
	0x1A1C2C, 0x5D275D, 0xB13E53, 0xEF7D57, 0xFFCD75, 0xA7F070, 0x38B764, 0x257179,
	0x29366F, 0x3B5DC9, 0x41A6F6, 0x73EFF7, 0xF4F4F4, 0x94B0C2, 0x566C86, 0x333C57,
}

// Palette colours the game names.
COLOR_BLACK :: 0
COLOR_RED :: 2
COLOR_ORANGE :: 3
COLOR_BROWN :: 3 // Sweetie-16 has no brown; orange stands in
COLOR_LIME :: 5
COLOR_GREEN :: 6
COLOR_TEAL :: 7
COLOR_YELLOW :: 4
COLOR_CYAN :: 11
COLOR_WHITE :: 12
COLOR_LIGHT :: 13
COLOR_MID :: 14
COLOR_DARK :: 15

// Order matches PICKS in tools/extract_gfx.py.
Gfx :: enum {
	Grass,
	Fence,
	Bush,
	Basket,
	Player,
	Berry,
	Jools,
	Specks,
	Bed,
}

cls :: proc(f: ^Frame, c: u8) {
	for &p in f.px {
		p = c
	}
}

set_px :: proc(f: ^Frame, x, y: int, c: u8) {
	if x < 0 || y < 0 || x >= SCREEN_W || y >= SCREEN_H {
		return
	}
	f.px[y * SCREEN_W + x] = c
}

get_px :: proc(f: ^Frame, x, y: int) -> u8 {
	if x < 0 || y < 0 || x >= SCREEN_W || y >= SCREEN_H {
		return 0
	}
	return f.px[y * SCREEN_W + x]
}

fill_rect :: proc(f: ^Frame, x, y, w, h: int, c: u8) {
	for yy in y ..< y + h {
		for xx in x ..< x + w {
			set_px(f, xx, yy, c)
		}
	}
}

// Paints a picture's lit pixels in one colour; unlit pixels are left alone.
draw_gfx :: proc(f: ^Frame, g: Gfx, x, y: int, color: u8) {
	mask := GFX[g]
	for i in 0 ..< TILE * TILE {
		if mask[i / 48] & (1 << uint(i % 48)) != 0 {
			set_px(f, x + i % TILE, y + i / TILE, color)
		}
	}
}

text_width :: proc(text: string) -> int {
	return len(text) * GLYPH_W
}

// Monospaced print of bytes as code page 437; returns the width drawn.
print :: proc(f: ^Frame, text: string, x, y: int, color: u8 = COLOR_WHITE) -> int {
	for i in 0 ..< len(text) {
		bits := FONT[text[i]]
		for row in 0 ..< GLYPH_H {
			for col in 0 ..< GLYPH_W {
				if bits & (1 << uint(row * GLYPH_W + col)) != 0 {
					set_px(f, x + i * GLYPH_W + col, y + row, color)
				}
			}
		}
	}
	return text_width(text)
}

// Writes palette indices through the palette into rgba.
resolve :: proc(f: ^Frame) {
	for p, i in f.px {
		c := PALETTE[p & 15]
		f.rgba[i] = 0xFF000000 | (c & 0xFF) << 16 | (c >> 8 & 0xFF) << 8 | (c >> 16 & 0xFF)
	}
}
