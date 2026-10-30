package main

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"

import web "../vendor/opus"
import oboe "../vendor/oboe"
import db "../lib/db"

State :: struct {
	cfg:          Config,
	conn:         db.Conn,
	mu:           sync.Mutex,
	cache:        ^oboe.Cache,
	log_store:    ^oboe.Store,
	log_fields:   []string,
	admin_token:  string,
	router:       web.Router,
	srv:          web.Server,
}

G: State

Error_Body :: struct {
	error: string,
}

fail :: proc(res: ^web.Response, status: web.Status, message: string) {
	web.response_json_status(res, status, Error_Body{error = message})
}

// ---- auth ----------------------------------------------------------------

bearer_token :: proc(req: ^web.Request) -> (string, bool) {
	auth, ok := web.request_header(req, "Authorization")
	if !ok {
		return "", false
	}
	prefix := "Bearer "
	if len(auth) <= len(prefix) || !strings.equal_fold(auth[:len(prefix)], prefix) {
		return "", false
	}
	token := strings.trim_space(auth[len(prefix):])
	if token == "" {
		return "", false
	}
	return token, true
}

// authenticate maps a Bearer token to a client id. The returned string is
// heap-allocated for the caller.
authenticate :: proc(req: ^web.Request) -> (string, bool) {
	token, ok := bearer_token(req)
	if !ok {
		return "", false
	}
	hash := sha256_hex_str(token)
	defer delete(hash)

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	stmt := db.prepare(&G.conn, "SELECT id FROM clients WHERE token_hash = ?1 AND token_hash <> ''")
	if stmt == nil {
		return "", false
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, hash)
	if db.step(stmt) != db.SQLITE_ROW {
		return "", false
	}
	return db.col_text_dup(stmt, 0, context.allocator), true
}

authenticate_admin :: proc(req: ^web.Request) -> bool {
	if G.admin_token == "" {
		return false
	}
	token, ok := bearer_token(req)
	if !ok {
		return false
	}
	return strings.equal_fold(token, G.admin_token)
}

// ---- rate limit ----------------------------------------------------------

RATE_LIMIT_PER_MINUTE :: 120

// opus' Status enum has no 429 entry; the reason phrase falls back to
// "Unknown", which is legal on the wire and the code is what clients read.
RATE_LIMITED :: web.Status(429)

rate_limited :: proc(client_id: string) -> bool {
	if G.cache == nil {
		return false
	}
	key := fmt.tprintf("rl:%s:%d", client_id, now_ms() / 60000)
	value, found := oboe.cache_get(G.cache, key)
	count := 0
	if found {
		s := string(value)
		if n, ok := strconv.parse_int(s); ok {
			count = n
		}
		delete(value)
	}
	if count >= RATE_LIMIT_PER_MINUTE {
		return true
	}
	next := fmt.tprintf("%d", count + 1)
	oboe.cache_set(G.cache, key, transmute([]byte)next, i64(120 * time.Second))
	return false
}

// ---- client endpoints ----------------------------------------------------

Ping_Response :: struct {
	ok:          bool,
	service:     string,
	version:     string,
	server_time: i64,
}

handle_ping :: proc(req: ^web.Request, res: ^web.Response) {
	web.response_json_status(
		res,
		.OK,
		Ping_Response{ok = true, service = "litescale", version = VERSION, server_time = now_ms()},
	)
}

Register_Request :: struct {
	id:          string,
	name:        string,
	app_version: string,
	platform:    string,
	lang:        string,
}

Register_Response :: struct {
	ok:        bool,
	client_id: string,
	token:     string,
}

