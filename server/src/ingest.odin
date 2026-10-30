package main

import "core:encoding/json"
import "core:fmt"
import "core:sync"
import "core:time"

import db "../lib/db"

SCHEMA_VERSION :: 1
MAX_RECORDS_PER_BATCH :: 500
MAX_MEMBERS :: 64
MAX_DEVICES :: 64

// ---- wire format ---------------------------------------------------------

Client_Payload :: struct {
	id:          string,
	name:        string,
	app_version: string,
	platform:    string,
	lang:        string,
}

Device_Payload :: struct {
	id:        string,
	name:      string,
	last_seen: i64,
}

Member_Payload :: struct {
	id:         string,
	name:       string,
	avatar:     string,
	color:      int,
	updated_at: i64,
}

Goal_Payload :: struct {
	cleared:    bool,
	member_id:  string,
	kg:         f64,
	updated_at: i64,
}

Record_Payload :: struct {
	t:  i64,
	kg: f64,
	m:  string,
	d:  string,
}

Ingest_Request :: struct {
	schema_version: int,
	client:         Client_Payload,
	devices:        []Device_Payload,
	members:        []Member_Payload,
	goal:           Goal_Payload,
	records:        []Record_Payload,
}

Rejected :: struct {
	index:  int,
	reason: string,
}

Ingest_Response :: struct {
	ok:          bool,
	batch_id:    string,
	accepted:    int,
	duplicates:  int,
	rejected:    [dynamic]Rejected,
	duplicate:   bool,
	server_time: i64,
}

Apply_Outcome :: struct {
	accepted:        int,
	duplicates:      int,
	rejected:        [dynamic]Rejected,
	duplicate_batch: bool,
	error:           string,
}

// ---- helpers -------------------------------------------------------------

now_ms :: proc() -> i64 {
	return time.to_unix_nanoseconds(time.now()) / (1000 * 1000)
}

valid_key :: proc(s: string, max_len: int) -> bool {
	if len(s) == 0 || len(s) > max_len {
		return false
	}
	for i in 0 ..< len(s) {
		c := s[i]
		ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		ok = ok || c == '-' || c == '_' || c == ':' || c == '.' || c == '|'
		if !ok {
			return false
		}
	}
	return true
}

valid_weight :: proc(kg: f64) -> bool {
	return kg > 0 && kg <= 500
}

// record_uid is content-derived: replaying the same measurement from the same
// client (even in a different batch) yields the same primary key.
record_uid :: proc(client_id, member_id, device_id: string, ts_ms: i64, kg: f64) -> string {
	buf: [512]byte
	canonical := fmt.bprintf(
		buf[:],
		"litescale/record/v1\n%s\n%s\n%s\n%d\n%.3f",
		client_id,
		member_id,
		device_id,
		ts_ms,
		kg,
	)
	return sha256_hex(transmute([]byte)canonical)
}

// ---- persistence ---------------------------------------------------------

Batch_Row :: struct {
	accepted:   int,
	duplicates: int,
	found:      bool,
}

find_batch :: proc(conn: ^db.Conn, batch_id: string) -> Batch_Row {
	stmt := db.prepare(conn, "SELECT accepted, duplicates FROM batches WHERE id = ?1")
	if stmt == nil {
		return Batch_Row{}
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, batch_id)
	if db.step(stmt) != db.SQLITE_ROW {
		return Batch_Row{}
	}
	return Batch_Row {
		accepted   = db.col_int(stmt, 0),
		duplicates = db.col_int(stmt, 1),
		found      = true,
	}
}

upsert_client_profile :: proc(conn: ^db.Conn, c: Client_Payload, at: i64) -> bool {
	stmt := db.prepare(
		conn,
		`INSERT INTO clients (id, name, app_version, platform, lang, token_hash, created_at, last_seen_at)
		 VALUES (?1, ?2, ?3, ?4, ?5, '', ?6, ?6)
		 ON CONFLICT(id) DO UPDATE SET
		   name = excluded.name,
		   app_version = excluded.app_version,
		   platform = excluded.platform,
		   lang = excluded.lang,
		   last_seen_at = excluded.last_seen_at`,
	)
	if stmt == nil {
		return false
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, c.id)
	db.bind_text(stmt, 2, c.name)
	db.bind_text(stmt, 3, c.app_version)
	db.bind_text(stmt, 4, c.platform)
	db.bind_text(stmt, 5, c.lang)
	db.bind_int64(stmt, 6, at)
	return db.step(stmt) == db.SQLITE_DONE
}

