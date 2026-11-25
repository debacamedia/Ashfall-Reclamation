class_name FieldManualText
extends RefCounted
## The Reclamation Field Manual's pages (Increment 33): Outpost 17's issue
## copy of how to stay alive out here, one chapter per system, annotated in
## red pen by its last owner, Sgt. Ada Vance.
##
## Text is BBCode for a RichTextLabel. Keys are written {action} (an input
## map action) and drawn from the player's real bindings, so the manual can't
## name the wrong key. Vance's notes are ((like this)).
##
## Chapters 1-4 are open from the start. 5-7 open the first time you need
## them (FieldManualProgress): the story will open them later too.

const HAND_FONT := "res://assets/fonts/caveat-latin-700-normal.woff2"
const TYPE_FONT := "res://assets/fonts/special-elite-latin-400-normal.woff2"
const INK := "#2b2418"
const PEN := "#a3261c"
const KEY_BG := "#3a3122"
const KEY_FG := "#f1e8cf"

## The cover's note.
const COVER_NOTE := "If you're reading this, I'm not coming back for it. Keep it dry.  — A.V."
const COVER_TITLE := "Reclamation\nField Manual"
const COVER_SUB := "Outpost 17 · Issue copy · Not to leave the post"

## Keys whose names Godot spells out.
const KEY_SHORT := {"BracketLeft": "[", "BracketRight": "]", "Equal": "=", "Minus": "-", "Escape": "Esc",
	"QuoteLeft": "`", "Apostrophe": "'", "Semicolon": ";", "Comma": ",", "Period": ".", "Slash": "/", "Backslash": "\\",
	"Control": "Ctrl", "Command": "Cmd"}

