# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

**Bush Master of SPLORR!!**, a new game by TheGrumpyGameDev, started November 11, 2026. The user's brief, in their words: "its about gathering berries from bushes. the screen has a small fenced in plot of land, and starts with one berry bush on it that has berries to collect. you control a person (the bush master) and collect berries from the bush and deposit them in a basket in the corner. the bushes regenerate berries over time. you get jools every time you deposit a berry in the basket."

Numbers the brief did not give were picked by Claude for the first build and are the user's to change: a bush holds 5 berries and regrows one every 3 seconds, the bush master holds 5 at first, a jool a berry, a 14 by 9 plot. They are the tuning constants at the top of `src/game/game.odin`.

**Controls (the user's rule, November 11, 2026): only arrows or WASD, Space for OK and Esc to cancel** (the gamepad's d-pad, A and B and the touch pads give the same six). No click-to-walk, no number keys, no extra buttons; keep it that way. (F for the feedback form is the vault's standing rule and stays.)

The shop (November 11, 2026, the user's request) is **a $ tile in the plot's top-right corner**: walk into it and a menu opens; Up/Down choose, Space buys (the menu stays open), Esc or the Leave row closes it. An earlier side panel with 1/2 keys and clickable rows was rejected by the user the same day. It sells **bigger hands** (+1 berry carried, dearer with each one) and **a new bush** (planted bare in the next of eight fixed spots, dearer with each one). The user first asked for a better price per berry too, then took it out the same day: **a price-per-berry upgrade is reserved for a metacurrency once there is a prestige mechanic**, so do not put it in the shop. Prices are Claude's placeholders, at the top of `src/game/shop.odin`: hands start at 10 jools and each costs 3/2 of the last (30 at most); bushes start at 50 and double.

**Energy, the bed and the mortgage** (November 11, 2026, the user's design; `src/game/home.odin`). Each berry picked and each trip to the basket costs energy (100 a day; 1 each, Claude's placeholders), and **standing still drains it, so energy is the day's clock** (the user, November 11, 2026: 1 every 2 seconds without a step, Claude's placeholder; paused while the shop menu or a notice is up). Walking and shopping are free. **The shop sells more energy** (the user's answer to the balance problem, November 11, 2026): +20 a day per upgrade, 30 jools then 6/5 of the last, 60 at most; it also tops up today. With too little energy the bush master cannot pick or sell and must go to bed: **the bed is in the plot's bottom-left corner**, walk into it to sleep. A night ends the day: energy and the bushes are full again, and the night's interest is added. **The mortgage is 1,000,000 jools at 10% a year, charged nightly as a 365th (rounded up) and compounding.** It is paid from the shop menu's "Pay mortgage" row, Left and Right choosing 10, 100, 1,000, 10,000, 100,000 or all. **Paying it to zero wins**: a "Paid off!" notice, then play goes on. The user's answers on November 11, 2026: interest 10% a year per night; pay from a shop row with a chosen amount; a growing balance has no penalty, paying it off wins; energy is spent on picks and deposits.

The vault at `/home/yermom/git/bok-of-splorr/splorr/` is the shared body of knowledge for all SPLORR!! games and holds the standing rules. Read its `Home.md` first. This game's note is `Games/Bush Master of SPLORR!!.md`; when a fact about the game changes, update that note and its `Home.md` row too. `Gotchas.md` there has the wasm and Odin lessons.

## Commands

```bash
tools/test.sh                  # native tests (odin test, one thread), wasm checks of both packages, then a real wasm build
tools/build.sh [--size]        # wasm build into build/web (--size for shipping)
tools/serve.sh                 # build and serve on http://localhost:${PORT:-8000}/
tools/pages.sh                 # tests, size build, copy into docs/ for GitHub Pages; never commits or pushes
./shippit.sh [--push]          # tests, size build, zip; butler push to itch.io only with --push (only on the user's "ship")
python3 -I tools/extract_gfx.py [--sheet out.png]  # regenerate src/game/gfx.odin and font.odin (add tiles to PICKS)
python3 -I tools/make_cover.py # regenerate the placeholder assets/cover.png
tools/make_shots.sh            # render a real frame natively: assets/screenshots/01-play.png and assets/portal.png
```

The browser pane's launch config `bush-master-web` (port 8769, in the vault's `.claude/launch.json` and this repo's) serves `build/web`; run `tools/build.sh` first.

## Architecture

Odin compiled to `js_wasm32`, a 384 by 216 software framebuffer of Sweetie-16 palette indices drawn to a canvas (no WebGL), as in the vault's `Tech/Odin wasm recipe.md`. Real time: odin.js calls `step` with the frame's seconds, and `game.tick` grows berries, floats the "+1"s and walks clicked routes (dt is clamped to 0.25 s, so a hidden tab does not regrow a burst).

- `src/game/` is the pure rules package (no `core:os`, no `core:fmt`): `game.odin` (tuning, `Game`, `Command`, moving, picking, depositing, the $ tile, `tick`, `itoa`, saves as the raw `Game` bytes with `SAVE_VERSION`; add new fields at the end of `Game` and keep the older sizes loading, as `SAVE_V1_SIZE`, `SAVE_V2_SIZE`, `SAVE_V3_SIZE` and `SAVE_V4_SIZE` do; removed fields stay as `unused_*` so the layout holds), `shop.odin` (the shop: `Shop_Item`, prices, `buy`, `BUSH_SPOTS`, the menu's commands and rows, `PAY_ROW`), `home.odin` (energy, `energy_max`, the idle drain, the bed, nights, interest, `PAY_STEPS`, paying, the morning and paid-off notices), `render.odin` (the plot, fence, bushes with a dot per berry, basket, the $ tile, the bed, the tallies (jools, held, day, energy bar, owed), hints, the shop menu and the notices), `screen.odin` (framebuffer, palette, `Gfx` enum, drawing and text). `gfx.odin` and `font.odin` are generated by `tools/extract_gfx.py`; never hand-edit them. Tests are `*_test.odin` with `#+build !js` first; `dump_test.odin` writes a frame with `-define:DUMP_PLAY=<path.ppm>`.
- `src/web/web.odin` (`package main`, `#+build js`) is the thin browser layer, imported as `tggd:game` (`-collection:tggd=src`).
- `web/index.html` maps the arrows, WASD, Space (OK) and Esc (Cancel), the gamepad (d-pad or stick, A OK, B cancel) and the touch pads (a d-pad, OK and Back, shown on the first touch) to `platform_command`; F opens the feedback form. The canvas takes no clicks. The `Command` order there must match `game.odin`. The footer holds the credits, the AI disclosure, the back links, "Start over" and the "Send feedback" link; the LootLocker game is not set up yet (the user's console setup), so the form cannot send until `domain` and `key` are filled in.

## Standing rules (full text in the vault's `Home.md`)

- **"Push" means `git push`; "ship" means itch.io.** Do neither unless the user says that word. One ship a day through Coxswain (`ship_today` before, `ship_complete` after); scheduling is not permission.
- **GitHub Pages first.** The repo is public (`playdeezgames/bush-master-of-splorr`). **Pages is live since November 11, 2026** at https://playdeezgames.github.io/bush-master-of-splorr/, served from `main` `/docs`, and the game is on the portal (oeuvre-of-splorr). To update it: `tools/pages.sh`, commit `docs/`, push (each push needs the user's go-ahead).
- **Release standard** from the start (`Tech/Release standard.md`).
- **Public repo: no 1-Bit Kingdom art**, ever. Keep every licence record and credit.
- If the ROM font 8x8 turns up, ask the user before replacing it (DINOBYTE first, then Public Pixel).
- In player-facing text and itch copy the game is a **"Metaphor"**, never a "Game", and the voice says **"yer"**, never "your" or "you're".
- Do not describe or "fix" deliberate design as a problem once the user has decided it.
- Anything an AI agent posts on itch.io says it was posted by an AI agent.