handle_register :: proc(req: ^web.Request, res: ^web.Response) {
	if G.cfg.enroll_key != "" {
		key, ok := web.request_header(req, "X-Enroll-Key")
		if !ok || !strings.equal_fold(key, G.cfg.enroll_key) {
			fail(res, .Unauthorized, "invalid enroll key")
			return
		}
	}

	payload: Register_Request
	if len(req.body) == 0 || json_unmarshal(req.body, &payload) != "" {
		fail(res, .Bad_Request, "invalid JSON body")
		return
	}
	if !valid_key(payload.id, 64) {
		fail(res, .Bad_Request, "invalid client id")
		return
	}
	if len(payload.name) > 128 || len(payload.app_version) > 64 || len(payload.platform) > 32 || len(payload.lang) > 16 {
		fail(res, .Bad_Request, "field too long")
		return
	}

	token := random_hex(32)
	if token == "" {
		fail(res, .Internal_Error, "cannot generate token")
		return
	}
	hash := sha256_hex_str(token)
	defer delete(hash)

	at := now_ms()
	sync.lock(&G.mu)
	stmt := db.prepare(
		&G.conn,
		`INSERT INTO clients (id, name, app_version, platform, lang, token_hash, created_at, last_seen_at)
		 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)
		 ON CONFLICT(id) DO UPDATE SET
		   name = excluded.name,
		   app_version = excluded.app_version,
		   platform = excluded.platform,
		   lang = excluded.lang,
		   token_hash = excluded.token_hash,
		   last_seen_at = excluded.last_seen_at`,
	)
	if stmt == nil {
		db_error := db.last_error(&G.conn)
		sync.unlock(&G.mu)
		fmt.eprintfln("register: %s", db_error)
		fail(res, .Internal_Error, "database error")
		return
	}
	db.bind_text(stmt, 1, payload.id)
	db.bind_text(stmt, 2, payload.name)
	db.bind_text(stmt, 3, payload.app_version)
	db.bind_text(stmt, 4, payload.platform)
	db.bind_text(stmt, 5, payload.lang)
	db.bind_text(stmt, 6, hash)
	db.bind_int64(stmt, 7, at)
	code := db.step(stmt)
	db.finalize(stmt)
	sync.unlock(&G.mu)

	if code != db.SQLITE_DONE {
		fail(res, .Internal_Error, "database error")
		return
	}

	web.response_json_status(
		res,
		.OK,
		Register_Response{ok = true, client_id = payload.id, token = token},
	)
}

handle_ingest :: proc(req: ^web.Request, res: ^web.Response) {
	if len(req.body) == 0 {
		fail(res, .Bad_Request, "empty body")
		return
	}
	if len(req.body) > G.cfg.max_body {
		fail(res, .Payload_Too_Large, "batch too large")
		return
	}

	batch_id, ok := web.request_header(req, "X-Idempotency-Key")
	if !ok || len(batch_id) < 8 || len(batch_id) > 128 || !valid_key(batch_id, 128) {
		fail(res, .Bad_Request, "missing or invalid X-Idempotency-Key")
		return
	}

	want_sha, sha_ok := web.request_header(req, "X-Body-Sha256")
	if !sha_ok || len(want_sha) != 64 {
		fail(res, .Bad_Request, "missing X-Body-Sha256")
		return
	}
	actual_sha := sha256_hex(req.body)
	defer delete(actual_sha)
	if !strings.equal_fold(actual_sha, want_sha) {
		fail(res, .Bad_Request, "checksum mismatch")
		return
	}

	client_id, authed := authenticate(req)
	if !authed {
		fail(res, .Unauthorized, "invalid token")
		return
	}
	defer delete(client_id)

	if rate_limited(client_id) {
		fail(res, RATE_LIMITED, "rate limit exceeded")
		return
	}

	payload, perr := decode_ingest(req.body)
	if perr != "" {
		fail(res, .Bad_Request, perr)
		return
	}
	if payload.client.id != client_id {
		fail(res, .Forbidden, "client id does not match token")
		return
	}
	if vmsg := validate_ingest(&payload); vmsg != "" {
		fail(res, .Bad_Request, vmsg)
		return
	}

	outcome := apply_ingest(client_id, &payload, batch_id, actual_sha)
	defer delete(outcome.rejected)

	if outcome.error != "" {
		fmt.eprintfln("ingest %s: %s", batch_id, outcome.error)
		fail(res, .Internal_Error, "database error")
		return
	}

	if !outcome.duplicate_batch {
		log_ingest(client_id, batch_id, actual_sha, &payload, outcome.accepted, outcome.duplicates)
	}

	web.response_json_status(
		res,
		.OK,
		Ingest_Response {
			ok = true,
			batch_id = batch_id,
			accepted = outcome.accepted,
			duplicates = outcome.duplicates,
			rejected = outcome.rejected,
			duplicate = outcome.duplicate_batch,
			server_time = now_ms(),
		},
	)
}

