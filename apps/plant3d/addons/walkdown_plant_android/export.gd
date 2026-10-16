## The Android export's link into the app (docs/PLANT3D.md §6, decision 0054 §3 and 0056): an activity alias of
## Godot's activity that other apps may start with a walkdown-plant:// URI (VIEW, also from a browser). The URI then
## is the activity's Intent, which ui/links_in.gd reads through Godot's AndroidRuntime plugin. Godot adds this to the
## manifest only in a Gradle build, so the Android presets use one.
@tool
extends EditorExportPlugin

const SCHEME := "walkdown-plant"


func _get_name() -> String:
	return "WalkdownPlantLinks"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return ("<activity-alias android:name=\".WalkdownPlantLink\" android:targetActivity=\".GodotApp\" "
		+ "android:exported=\"true\">\n"
		+ "    <intent-filter>\n"
		+ "        <action android:name=\"android.intent.action.VIEW\" />\n"
		+ "        <category android:name=\"android.intent.category.DEFAULT\" />\n"
		+ "        <category android:name=\"android.intent.category.BROWSABLE\" />\n"
		+ "        <data android:scheme=\"%s\" />\n" % SCHEME
		+ "    </intent-filter>\n"
		+ "</activity-alias>\n")
