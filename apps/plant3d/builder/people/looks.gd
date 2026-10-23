## The people's looks (docs/PLANT3D.md §18.2): generic plant staff in work clothes and PPE, ours and invented (no
## plant's uniform, neutral colours): a white hard hat, a blue coverall with reflective tape and a hi-vis vest for the
## plant's own staff; the roles told apart by the vest's colour and what they carry; the contractors in grey with a
## blue hat, the HSE officers with a green one. Eight looks, so the posed band needs at most 8 × 6 MultiMeshes
## (docs/PLANT3D.md §18.4: ≤ 50 draw calls). The build writes them to built/people/people.json; the app picks a
## person's look by their role.
extends RefCounted

const WHITE_HAT := Color(0.93, 0.93, 0.9)
const SUIT := Color(0.17, 0.26, 0.42)        # a blue coverall
const TAPE := Color(0.80, 0.82, 0.82)        # reflective tape (silver)
const ORANGE := Color(0.93, 0.46, 0.12)
const LIME := Color(0.78, 0.88, 0.18)
const BASE := {"suit": SUIT, "tape": TAPE, "hat": WHITE_HAT, "boots": Color(0.13, 0.12, 0.11),
	"gloves": Color(0.33, 0.32, 0.29), "glasses": Color(0.24, 0.27, 0.30), "ear": Color(0.22, 0.22, 0.23),
	"skin": Color(0.70, 0.53, 0.41)}

const LOOKS := {
	"operator": {"vest": ORANGE, "carry": ["radio"], "skin": Color(0.64, 0.47, 0.35)},
	"ic": {"vest": LIME, "carry": ["bag", "radio"], "skin": Color(0.74, 0.57, 0.45)},
	"mech": {"vest": LIME, "carry": ["belt"], "skin": Color(0.55, 0.40, 0.30), "build": 1.08},
	"elec": {"vest": LIME, "carry": ["belt", "radio"], "gloves": Color(0.52, 0.36, 0.18), "skin": Color(0.68, 0.50, 0.38)},
	"supervisor": {"vest": ORANGE, "carry": ["clipboard", "radio"], "skin": Color(0.60, 0.44, 0.33), "build": 1.05},
	"manager": {"vest": LIME, "shirt": Color(0.86, 0.87, 0.88), "suit": Color(0.24, 0.25, 0.29), "carry": [],
		"gloves": Color(0.70, 0.53, 0.41), "skin": Color(0.70, 0.53, 0.41), "ear": false},
	"hse": {"vest": LIME, "hat": Color(0.22, 0.55, 0.28), "carry": ["clipboard", "radio"], "skin": Color(0.66, 0.49, 0.37)},
	"contractor": {"vest": ORANGE, "hat": Color(0.18, 0.36, 0.70), "suit": Color(0.42, 0.43, 0.42), "carry": ["belt"],
		"skin": Color(0.50, 0.36, 0.27), "build": 1.04},
}

## Every role of docs/plant3d/STAFF.md to its look.
const ROLE_LOOK := {
	"shift_sup": "supervisor", "ccr_op": "operator", "field_op": "operator", "elec_ap": "elec", "wtp_op": "operator",
	"shift_chem": "supervisor", "guard": "manager", "ic_tech": "ic", "ic_eng": "supervisor", "mech_tech": "mech",
	"mech_eng": "supervisor", "elec_tech": "elec", "elec_eng": "supervisor", "maint_sup": "supervisor",
	"chemist": "supervisor", "hse_officer": "hse", "plant_mgr": "manager", "ops_mgr": "manager", "maint_mgr": "manager",
	"contractor_sup": "contractor", "contractor": "contractor", "store": "mech", "driver": "manager", "camp": "manager",
}

## A look's full description for builder/people/body.gd: its colours and what it carries.
static func look(id: String) -> Dictionary:
	var l: Dictionary = LOOKS[id]
	var c := BASE.duplicate()
	for k in ["suit", "hat", "gloves", "skin", "vest", "shirt"]:
		if l.has(k):
			c[k] = l[k]
	if l.has("ear") and l.ear is Color:
		c.ear = l.ear
	return {"id": id, "colours": c, "carry": l.get("carry", []), "build": l.get("build", 1.0),
		"ear": not (l.has("ear") and l.ear is bool and not l.ear)}
