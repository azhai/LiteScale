package main

// Illustrated avatars bundled from assets/avatars (client repo).
AVATAR_PNGS := [48]string{
	string(#load("ui/avatars/a01.png")),
	string(#load("ui/avatars/a02.png")),
	string(#load("ui/avatars/a03.png")),
	string(#load("ui/avatars/a04.png")),
	string(#load("ui/avatars/a05.png")),
	string(#load("ui/avatars/a06.png")),
	string(#load("ui/avatars/a07.png")),
	string(#load("ui/avatars/a08.png")),
	string(#load("ui/avatars/a09.png")),
	string(#load("ui/avatars/a10.png")),
	string(#load("ui/avatars/a11.png")),
	string(#load("ui/avatars/a12.png")),
	string(#load("ui/avatars/a13.png")),
	string(#load("ui/avatars/a14.png")),
	string(#load("ui/avatars/a15.png")),
	string(#load("ui/avatars/a16.png")),
	string(#load("ui/avatars/a17.png")),
	string(#load("ui/avatars/a18.png")),
	string(#load("ui/avatars/a19.png")),
	string(#load("ui/avatars/a20.png")),
	string(#load("ui/avatars/a21.png")),
	string(#load("ui/avatars/a22.png")),
	string(#load("ui/avatars/a23.png")),
	string(#load("ui/avatars/a24.png")),
	string(#load("ui/avatars/a25.png")),
	string(#load("ui/avatars/a26.png")),
	string(#load("ui/avatars/a27.png")),
	string(#load("ui/avatars/a28.png")),
	string(#load("ui/avatars/a29.png")),
	string(#load("ui/avatars/a30.png")),
	string(#load("ui/avatars/a31.png")),
	string(#load("ui/avatars/a32.png")),
	string(#load("ui/avatars/a33.png")),
	string(#load("ui/avatars/a34.png")),
	string(#load("ui/avatars/a35.png")),
	string(#load("ui/avatars/a36.png")),
	string(#load("ui/avatars/a37.png")),
	string(#load("ui/avatars/a38.png")),
	string(#load("ui/avatars/a39.png")),
	string(#load("ui/avatars/a40.png")),
	string(#load("ui/avatars/a41.png")),
	string(#load("ui/avatars/a42.png")),
	string(#load("ui/avatars/a43.png")),
	string(#load("ui/avatars/a44.png")),
	string(#load("ui/avatars/a45.png")),
	string(#load("ui/avatars/a46.png")),
	string(#load("ui/avatars/a47.png")),
	string(#load("ui/avatars/a48.png")),
}

// avatar_png returns the embedded PNG for ids a01..a48; empty when unknown.
avatar_png :: proc(id: string) -> string {
	if len(id) != 3 || id[0] != 'a' {
		return ""
	}
	if id[1] < '0' || id[1] > '9' || id[2] < '0' || id[2] > '9' {
		return ""
	}
	n := int(id[1] - '0') * 10 + int(id[2] - '0') - 1
	if n < 0 || n >= len(AVATAR_PNGS) {
		return ""
	}
	return AVATAR_PNGS[n]
}