upsert_member :: proc(conn: ^db.Conn, client_id: string, m: Member_Payload, at: i64) -> bool {
	stmt := db.prepare(
		conn,
		`INSERT INTO members (client_id, id, name, avatar, color, updated_at)
		 VALUES (?1, ?2, ?3, ?4, ?5, ?6)
		 ON CONFLICT(client_id, id) DO UPDATE SET
		   name = excluded.name,
		   avatar = excluded.avatar,
		   color = excluded.color,
		   updated_at = excluded.updated_at`,
	)
	if stmt == nil {
		return false
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, client_id)
	db.bind_text(stmt, 2, m.id)
	db.bind_text(stmt, 3, m.name)
	db.bind_text(stmt, 4, m.avatar)
	db.bind_int(stmt, 5, m.color)
	db.bind_int64(stmt, 6, at)
	return db.step(stmt) == db.SQLITE_DONE
}

upsert_device :: proc(conn: ^db.Conn, client_id: string, d: Device_Payload) -> bool {
	stmt := db.prepare(
		conn,
		`INSERT INTO devices (client_id, id, name, last_seen)
		 VALUES (?1, ?2, ?3, ?4)
		 ON CONFLICT(client_id, id) DO UPDATE SET
		   name = excluded.name,
		   last_seen = MAX(devices.last_seen, excluded.last_seen)`,
	)
	if stmt == nil {
		return false
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, client_id)
	db.bind_text(stmt, 2, d.id)
	db.bind_text(stmt, 3, d.name)
	db.bind_int64(stmt, 4, d.last_seen)
	return db.step(stmt) == db.SQLITE_DONE
}

member_exists :: proc(conn: ^db.Conn, client_id, member_id: string) -> bool {
	stmt := db.prepare(conn, "SELECT 1 FROM members WHERE client_id = ?1 AND id = ?2")
	if stmt == nil {
		return false
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, client_id)
	db.bind_text(stmt, 2, member_id)
	return db.step(stmt) == db.SQLITE_ROW
}

find_client :: proc(conn: ^db.Conn, client_id: string) -> bool {
	stmt := db.prepare(conn, "SELECT 1 FROM clients WHERE id = ?1")
	if stmt == nil {
		return false
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, client_id)
	return db.step(stmt) == db.SQLITE_ROW
}

validate_ingest :: proc(req: ^Ingest_Request) -> string {
	if req.schema_version != SCHEMA_VERSION {
		return "unsupported schema_version"
	}
	if !valid_key(req.client.id, 64) {
		return "invalid client.id"
	}
	if len(req.members) > MAX_MEMBERS {
		return "too many members"
	}
	if len(req.devices) > MAX_DEVICES {
		return "too many devices"
	}
	if len(req.records) > MAX_RECORDS_PER_BATCH {
		return "too many records"
	}
	return ""
}

