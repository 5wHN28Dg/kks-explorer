## A door (docs/PLANT3D.md §5): opens when someone walks up to it or presses it, closes again a few seconds after
## they have gone. Roller doors go up, personnel and double doors slide aside. Made by the content build.
extends AnimatableBody3D

@export var kind := "personnel"
@export var width := 1.0
@export var height := 2.1

const NEAR := 2.0        # metres from the door's centre line at which it opens for a walker
const SPEED := 1.5       # metres a second
const HOLD := 3.0        # seconds it stays open after the walker has gone

var openness := 0.0      # 0 closed, 1 open
var hold := 0.0
var closed_xf: Transform3D
var moving := false      # running open or shut: the sounds (ui/sound_player.gd, group plant_sounds) hear it

func _ready() -> void:
	closed_xf = transform
	sync_to_physics = true

## Opens the door now (the trainee pressed it), and keeps it open for a while.
func press() -> void:
	hold = HOLD

func _physics_process(delta: float) -> void:
	var want := false
	for p in get_tree().get_nodes_in_group("walkers"):
		var local: Vector3 = closed_xf.affine_inverse() * (p as Node3D).global_position
		if absf(local.x) < width * 0.5 + 1.0 and absf(local.z) < NEAR and local.y > -1.0 and local.y < height:
			want = true
			hold = HOLD
	if not want and hold > 0.0:
		hold -= delta   # pressed, or walked away from: open a while longer
		want = hold > 0.0
	var was := openness
	openness = move_toward(openness, 1.0 if want else 0.0, SPEED * delta / maxf(height if kind == "roller" else width, 0.5))
	var now := openness != was
	if now != moving:
		moving = now
		get_tree().call_group("plant_sounds", "door_moving", self, moving)
	var off := Vector3(0, openness * height, 0) if kind == "roller" else Vector3(openness * width, 0, 0)
	transform = closed_xf.translated_local(off)