## Mouse buttons by index, for keys bound to the mouse.
const MOUSE_NAMES := {MOUSE_BUTTON_LEFT: "Left click", MOUSE_BUTTON_RIGHT: "Right click", MOUSE_BUTTON_MIDDLE: "Middle click",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down"}

## Each chapter: id, number, title, the page it starts on, whether it's open
## from the start, and its text.
const CHAPTERS := [
	{
		"id": &"staying_alive", "n": 1, "title": "Staying alive", "page": 3, "open": true,
		"text": """[b]Health[/b] doesn't come back by itself. A [b]Bandage[/b] gives back 20, a [b]Medkit[/b] 40. Press {use_medkit} to use the best one you carry, or put them on your quick bar, take one in hand and {fire}.

[b]Food[/b] runs down over about forty minutes, three times as fast when you sprint. [b]Peckish[/b] is a warning. [b]Hungry[/b], you can't sprint. [b]Starving[/b], you slow down and your health drains, though hunger alone won't finish you. Press {eat} to eat the best thing you carry. Canned food turns up in lockers and on raiders; vegetables grow at farms; stew is cooked on a stove.

((Beans before bullets. Trust me.))

[b]The ash storm[/b] closes in at the edge of the land. The air turns orange, you're warned, and then it burns. Turn back. Where a road runs out through it there's a gap you can follow.

[b]If you fall,[/b] everything you carried waits where you went down, in a chest marked [i]Your Gear[/i], on your compass and your map, with a light over it. You come back at the post with your blade and this manual. Walk back for the rest before anything else does.

((Twice. Don't ask.))""",
	},
	{
		"id": &"scavenging", "n": 2, "title": "Scavenging", "page": 7, "open": true,
		"text": """[b]Search[/b] lockers, crates and cabinets: hold {interact} until it opens, then take what you want, or press {take_all} for everything that fits. What's been taken stays taken. Nothing out here refills.

[b]Break down[/b] pallets, furniture and scrap heaps: hold {interact} on them. The materials go straight into your pack: Wood, Scrap Metal, Cloth and the rest. They're what everything else is made of.

[b]Your pack[/b] ({inventory}) has slots and a weight it can carry. Drag things to move or stack them, right-click to use or wear them, and drag them outside the window to drop them.

[b]Bigger packs[/b] carry more: the [b]Satchel[/b] you start with (30 kg), a [b]Rucksack[/b] made by hand (40 kg), a [b]Military Pack[/b] from a military store (50 kg) and a [b]Frame Pack[/b] from a workbench (60 kg). The Frame Pack rattles: crouch ({crouch}) and raiders won't hear it.

((The quartermaster at Northwatch kept the good packs. Check his crate.))""",
	},
	{
		"id": &"making_things", "n": 3, "title": "Making things", "page": 10, "open": true,
		"text": """[b]By hand[/b] ({crafting}): planks from wood, bandages from cloth, pistol rounds, a pipe pistol, a rucksack, barricades, a ladder, even a field workbench. The list shows what you have the makings for, and what's missing for the rest.

[b]At a workbench[/b] (a W on your map) you can make more: kits to build with, medkits, pistol rounds and shotgun shells, gunpowder, armour, the frame pack, and the metal parts everything else needs: pipes, plate and springs. Stand at it and press {crafting}. It mends what you wear, too.

[b]At a weapons bench[/b] (a G) you make guns from their parts (barrel, receiver, stock, trigger group, magazine), rifle rounds, and attachments: sights, scopes, suppressors, foregrips. Fit and take them off there.

[b]Cooking[/b] needs a stove (an S) or a workbench, and every dish burns a Wood Plank. Stew fills you far more than what went into it.

((Make rounds before you need them. You'll need them.))""",
	},
	{
		"id": &"guns_and_fighting", "n": 4, "title": "Guns and fighting", "page": 14, "open": true,
		"text": """[b]Your quick bar[/b] is the row of eight slots along the bottom: {weapon_1} to {weapon_8}, or the wheel. Put anything you can hold there: guns, blades, medkits, food, this manual. Drag them up from your pack ({inventory}), or right-click a gun to put it on. Two of the same gun is fine; each keeps its own rounds and attachments.

[b]Fire[/b] with {fire}, [b]aim[/b] with {aim}, [b]reload[/b] with {reload}. Rounds stay in your pack: no rounds, no reload. Your blade never runs dry.

[b]Raiders[/b] come at you with blades. Keep your distance and keep moving. [b]Raider Veterans[/b] take more killing; further east, [b]Scorch Marauders[/b] wear plate that turns a quarter of what hits them. Crouch ({crouch}) to move quietly. A raider who hasn't heard you hasn't seen you either.

[b]Armour[/b] (head, body, legs) takes a share off every hit and wears down as it does. Mend it at a workbench before it's worn through.

((Count your rounds. They don't count themselves.))""",
	},
	{
		"id": &"building", "n": 5, "title": "Building", "page": 18, "open": false,
		"text": """[b]Build mode[/b] ({build_mode}) shows what you can put up. Make kits at a workbench first: walls, doors, floors, stairs, platforms. Click to place; {build_next} and {build_previous} or the wheel choose; {build_variant} changes the variant, {build_rotate} rotates, {build_move} moves something you've built, {interact} repairs it and {build_dismantle} takes it down for scrap.

[b]What you build stands:[/b] it's saved, it blocks raiders, and raiders can break it. Mend it before it falls.

[b]Inside a place you hold,[/b] build mode also plans settlement buildings: a bunkhouse, a storehouse, guard posts and towers, a kitchen, pens. You lay out where they go; Builders put them up with the materials you bring or leave in the stores.

((Walls first. Then the gate. Then the tower to see over both.))""",
	},
	{
		"id": &"settlements", "n": 6, "title": "Settlements", "page": 22, "open": false,
		"text": """[b]Claiming a place:[/b] clear out its raiders, then hold {interact} at its notice board. Once it's yours its raiders stop coming, and it shows green on your compass and map.

[b]People[/b] turn up when there's a free bed and food to spare, and survivors you meet out in the world come if you ask. Give each a job on the settlement screen ({settlement}): Farmer, Guard, Builder, Woodcutter, Cook, Rancher, Miner, Armorer, Tailor. Some need a place to work first.

[b]Water and food:[/b] get the pump working, then farmers grow food on the water. Everyone eats a meal every four hours. Unfed, they stop working; left hungry, they leave.

[b]Raids[/b] come every couple of days, with warning. Guards fight from their posts and towers; everyone else shelters. Arm your guards with guns and rounds, from your pack or an Armory Locker. Anyone who goes down can be helped up with a bandage. Raids come whether you're there or not.

[b]The supply line:[/b] hold two places and they share materials, guns and rounds. Food is split between them by the shares you set.

((Water first. Then people. Then walls.))""",
	},
	{
		"id": &"getting_around", "n": 7, "title": "Getting around", "page": 27, "open": false,
		"text": """[b]The compass[/b] at the top shows the places you know, your gear, your truck, your pins and any raid on its way.

[b]The map[/b] ({map}) fills in as you go, and you see further from up high. Right-click to drop a numbered pin; pins show on the compass too.

[b]The truck[/b] waits in the post's motor pool. {interact} at the driver's door gets in. {move_forward} and {move_back} drive and brake, {move_left} and {move_right} steer, {jump} is the handbrake, {camera_toggle} changes the view and {interact} gets you out. Its bed carries far more than you can. It runs on fuel: hold {interact} at the fuel cap with a Fuel Can (10 litres).

[b]Leaving:[/b] the road east out of Halden's Crossing runs through a gap in the storm to the country beyond. Drive through it and the truck comes with you.

((The radio mast at Northwatch still blinks. Somebody's keeping it lit.))""",
	},
]


## The chapter with `id`, or {}.
static func chapter(id: StringName) -> Dictionary:
	for c: Dictionary in CHAPTERS:
		if c["id"] == id:
			return c
	return {}


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for c: Dictionary in CHAPTERS:
		out.append(c["id"])
	return out


## Every {action} named in the manual.
static func actions_named() -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string("\\{([a-z_0-9]+)\\}")
	for c: Dictionary in CHAPTERS:
		for m in re.search_all(c["text"]):
			if not out.has(m.get_string(1)):
				out.append(m.get_string(1))
	return out


## What `action` is bound to, as a player would say it ("E", "Left click").
static func key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var names := PackedStringArray()
	for e in InputMap.action_get_events(action):
		var n := ""
		if e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			n = OS.get_keycode_string(code)
			n = KEY_SHORT.get(n, n)
		elif e is InputEventMouseButton:
			n = MOUSE_NAMES.get((e as InputEventMouseButton).button_index, "Mouse")
		if n != "" and not names.has(n):
			names.append(n)
		if names.size() == 2:
			break
	return " / ".join(names) if not names.is_empty() else "?"


## A chapter's text ready for a RichTextLabel: keys drawn as keycaps, Vance's
## notes in red pen.
static func render(text: String) -> String:
	var re := RegEx.create_from_string("\\{([a-z_0-9]+)\\}")
	var out := text.replace("\n\n", "\n")
	for m in re.search_all(text):
		out = out.replace(m.get_string(0), "[bgcolor=%s][color=%s] %s [/color][/bgcolor]" % [KEY_BG, KEY_FG, key_name(m.get_string(1))])
	var notes := RegEx.create_from_string("\\(\\((.+?)\\)\\)")
	for m in notes.search_all(out):
		out = out.replace(m.get_string(0), "[indent][font=%s][font_size=26][color=%s]%s[/color][/font_size][/font][/indent]" % [HAND_FONT, PEN, m.get_string(1)])
	return out