// apply_ingest writes one batch in a single transaction. The batch key is
// checked under the write lock, so a concurrent retry of the same key either
// waits and sees the completed batch, or wins and writes exactly once.
apply_ingest :: proc(
	cid: string,
	req: ^Ingest_Request,
	batch_id, sha: string,
) -> (
	out: Apply_Outcome,
) {
	conn := &G.conn
	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	if !db.exec(conn, "BEGIN IMMEDIATE") {
		out.error = db.last_error(conn)
		return
	}
	committed := false
	defer {
		if !committed {
			db.exec(conn, "ROLLBACK")
		}
	}

	if existing := find_batch(conn, batch_id); existing.found {
		db.exec(conn, "ROLLBACK")
		committed = true
		out.duplicate_batch = true
		out.accepted = existing.accepted
		out.duplicates = existing.duplicates
		return
	}

	at := now_ms()

	if !upsert_client_profile(conn, req.client, at) {
		out.error = db.last_error(conn)
		return
	}

	for m in req.members {
		if !valid_key(m.id, 64) || len(m.name) > 128 {
			continue
		}
		updated := m.updated_at
		if updated <= 0 {
			updated = at
		}
		if !upsert_member(conn, cid, m, updated) {
			out.error = db.last_error(conn)
			return
		}
	}

	for d in req.devices {
		if !valid_key(d.id, 128) || len(d.name) > 128 {
			continue
		}
		seen := d.last_seen
		if seen <= 0 {
			seen = at
		}
		if !upsert_device(conn, cid, Device_Payload{id = d.id, name = d.name, last_seen = seen}) {
			out.error = db.last_error(conn)
			return
		}
	}

	if req.goal.cleared {
		stmt := db.prepare(conn, "DELETE FROM goals WHERE client_id = ?1")
		if stmt == nil {
			out.error = db.last_error(conn)
			return
		}
		db.bind_text(stmt, 1, cid)
		db.step(stmt)
		db.finalize(stmt)
	} else if valid_weight(req.goal.kg) {
		updated := req.goal.updated_at
		if updated <= 0 {
			updated = at
		}
		stmt := db.prepare(
			conn,
			`INSERT INTO goals (client_id, member_id, kg, updated_at)
			 VALUES (?1, ?2, ?3, ?4)
			 ON CONFLICT(client_id) DO UPDATE SET
			   member_id = excluded.member_id,
			   kg = excluded.kg,
			   updated_at = excluded.updated_at`,
		)
		if stmt == nil {
			out.error = db.last_error(conn)
			return
		}
		db.bind_text(stmt, 1, cid)
		if req.goal.member_id == "" {
			db.bind_null(stmt, 2)
		} else {
			db.bind_text(stmt, 2, req.goal.member_id)
		}
		db.bind_double(stmt, 3, req.goal.kg)
		db.bind_int64(stmt, 4, updated)
		if db.step(stmt) != db.SQLITE_DONE {
			out.error = db.last_error(conn)
			db.finalize(stmt)
			return
		}
		db.finalize(stmt)
	}

	ins := db.prepare(
		conn,
		`INSERT INTO measurements (uid, client_id, member_id, device_id, ts_ms, kg, received_at, batch_id)
		 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
		 ON CONFLICT(uid) DO NOTHING`,
	)
	if ins == nil {
		out.error = db.last_error(conn)
		return
	}
	defer db.finalize(ins)

	member_known: map[string]bool
	defer delete(member_known)

	min_ts := i64(946684800000) // 2000-01-01
	future := at + 24 * 60 * 60 * 1000

	for r, i in req.records {
		if r.m == "" || !valid_key(r.m, 64) {
			append(&out.rejected, Rejected{index = i, reason = "invalid member id"})
			continue
		}
		if r.t < min_ts || r.t > future {
			append(&out.rejected, Rejected{index = i, reason = "timestamp out of range"})
			continue
		}
		if !valid_weight(r.kg) {
			append(&out.rejected, Rejected{index = i, reason = "weight out of range"})
			continue
		}
		if r.d != "" && !valid_key(r.d, 128) {
			append(&out.rejected, Rejected{index = i, reason = "invalid device id"})
			continue
		}

		known, cached := member_known[r.m]
		if !cached {
			known = member_exists(conn, cid, r.m)
			member_known[r.m] = known
		}
		if !known {
			append(&out.rejected, Rejected{index = i, reason = "unknown member"})
			continue
		}

		uid := record_uid(cid, r.m, r.d, r.t, r.kg)
		defer delete(uid)
		db.reset(ins)
		db.bind_text(ins, 1, uid)
		db.bind_text(ins, 2, cid)
		db.bind_text(ins, 3, r.m)
		if r.d == "" {
			db.bind_null(ins, 4)
		} else {
			db.bind_text(ins, 4, r.d)
		}
		db.bind_int64(ins, 5, r.t)
		db.bind_double(ins, 6, r.kg)
		db.bind_int64(ins, 7, at)
		db.bind_text(ins, 8, batch_id)
		if db.step(ins) != db.SQLITE_DONE {
			out.error = db.last_error(conn)
			return
		}
		if db.changes(conn) == 1 {
			out.accepted += 1
		} else {
			out.duplicates += 1
		}
	}

	bstmt := db.prepare(
		conn,
		`INSERT INTO batches (id, client_id, received_at, payload_sha256, records, accepted, duplicates)
		 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
	)
	if bstmt == nil {
		out.error = db.last_error(conn)
		return
	}
	db.bind_text(bstmt, 1, batch_id)
	db.bind_text(bstmt, 2, cid)
	db.bind_int64(bstmt, 3, at)
	db.bind_text(bstmt, 4, sha)
	db.bind_int(bstmt, 5, len(req.records))
	db.bind_int(bstmt, 6, out.accepted)
	db.bind_int(bstmt, 7, out.duplicates)
	code := db.step(bstmt)
	db.finalize(bstmt)
	if code != db.SQLITE_DONE {
		out.error = db.last_error(conn)
		return
	}

	if !db.exec(conn, "COMMIT") {
		out.error = db.last_error(conn)
		return
	}
	committed = true
	return
}

// sql_escape is only used for the fixed bootstrap INSERT above, which has no
// bindable alias for its literal columns. Values still go through bind_text
// everywhere else.
sql_escape :: proc(s: string) -> string {
	buf := make([dynamic]byte, 0, len(s), context.temp_allocator)
	for i in 0 ..< len(s) {
		if s[i] == '\'' {
			append(&buf, '\'')
		}
		append(&buf, s[i])
	}
	return string(buf[:])
}

// decode_ingest parses the request body; the caller owns nothing extra.
decode_ingest :: proc(body: []byte) -> (req: Ingest_Request, err: string) {
	jerr := json.unmarshal(body, &req)
	if jerr != nil {
		return req, "invalid JSON body"
	}
	return req, ""
}