Me_Response :: struct {
	ok:           bool,
	client_id:    string,
	measurements: int,
	members:      int,
	devices:      int,
	last_ts:      i64,
}

handle_me :: proc(req: ^web.Request, res: ^web.Response) {
	client_id, ok := authenticate(req)
	if !ok {
		fail(res, .Unauthorized, "invalid token")
		return
	}
	defer delete(client_id)

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	stmt := db.prepare(
		&G.conn,
		`SELECT
		   (SELECT COUNT(*) FROM measurements WHERE client_id = ?1),
		   (SELECT COUNT(*) FROM members WHERE client_id = ?1),
		   (SELECT COUNT(*) FROM devices WHERE client_id = ?1),
		   COALESCE((SELECT MAX(ts_ms) FROM measurements WHERE client_id = ?1), 0)`,
	)
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, client_id)
	if db.step(stmt) != db.SQLITE_ROW {
		fail(res, .Internal_Error, "database error")
		return
	}
	web.response_json_status(
		res,
		.OK,
		Me_Response {
			ok = true,
			client_id = client_id,
			measurements = db.col_int(stmt, 0),
			members = db.col_int(stmt, 1),
			devices = db.col_int(stmt, 2),
			last_ts = db.col_int64(stmt, 3),
		},
	)
}

json_unmarshal :: proc(body: []byte, v: ^$T) -> string {
	err := json.unmarshal(body, v)
	if err != nil {
		return "invalid JSON body"
	}
	return ""
}

not_found :: proc(req: ^web.Request, res: ^web.Response) {
	fail(res, .Not_Found, "not found")
}

register_routes :: proc() {
	web.router_init(&G.router)
	G.router.not_found = not_found

	web.router_get(&G.router, "/api/v1/ping", handle_ping)
	web.router_post(&G.router, "/api/v1/clients", handle_register)
	web.router_post(&G.router, "/api/v1/ingest", handle_ingest)
	web.router_get(&G.router, "/api/v1/clients/me", handle_me)

	register_admin_routes()
}

// ---- raw batch log (oboe) ------------------------------------------------

log_ingest :: proc(
	client_id, batch_id, sha: string,
	payload: ^Ingest_Request,
	accepted, duplicates: int,
) {
	if G.log_store == nil {
		return
	}
	fields := []oboe.Field {
		{name = "client_id", value = client_id},
		{name = "batch_id", value = batch_id},
		{name = "sha256", value = sha},
		{name = "records", value = fmt.tprintf("%d", len(payload.records))},
		{name = "accepted", value = fmt.tprintf("%d", accepted)},
		{name = "duplicates", value = fmt.tprintf("%d", duplicates)},
		{name = "platform", value = payload.client.platform},
		{name = "app_version", value = payload.client.app_version},
	}
	stream := oboe.compute_stream_id(fields, G.log_fields)
	rows := []oboe.Ingest_Row {
		{
			ts = time.to_unix_nanoseconds(time.now()),
			stream = stream,
			msg = "weight-ingest",
			fields = fields,
		},
	}
	oboe.store_ingest(G.log_store, rows)
}
