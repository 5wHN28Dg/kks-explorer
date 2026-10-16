## Procedure text (docs/PLANT3D.md §8: runs and blocks of docs/COURSES.md §3–§4) as BBCode for a RichTextLabel.
## Content text is escaped (it never makes markup); links become [url] tags with our own targets: `kks:CODE`,
## `course:ID` or `course:ID/PAGE`, `page:ID`.
extends RefCounted


static func esc(s: String) -> String:
	return s.replace("[", "[lb]")


static func run(r) -> String:
	if typeof(r) == TYPE_STRING:
		return esc(r)
	if typeof(r) != TYPE_ARRAY:
		return ""
	var out := ""
	for it in r:
		if typeof(it) == TYPE_STRING:
			out += esc(it)
		elif typeof(it) == TYPE_DICTIONARY:
			if it.has("b"):
				out += "[b]%s[/b]" % run(it["b"])
			elif it.has("i"):
				out += "[i]%s[/i]" % run(it["i"])
			elif it.has("small"):
				out += "[font_size=15]%s[/font_size]" % run(it["small"])
			elif it.has("num"):
				out += "[code]%s[/code]" % esc(String(it["num"]))
			elif it.has("term"):
				out += run(it["term"])
			elif it.has("link"):
				out += "[url=%s][color=#7fc8ff]%s[/color][/url]" % [target(it.get("to", {})), run(it["link"])]
	return out


static func target(to: Dictionary) -> String:
	if to.has("kks"):
		return "kks:" + String(to["kks"])
	if to.has("course"):
		return "course:" + String(to["course"]) + (("/" + String(to["page"])) if to.has("page") else "")
	if to.has("page"):
		return "page:" + String(to["page"])
	if to.has("url"):
		return "url:" + String(to["url"])
	return ""


static func blocks(bs) -> String:
	if typeof(bs) != TYPE_ARRAY:
		return ""
	var out := PackedStringArray()
	for b in bs:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		if b.has("p"):
			out.append(run(b["p"]))
		elif b.has("h"):
			out.append("[b]%s[/b]" % run(b["h"]))
		elif b.has("ul") or b.has("ol"):
			var items: Array = b.get("ul", b.get("ol", []))
			var lines := PackedStringArray()
			for k in items.size():
				lines.append(("• " if b.has("ul") else "%d. " % (k + 1)) + run(items[k]))
			out.append("\n".join(lines))
		elif b.has("callout"):
			out.append("[b]%s[/b]\n%s" % [run(b.get("label", [])), blocks(b.get("body", []))])
		elif b.has("table"):
			var t: Dictionary = b["table"]
			var rows := PackedStringArray()
			rows.append(" | ".join(t.get("head", []).map(func(c): return "[b]%s[/b]" % run(c))))
			for row in t.get("rows", []):
				rows.append(" | ".join(row.map(func(c): return run(c))))
			out.append("\n".join(rows))
		elif b.has("chain"):
			out.append(" → ".join(b["chain"].map(func(c): return run(c))))
		elif b.has("cards"):
			out.append("\n".join(b["cards"].map(func(c): return "[b]%s[/b]: %s" % [run(c[0]), run(c[1])])))
	return "\n\n".join(out)


## The codes a run links to, in order (the step's equipment to point at).
static func codes(r) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(r) != TYPE_ARRAY:
		return out
	for it in r:
		if typeof(it) == TYPE_DICTIONARY and it.has("link") and it.get("to", {}).has("kks"):
			out.append(it["to"]["kks"])
	return out
