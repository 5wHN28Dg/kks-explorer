## The test runner's own check (tests/run_tests.gd): a test function stopped by a script error must count as
## failed. This one errors on purpose.
extends RefCounted

func run(_tree: SceneTree) -> Array:
	var x = null
	x.call("no_such_method")
	return []
