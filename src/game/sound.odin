package game

// Sound effects (the user, November 12, 2026: sound effects, and a way to mute them). The rules
// queue a Sound when something happens; the page plays the queue each frame with small synthesised
// blips (web/index.html, SOUNDS, in this enum's order) and empties it. Muting is the rules' job: a
// muted game queues nothing. Mute is in the Esc menu.

Sound :: enum u8 {
	Pick, // the bush master picked a berry
	Sell, // dropped a load in the basket
	Full, // hands full
	Tired, // not enough energy
	Buy, // bought something in the shop
	Deny, // can't afford it
	Move, // a menu cursor moved
	Open, // a menu opened
	Close, // a menu or notice closed
	Sleep, // went to bed
	Pay, // paid some of the mortgage
	Paid_Off, // paid it all
	Robot_Pick, // a robot picked (quieter)
	Robot_Sell, // a robot sold (quieter)
	Reset, // started over
}

SOUND_CAP :: 16

play :: proc(g: ^Game, s: Sound) {
	if g.muted || g.sound_count >= SOUND_CAP {
		return
	}
	g.sounds[g.sound_count] = s
	g.sound_count += 1
}
