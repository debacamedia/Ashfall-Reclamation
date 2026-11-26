class_name StoryRadio
extends Interactable
## Northwatch's radio in the command post (Increment 34): the last order of
## Act 1, "Answer the radio". It only answers once the rest of Chapter 5 is
## done (Northwatch taken and claimed, an Armorer at work, all three places
## held); before that, and in Free Play, it's static.

signal answered(by: PlayerController, line: String)


func _ready() -> void:
	action_name = "Answer"
	object_name = "the radio"
	hold_time = 1.0


func get_prompt(interactor: Node3D) -> String:
	return "Answer the radio" if _ready_for(interactor) else "Radio: static"


func get_block_reason(interactor: Node3D) -> String:
	var p := interactor as PlayerController
	if p == null or p.story == null or not p.story.is_story():
		return "Only static on every channel"
	if p.story.is_done(&"radio"):
		return "Only static now"
	return "" if _ready_for(interactor) else "Only static. Hold Northwatch, and all three places, first"


## Is the rest of Chapter 5 done?
static func _ready_for(interactor: Node3D) -> bool:
	var p := interactor as PlayerController
	if p == null or p.story == null or not p.story.is_story() or p.story.is_done(&"radio"):
		return false
	var c := p.story.current_chapter()
	if c.is_empty() or c["id"] != &"northwatch":
		return false
	for o: Dictionary in c["orders"]:
		if o["id"] != &"radio" and not p.story.is_done(o["id"]):
			return false
	return true


## What the radio says to you.
static func line_for(p: PlayerController) -> String:
	return "The radio crackles: \"Unit 17, this is Command. %s, is that you? You are cleared to proceed east. Report to Scorch.\"" % p.call_name()


func _perform(interactor: Node3D) -> void:
	var p := interactor as PlayerController
	if p == null or not _ready_for(p):
		return
	p.story.answered_radio(line_for(p))
	answered.emit(p, line_for(p))
