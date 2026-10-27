## The invite's QR code (docs/plant3d/MULTIPLAYER.md §1.1, net/qr.gd): the matrices our encoder makes equal those of an
## independent encoder (the Python package qrcode 8.2, byte mode, level M) for the same text, version and mask; the
## version and mask it
## chooses itself for the invite link; the text too long for version 10 refused. (Scanned by the Note 9's camera app
## and by zxing-cpp on the laptop: MULTIPLAYER.md §1.1 "As built".)
extends RefCounted

const QR = preload("res://net/qr.gd")

# [text, version, mask, the rows as hex numbers, most significant bit the leftmost module] from
#   q = qrcode.QRCode(version=V, error_correction=ERROR_CORRECT_M, border=0, mask_pattern=K)
#   q.add_data(QRData(text.encode(), mode=MODE_8BIT_BYTE), optimize=0); q.make(fit=False); q.get_matrix()
# (segno 1.6.6 adds a zero codeword when byte mode's stream already ends on a codeword boundary, which ISO/IEC 18004
# 7.4.10 doesn't ask for: its matrices differ in the data, so it is not the reference here)
const GOLDEN := [
	['walkdown-plant://join/K3QX9F2MHT4C7PW5', 3, 2, "1fc57d7f 104aed41 175f635d 175bbe5d 175f725d 10527c41 1fd5557f 175300 17c8327c 69a83f7 9ecf57c 139d80da b736205 12083b7b 1a402510 49277a8 afc3e86 1c25cb7f 137ae4dc 140bb2d9 137c73fc 163519 1fc92b5c 105d671b 17540df4 175df3af 1750bff6 104cb572 1fd98064"],
	['walkdown-plant://join/K3QX9F2MHT4C7PW5', 3, 5, "1fc3a67f 1052cd41 175f635d 1757cf5d 174f725d 104a5c41 1fd5557f 1f7300 105832ce 186f230 9ecf57c 1195a058 6c5b968 10001bf9 1a402510 38e066f afc3e86 1e2debfd 1ecc3fb1 1603925b 137c73fc 1a451e 1fc92b5c 10454719 1742d7f9 1745d32d 1740bff6 1040c4b5 1fd98064"],
	['Walkdown Plant Walkdown Plant Walkdown Plant Walkdown Plant Walkdown Plant Walkdown Plant Walkdown Plant Walkdown Plant Walkdown Plant Walkdown Plant ', 8, 6, "1fd928544797f 105b815a15f41 1751ddc4f4b5d 17429b73bba5d 175295ff6085d 104baac6a1441 1fd555555557f 4a3c560000 13f763fd6da97 1d00719ddcfd7 1a55188870151 12c4fec35c3f 26c439195e1b 5986c36496cc fec475719f9f 1d1e02fe7bdee f72f8d4797fd 4b47eb24fbd6 6fdecf8bb985 1c21a581830e9 64befbd07989 172505a76dfd4 ff09dfeaf3f9 9136a447651c 175608d51d359 111899c7ea51c 1df2817e1bffd 1ea64ef04863c 1c4e612cfbe4c b89d8114f805 16cc0f3c59875 e975799a0118 7ea0901657fb 6b7f779dcdbb 164aba4cbca59 18a0d394da2af 15fdc86ddf6eb 521015cf975f 8cf5b00cbfcf e35566c4afdd 1c6cd0fc797ff 1c5a456c912 1fd73f54b8951 105141456631a 175b0b7d43dfb 1756fd35ecc8b 174321168c8be 104c7e78babff 1fd1a675193a1"],
	['x', 1, 0, "1fc47f 105141 17405d 17425d 17595d 104541 1fd57f f00 154612 89846 6e111 150c46 125554 1aa9 1fcaef 104fb8 1752ed 174846 175111 104846 1fd157"],
]

var fails := []


func run(_tree) -> Array:
	for g in GOLDEN:
		var q := QR.encode(g[0], g[2], g[1])
		if q.is_empty() or q["version"] != g[1] or q["mask"] != g[2]:
			fails.append("%s: version %s mask %s" % [g[0].left(20), str(q.get("version")), str(q.get("mask"))])
			continue
		var n: int = q["size"]
		var rows: PackedStringArray = g[3].split(" ")
		if rows.size() != n:
			fails.append("%s: %d rows, not %d" % [g[0].left(20), rows.size(), n])
			continue
		var differs := 0
		for y in n:
			var v := rows[y].hex_to_int()
			for x in n:
				if q["modules"][y * n + x] != (v >> (n - 1 - x)) & 1:
					differs += 1
		if differs > 0:
			fails.append("%s v%d mask %d: %d modules differ" % [g[0].left(20), g[1], g[2], differs])
	var link := QR.encode("walkdown-plant://join/K3QX9F2MHT4C7PW5")
	if link.get("version") != 3:
		fails.append("the invite link: version %s, not 3" % str(link.get("version")))
	if not QR.encode("x".repeat(300)).is_empty():
		fails.append("a text too long for version 10 is refused")
	var img := QR.image(link, 4)
	if img.get_width() != (29 + 8) * 4:
		fails.append("the image's size")
	return fails
