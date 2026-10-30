package main

import "core:crypto/sha2"
import "core:encoding/hex"
import "core:os"

// hex_encode allocates; the caller owns the result.
hex_encode :: proc(data: []byte) -> string {
	res := hex.encode(data)
	return string(res)
}

// sha256_hex allocates; the caller owns the result.
sha256_hex :: proc(data: []byte) -> string {
	digest: [sha2.DIGEST_SIZE_256]byte
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	sha2.final(&ctx, digest[:])
	return hex_encode(digest[:])
}

// sha256_hex_str is sha256_hex for callers that already hold a string.
sha256_hex_str :: proc(s: string) -> string {
	return sha256_hex(transmute([]byte)s)
}

// random_hex reads bytes from the OS CSPRNG (/dev/urandom, macOS/Linux).
random_hex :: proc(n: int) -> string {
	f, err := os.open("/dev/urandom", os.O_RDONLY)
	if err != nil {
		return ""
	}
	defer os.close(f)

	buf := make([]byte, n)
	defer delete(buf)
	got := 0
	for got < n {
		k, rerr := os.read(f, buf[got:])
		if rerr != nil || k <= 0 {
			return ""
		}
		got += k
	}
	return hex_encode(buf)
}
