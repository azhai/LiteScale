package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:sync"

import web "../vendor/opus"
import db "../lib/db"

ADMIN_HTML :: string(#load("ui/index.html"))
ADMIN_JS :: string(#load("ui/alpine.min.js"))

// ---- static assets -------------------------------------------------------

handle_admin_index :: proc(req: ^web.Request, res: ^web.Response) {
	web.response_set_header(res, "Content-Type", "text/html; charset=utf-8")
	web.response_set_header(res, "Cache-Control", "no-store")
	web.response_write_string(res, ADMIN_HTML)
}

handle_admin_js :: proc(req: ^web.Request, res: ^web.Response) {
	web.response_set_header(res, "Content-Type", "text/javascript; charset=utf-8")
	web.response_set_header(res, "Cache-Control", "public, max-age=86400")
	web.response_write_string(res, ADMIN_JS)
}

handle_admin_avatar :: proc(req: ^web.Request, res: ^web.Response) {
	id, has := web.request_param(req, "id")
	if !has {
		fail(res, .Bad_Request, "missing avatar id")
		return
	}
	png := avatar_png(id)
	if png == "" {
		fail(res, .Not_Found, "unknown avatar")
		return
	}
	web.response_set_header(res, "Content-Type", "image/png")
	web.response_set_header(res, "Cache-Control", "public, max-age=86400")
	web.response_write_string(res, png)
}

handle_root :: proc(req: ^web.Request, res: ^web.Response) {
	web.response_redirect(res, "/admin/")
}

// ---- shapes --------------------------------------------------------------

Overview_Response :: struct {
	ok:            bool,
	version:       string,
	server_time:   i64,
	clients:       int,
	devices:       int,
	members:       int,
	measurements:  int,
	goals:         int,
	batches:       int,
	db_bytes:      i64,
	last_batch_at: i64,
}

Client_Row :: struct {
	id:           string,
	name:         string,
	platform:     string,
	app_version:  string,
	lang:         string,
	created_at:   i64,
	last_seen_at: i64,
	measurements: int,
	members:      int,
	devices:      int,
	last_kg:      f64,
	last_ts:      i64,
}

Clients_Response :: struct {
	ok:     bool,
	total:  int,
	limit:  int,
	offset: int,
	items:  [dynamic]Client_Row,
}

Member_Row :: struct {
	id:           string,
	name:         string,
	avatar:       string,
	color:        int,
	height_cm:    f64,
	gender:       string,
	birth:        string,
	updated_at:   i64,
	measurements: int,
	goals:        int,
}

Device_Row :: struct {
	id:        string,
	name:      string,
	last_seen: i64,
}

Goal_Row :: struct {
	set:        bool,
	member_id:  string,
	kg:         f64,
	updated_at: i64,
}

Member_Goal_Row :: struct {
	member_id:   string,
	member_name: string,
	date:        string,
	target_kg:   f64,
	actual_kg:   f64,
	updated_at:  i64,
}

Client_Stats :: struct {
	measurements: int,
	first_ts:     i64,
	last_ts:      i64,
	last_kg:      f64,
}

Client_Detail_Response :: struct {
	ok:      bool,
	client:  Client_Row,
	members: [dynamic]Member_Row,
	devices: [dynamic]Device_Row,
	goal:    Goal_Row,
	goals:   [dynamic]Member_Goal_Row,
	stats:   Client_Stats,
}

Measurement_Row :: struct {
	uid:         string,
	client_id:   string,
	member_id:   string,
	member_name: string,
	device_id:   string,
	device_name: string,
	ts_ms:       i64,
	kg:          f64,
	received_at: i64,
	batch_id:    string,
}

Measurements_Response :: struct {
	ok:     bool,
	total:  int,
	limit:  int,
	offset: int,
	items:  [dynamic]Measurement_Row,
}

Batch_Out :: struct {
	id:             string,
	client_id:      string,
	received_at:    i64,
	payload_sha256: string,
	records:        int,
	accepted:       int,
	duplicates:     int,
}

Batches_Response :: struct {
	ok:     bool,
	total:  int,
	limit:  int,
	offset: int,
	items:  [dynamic]Batch_Out,
}

Action_Response :: struct {
	ok:      bool,
	deleted: int,
}

Measurement_Update :: struct {
	ts_ms:     i64,
	kg:        f64,
	member_id: string,
}

Measurement_Update_Response :: struct {
	ok:  bool,
	uid: string,
}

Bulk_Delete_Request :: struct {
	uids: []string,
}

Import_Response :: struct {
	ok:              bool,
	total:           int,
	imported:        int,
	duplicates:      int,
	members_created: int,
	rejected:        [dynamic]Rejected,
}

// ---- query helpers -------------------------------------------------------

query_value :: proc(req: ^web.Request, key: string) -> string {
	v, _ := web.request_query(req, key)
	return v
}

query_int :: proc(req: ^web.Request, key: string, fallback: int) -> int {
	v := query_value(req, key)
	if v == "" {
		return fallback
	}
	n, ok := strconv.parse_int(v)
	if !ok {
		return fallback
	}
	return n
}

query_i64 :: proc(req: ^web.Request, key: string) -> i64 {
	v := query_value(req, key)
	if v == "" {
		return 0
	}
	n, ok := strconv.parse_i64(v)
	if !ok {
		return 0
	}
	return n
}

// pragma_int reads a one-column PRAGMA. The caller must already hold G.mu or
// be the only writer on the connection.
pragma_int :: proc(name: string) -> i64 {
	stmt := db.prepare(&G.conn, strings.concatenate({"PRAGMA ", name}, context.temp_allocator))
	if stmt == nil {
		return 0
	}
	defer db.finalize(stmt)
	if db.step(stmt) != db.SQLITE_ROW {
		return 0
	}
	return db.col_int64(stmt, 0)
}

// ---- filter args ---------------------------------------------------------

Arg_Kind :: enum {
	Text,
	Int,
}

Arg :: struct {
	kind: Arg_Kind,
	text: string,
	num:  i64,
}

bind_args :: proc(stmt: ^db.Stmt, args: []Arg) -> int {
	idx := 1
	for a in args {
		switch a.kind {
		case .Text:
			db.bind_text(stmt, idx, a.text)
		case .Int:
			db.bind_int64(stmt, idx, a.num)
		}
		idx += 1
	}
	return idx
}

where_add :: proc(sb: ^strings.Builder, first: ^bool, cond: string) {
	if first^ {
		strings.write_string(sb, " WHERE ")
		first^ = false
	} else {
		strings.write_string(sb, " AND ")
	}
	strings.write_string(sb, cond)
}

// ---- overview ------------------------------------------------------------

handle_admin_overview :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	out := Overview_Response {
		ok          = true,
		version     = VERSION,
		server_time = now_ms(),
	}
	stmt := db.prepare(
		&G.conn,
		`SELECT
		   (SELECT COUNT(*) FROM clients),
		   (SELECT COUNT(*) FROM devices),
		   (SELECT COUNT(*) FROM members),
		   (SELECT COUNT(*) FROM measurements),
		   (SELECT COUNT(*) FROM member_goals),
		   (SELECT COUNT(*) FROM batches),
		   COALESCE((SELECT MAX(received_at) FROM batches), 0)`,
	)
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	if db.step(stmt) == db.SQLITE_ROW {
		out.clients = db.col_int(stmt, 0)
		out.devices = db.col_int(stmt, 1)
		out.members = db.col_int(stmt, 2)
		out.measurements = db.col_int(stmt, 3)
		out.goals = db.col_int(stmt, 4)
		out.batches = db.col_int(stmt, 5)
		out.last_batch_at = db.col_int64(stmt, 6)
	}
	db.finalize(stmt)

	out.db_bytes = pragma_int("page_count") * pragma_int("page_size")

	web.response_json_status(res, .OK, out)
}

// ---- clients -------------------------------------------------------------

CLIENT_SELECT :: `SELECT c.id, c.name, c.platform, c.app_version, c.lang, c.created_at, c.last_seen_at,
	(SELECT COUNT(*) FROM measurements m WHERE m.client_id = c.id),
	(SELECT COUNT(*) FROM members mm WHERE mm.client_id = c.id),
	(SELECT COUNT(*) FROM devices dv WHERE dv.client_id = c.id),
	COALESCE((SELECT m.kg FROM measurements m WHERE m.client_id = c.id ORDER BY m.ts_ms DESC LIMIT 1), 0),
	COALESCE((SELECT m.ts_ms FROM measurements m WHERE m.client_id = c.id ORDER BY m.ts_ms DESC LIMIT 1), 0)
	FROM clients c`

CLIENT_WHERE_Q :: ` WHERE (?1 = '' OR c.id LIKE ?2 OR c.name LIKE ?2)`

read_client_row :: proc(stmt: ^db.Stmt) -> Client_Row {
	return Client_Row {
		id = db.col_text_dup(stmt, 0, context.temp_allocator),
		name = db.col_text_dup(stmt, 1, context.temp_allocator),
		platform = db.col_text_dup(stmt, 2, context.temp_allocator),
		app_version = db.col_text_dup(stmt, 3, context.temp_allocator),
		lang = db.col_text_dup(stmt, 4, context.temp_allocator),
		created_at = db.col_int64(stmt, 5),
		last_seen_at = db.col_int64(stmt, 6),
		measurements = db.col_int(stmt, 7),
		members = db.col_int(stmt, 8),
		devices = db.col_int(stmt, 9),
		last_kg = db.col_double(stmt, 10),
		last_ts = db.col_int64(stmt, 11),
	}
}

handle_admin_clients :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	limit := clamp(query_int(req, "limit", 50), 1, 500)
	offset := max(query_int(req, "offset", 0), 0)
	q := strings.trim_space(query_value(req, "q"))
	pattern := strings.concatenate({"%", q, "%"}, context.temp_allocator)

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	out := Clients_Response{ok = true, limit = limit, offset = offset}
	out.items = make([dynamic]Client_Row, 0, limit)

	cstmt := db.prepare(
		&G.conn,
		strings.concatenate({"SELECT COUNT(*) FROM clients c", CLIENT_WHERE_Q}, context.temp_allocator),
	)
	if cstmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	db.bind_text(cstmt, 1, q)
	db.bind_text(cstmt, 2, pattern)
	if db.step(cstmt) == db.SQLITE_ROW {
		out.total = db.col_int(cstmt, 0)
	}
	db.finalize(cstmt)

	stmt := db.prepare(
		&G.conn,
		strings.concatenate(
			{CLIENT_SELECT, CLIENT_WHERE_Q, " ORDER BY c.last_seen_at DESC LIMIT ?3 OFFSET ?4"},
			context.temp_allocator,
		),
	)
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, q)
	db.bind_text(stmt, 2, pattern)
	db.bind_int(stmt, 3, limit)
	db.bind_int(stmt, 4, offset)
	for db.step(stmt) == db.SQLITE_ROW {
		append(&out.items, read_client_row(stmt))
	}

	web.response_json_status(res, .OK, out)
}

handle_admin_client_detail :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	client_id, has := web.request_param(req, "id")
	if !has {
		fail(res, .Bad_Request, "missing client id")
		return
	}

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	out := Client_Detail_Response{ok = true}
	cstmt := db.prepare(
		&G.conn,
		strings.concatenate({CLIENT_SELECT, " WHERE c.id = ?1"}, context.temp_allocator),
	)
	if cstmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	db.bind_text(cstmt, 1, client_id)
	if db.step(cstmt) != db.SQLITE_ROW {
		db.finalize(cstmt)
		fail(res, .Not_Found, "client not found")
		return
	}
	out.client = read_client_row(cstmt)
	db.finalize(cstmt)

	out.members = make([dynamic]Member_Row, 0, 8)
	mstmt := db.prepare(
		&G.conn,
		`SELECT mm.id, mm.name, mm.avatar, mm.color, COALESCE(p.height_cm, 0),
		   COALESCE(dt.gender, ''), COALESCE(dt.birth, ''), mm.updated_at,
		   (SELECT COUNT(*) FROM measurements m WHERE m.client_id = ?1 AND m.member_id = mm.id),
		   (SELECT COUNT(*) FROM member_goals g WHERE g.client_id = ?1 AND g.member_id = mm.id)
		 FROM members mm
		 LEFT JOIN member_profiles p ON p.client_id = mm.client_id AND p.member_id = mm.id
		 LEFT JOIN member_details dt ON dt.client_id = mm.client_id AND dt.member_id = mm.id
		 WHERE mm.client_id = ?1 ORDER BY mm.updated_at`,
	)
	if mstmt != nil {
		db.bind_text(mstmt, 1, client_id)
		for db.step(mstmt) == db.SQLITE_ROW {
			append(
				&out.members,
				Member_Row {
					id = db.col_text_dup(mstmt, 0, context.temp_allocator),
					name = db.col_text_dup(mstmt, 1, context.temp_allocator),
					avatar = db.col_text_dup(mstmt, 2, context.temp_allocator),
					color = db.col_int(mstmt, 3),
					height_cm = db.col_double(mstmt, 4),
					gender = db.col_text_dup(mstmt, 5, context.temp_allocator),
					birth = db.col_text_dup(mstmt, 6, context.temp_allocator),
					updated_at = db.col_int64(mstmt, 7),
					measurements = db.col_int(mstmt, 8),
					goals = db.col_int(mstmt, 9),
				},
			)
		}
		db.finalize(mstmt)
	}

	out.devices = make([dynamic]Device_Row, 0, 8)
	dstmt := db.prepare(
		&G.conn,
		"SELECT id, name, last_seen FROM devices WHERE client_id = ?1 ORDER BY last_seen DESC",
	)
	if dstmt != nil {
		db.bind_text(dstmt, 1, client_id)
		for db.step(dstmt) == db.SQLITE_ROW {
			append(
				&out.devices,
				Device_Row {
					id = db.col_text_dup(dstmt, 0, context.temp_allocator),
					name = db.col_text_dup(dstmt, 1, context.temp_allocator),
					last_seen = db.col_int64(dstmt, 2),
				},
			)
		}
		db.finalize(dstmt)
	}

	gstmt := db.prepare(&G.conn, "SELECT member_id, kg, updated_at FROM goals WHERE client_id = ?1")
	if gstmt != nil {
		db.bind_text(gstmt, 1, client_id)
		if db.step(gstmt) == db.SQLITE_ROW {
			out.goal = Goal_Row {
				set        = true,
				member_id  = db.col_text_dup(gstmt, 0, context.temp_allocator),
				kg         = db.col_double(gstmt, 1),
				updated_at = db.col_int64(gstmt, 2),
			}
		}
		db.finalize(gstmt)
	}

	out.goals = make([dynamic]Member_Goal_Row, 0, 8)
	mgstmt := db.prepare(
		&G.conn,
		`SELECT g.member_id, COALESCE(mm.name, ''), g.date, g.target_kg, g.actual_kg, g.updated_at
		 FROM member_goals g
		 LEFT JOIN members mm ON mm.client_id = g.client_id AND mm.id = g.member_id
		 WHERE g.client_id = ?1 ORDER BY g.date, g.member_id`,
	)
	if mgstmt != nil {
		db.bind_text(mgstmt, 1, client_id)
		for db.step(mgstmt) == db.SQLITE_ROW {
			append(
				&out.goals,
				Member_Goal_Row {
					member_id = db.col_text_dup(mgstmt, 0, context.temp_allocator),
					member_name = db.col_text_dup(mgstmt, 1, context.temp_allocator),
					date = db.col_text_dup(mgstmt, 2, context.temp_allocator),
					target_kg = db.col_double(mgstmt, 3),
					actual_kg = db.col_double(mgstmt, 4),
					updated_at = db.col_int64(mgstmt, 5),
				},
			)
		}
		db.finalize(mgstmt)
	}

	sstmt := db.prepare(
		&G.conn,
		`SELECT COUNT(*), COALESCE(MIN(ts_ms), 0), COALESCE(MAX(ts_ms), 0),
		   COALESCE((SELECT kg FROM measurements WHERE client_id = ?1 ORDER BY ts_ms DESC LIMIT 1), 0)
		 FROM measurements WHERE client_id = ?1`,
	)
	if sstmt != nil {
		db.bind_text(sstmt, 1, client_id)
		if db.step(sstmt) == db.SQLITE_ROW {
			out.stats = Client_Stats {
				measurements = db.col_int(sstmt, 0),
				first_ts = db.col_int64(sstmt, 1),
				last_ts = db.col_int64(sstmt, 2),
				last_kg = db.col_double(sstmt, 3),
			}
		}
		db.finalize(sstmt)
	}

	web.response_json_status(res, .OK, out)
}

Member_Update :: struct {
	name:      string,
	avatar:    string,
	color:     int,
	height_cm: f64,
	gender:    string,
	birth:     string,
}

handle_admin_member_update :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	client_id, has_c := web.request_param(req, "cid")
	member_id, has_m := web.request_param(req, "mid")
	if !has_c || !has_m {
		fail(res, .Bad_Request, "missing ids")
		return
	}
	body: Member_Update
	if len(req.body) == 0 || json_unmarshal(req.body, &body) != "" {
		fail(res, .Bad_Request, "invalid JSON body")
		return
	}
	name := strings.trim_space(body.name)
	if len(name) == 0 || len(name) > 128 {
		fail(res, .Bad_Request, "invalid name")
		return
	}
	if body.height_cm < 0 || (body.height_cm != 0 && !valid_height(body.height_cm)) {
		fail(res, .Bad_Request, "height out of range")
		return
	}
	if !valid_gender(body.gender) {
		fail(res, .Bad_Request, "invalid gender")
		return
	}
	if body.birth != "" && !valid_birth_month(body.birth) {
		fail(res, .Bad_Request, "invalid birth month")
		return
	}

	at := now_ms()
	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)
	stmt := db.prepare(
		&G.conn,
		"UPDATE members SET name = ?3, avatar = ?4, color = ?5, updated_at = ?6 WHERE client_id = ?1 AND id = ?2",
	)
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, client_id)
	db.bind_text(stmt, 2, member_id)
	db.bind_text(stmt, 3, name)
	db.bind_text(stmt, 4, body.avatar)
	db.bind_int(stmt, 5, body.color)
	db.bind_int64(stmt, 6, at)
	if db.step(stmt) != db.SQLITE_DONE {
		fail(res, .Internal_Error, "database error")
		return
	}
	if db.changes(&G.conn) == 0 {
		fail(res, .Not_Found, "member not found")
		return
	}
	if body.height_cm > 0 {
		if !set_member_height(&G.conn, client_id, member_id, body.height_cm, at) {
			fail(res, .Internal_Error, "database error")
			return
		}
	} else {
		pstmt := db.prepare(
			&G.conn,
			"DELETE FROM member_profiles WHERE client_id = ?1 AND member_id = ?2",
		)
		if pstmt == nil {
			fail(res, .Internal_Error, "database error")
			return
		}
		db.bind_text(pstmt, 1, client_id)
		db.bind_text(pstmt, 2, member_id)
		ok := db.step(pstmt) == db.SQLITE_DONE
		db.finalize(pstmt)
		if !ok {
			fail(res, .Internal_Error, "database error")
			return
		}
	}
	if !set_member_details(&G.conn, client_id, member_id, body.gender, body.birth, at, true) {
		fail(res, .Internal_Error, "database error")
		return
	}
	web.response_json_status(res, .OK, Action_Response{ok = true, deleted = 1})
}

Goal_Update :: struct {
	cleared: bool,
	kg:      f64,
}

Member_Goal_Update :: struct {
	cleared: bool,
	kg:      f64,
}

handle_admin_goal_update :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	client_id, has := web.request_param(req, "cid")
	if !has {
		fail(res, .Bad_Request, "missing client id")
		return
	}
	body: Goal_Update
	if len(req.body) == 0 || json_unmarshal(req.body, &body) != "" {
		fail(res, .Bad_Request, "invalid JSON body")
		return
	}

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	if !find_client(&G.conn, client_id) {
		fail(res, .Not_Found, "client not found")
		return
	}

	if body.cleared {
		stmt := db.prepare(&G.conn, "DELETE FROM goals WHERE client_id = ?1")
		if stmt == nil {
			fail(res, .Internal_Error, "database error")
			return
		}
		db.bind_text(stmt, 1, client_id)
		ok := db.step(stmt) == db.SQLITE_DONE
		db.finalize(stmt)
		if !ok {
			fail(res, .Internal_Error, "database error")
			return
		}
	} else {
		if !valid_weight(body.kg) {
			fail(res, .Bad_Request, "weight out of range")
			return
		}
		stmt := db.prepare(
			&G.conn,
			`INSERT INTO goals (client_id, member_id, kg, updated_at) VALUES (?1, NULL, ?2, ?3)
			 ON CONFLICT(client_id) DO UPDATE SET kg = excluded.kg, member_id = NULL, updated_at = excluded.updated_at`,
		)
		if stmt == nil {
			fail(res, .Internal_Error, "database error")
			return
		}
		db.bind_text(stmt, 1, client_id)
		db.bind_double(stmt, 2, body.kg)
		db.bind_int64(stmt, 3, now_ms())
		ok := db.step(stmt) == db.SQLITE_DONE
		db.finalize(stmt)
		if !ok {
			fail(res, .Internal_Error, "database error")
			return
		}
	}
	web.response_json_status(res, .OK, Action_Response{ok = true})
}

handle_admin_member_goal_update :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	client_id, has_c := web.request_param(req, "cid")
	member_id, has_m := web.request_param(req, "mid")
	date, has_d := web.request_param(req, "date")
	if !has_c || !has_m || !has_d {
		fail(res, .Bad_Request, "missing ids")
		return
	}
	if !valid_date(date) {
		fail(res, .Bad_Request, "date must be yyyy-MM-dd")
		return
	}
	body: Member_Goal_Update
	if len(req.body) == 0 || json_unmarshal(req.body, &body) != "" {
		fail(res, .Bad_Request, "invalid JSON body")
		return
	}

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	if !find_client(&G.conn, client_id) {
		fail(res, .Not_Found, "client not found")
		return
	}
	if !member_exists(&G.conn, client_id, member_id) {
		fail(res, .Not_Found, "member not found")
		return
	}

	if body.cleared {
		stmt := db.prepare(
			&G.conn,
			"DELETE FROM member_goals WHERE client_id = ?1 AND member_id = ?2 AND date = ?3",
		)
		if stmt == nil {
			fail(res, .Internal_Error, "database error")
			return
		}
		db.bind_text(stmt, 1, client_id)
		db.bind_text(stmt, 2, member_id)
		db.bind_text(stmt, 3, date)
		ok := db.step(stmt) == db.SQLITE_DONE
		db.finalize(stmt)
		if !ok {
			fail(res, .Internal_Error, "database error")
			return
		}
	} else {
		if !valid_weight(body.kg) {
			fail(res, .Bad_Request, "weight out of range")
			return
		}
		// actual_kg is owned by the client and survives a target edit.
		stmt := db.prepare(
			&G.conn,
			`INSERT INTO member_goals (client_id, member_id, date, target_kg, actual_kg, updated_at)
			 VALUES (?1, ?2, ?3, ?4, 0, ?5)
			 ON CONFLICT(client_id, member_id, date) DO UPDATE SET
			   target_kg = excluded.target_kg,
			   updated_at = excluded.updated_at`,
		)
		if stmt == nil {
			fail(res, .Internal_Error, "database error")
			return
		}
		db.bind_text(stmt, 1, client_id)
		db.bind_text(stmt, 2, member_id)
		db.bind_text(stmt, 3, date)
		db.bind_double(stmt, 4, body.kg)
		db.bind_int64(stmt, 5, now_ms())
		ok := db.step(stmt) == db.SQLITE_DONE
		db.finalize(stmt)
		if !ok {
			fail(res, .Internal_Error, "database error")
			return
		}
	}
	web.response_json_status(res, .OK, Action_Response{ok = true})
}

handle_admin_client_delete :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	client_id, has := web.request_param(req, "cid")
	if !has {
		fail(res, .Bad_Request, "missing client id")
		return
	}

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	if !db.exec(&G.conn, "BEGIN IMMEDIATE") {
		fmt.eprintfln("purge %s: begin: %s", client_id, db.last_error(&G.conn))
		fail(res, .Internal_Error, "database error")
		return
	}
	// Child tables key on client_id; clients itself keys on id.
	tables := []string{"measurements", "batches", "member_goals", "member_details", "member_profiles", "goals", "members", "devices"}
	deleted := 0
	ok := true
	for table in tables {
		sql := strings.concatenate({"DELETE FROM ", table, " WHERE client_id = ?1"}, context.temp_allocator)
		stmt := db.prepare(&G.conn, sql)
		if stmt == nil {
			fmt.eprintfln("purge %s: %s: %s", client_id, table, db.last_error(&G.conn))
			ok = false
			break
		}
		db.bind_text(stmt, 1, client_id)
		step_ok := db.step(stmt) == db.SQLITE_DONE
		db.finalize(stmt)
		if !step_ok {
			fmt.eprintfln("purge %s: %s: %s", client_id, table, db.last_error(&G.conn))
			ok = false
			break
		}
		if table == "measurements" {
			deleted = db.changes(&G.conn)
		}
	}
	if ok {
		stmt := db.prepare(&G.conn, "DELETE FROM clients WHERE id = ?1")
		if stmt == nil {
			fmt.eprintfln("purge %s: clients: %s", client_id, db.last_error(&G.conn))
			ok = false
		} else {
			db.bind_text(stmt, 1, client_id)
			ok = db.step(stmt) == db.SQLITE_DONE
			if !ok {
				fmt.eprintfln("purge %s: clients: %s", client_id, db.last_error(&G.conn))
			}
			db.finalize(stmt)
		}
	}
	if !ok {
		db.exec(&G.conn, "ROLLBACK")
		fail(res, .Internal_Error, "database error")
		return
	}
	if !db.exec(&G.conn, "COMMIT") {
		fmt.eprintfln("purge %s: commit: %s", client_id, db.last_error(&G.conn))
		db.exec(&G.conn, "ROLLBACK")
		fail(res, .Internal_Error, "database error")
		return
	}
	web.response_json_status(res, .OK, Action_Response{ok = true, deleted = deleted})
}

// ---- measurements --------------------------------------------------------

Measurement_Filter :: struct {
	client_id: string,
	member_id: string,
	device_id: string,
	q:         string,
	from:      i64,
	to:        i64,
}

parse_measurement_filter :: proc(req: ^web.Request) -> Measurement_Filter {
	return Measurement_Filter {
		client_id = query_value(req, "client_id"),
		member_id = query_value(req, "member_id"),
		device_id = query_value(req, "device_id"),
		q = strings.trim_space(query_value(req, "q")),
		from = query_i64(req, "from"),
		to = query_i64(req, "to"),
	}
}

// build_measurement_where writes a WHERE clause (or "") and the positional
// args for it. Indexed filters come first so SQLite can pick them; the free
// text search is the last OR group.
build_measurement_where :: proc(
	f: Measurement_Filter,
) -> (
	where_sql: string,
	args: [9]Arg,
	count: int,
) {
	if f.client_id == "" && f.member_id == "" && f.device_id == "" && f.q == "" && f.from <= 0 && f.to <= 0 {
		return "", args, 0
	}
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	first := true
	if f.client_id != "" {
		where_add(&sb, &first, "m.client_id = ?")
		args[count] = Arg{kind = .Text, text = f.client_id}
		count += 1
	}
	if f.member_id != "" {
		where_add(&sb, &first, "m.member_id = ?")
		args[count] = Arg{kind = .Text, text = f.member_id}
		count += 1
	}
	if f.device_id != "" {
		where_add(&sb, &first, "m.device_id = ?")
		args[count] = Arg{kind = .Text, text = f.device_id}
		count += 1
	}
	if f.from > 0 {
		where_add(&sb, &first, "m.ts_ms >= ?")
		args[count] = Arg{kind = .Int, num = f.from}
		count += 1
	}
	if f.to > 0 {
		where_add(&sb, &first, "m.ts_ms <= ?")
		args[count] = Arg{kind = .Int, num = f.to}
		count += 1
	}
	if f.q != "" {
		where_add(
			&sb,
			&first,
			"(m.member_id LIKE ? OR mm.name LIKE ? OR COALESCE(m.device_id, '') LIKE ? OR COALESCE(dv.name, '') LIKE ?)",
		)
		pattern := strings.concatenate({"%", f.q, "%"}, context.temp_allocator)
		for _ in 0 ..< 4 {
			args[count] = Arg{kind = .Text, text = pattern}
			count += 1
		}
	}
	where_sql = strings.to_string(sb)
	return
}

MEASUREMENT_SELECT :: `SELECT m.uid, m.client_id, m.member_id, COALESCE(mm.name, ''), COALESCE(m.device_id, ''), COALESCE(dv.name, ''), m.ts_ms, m.kg, m.received_at, m.batch_id`

MEASUREMENT_FROM :: `
	FROM measurements m
	LEFT JOIN members mm ON mm.client_id = m.client_id AND mm.id = m.member_id
	LEFT JOIN devices dv ON dv.client_id = m.client_id AND dv.id = m.device_id`

handle_admin_measurements :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	limit := clamp(query_int(req, "limit", 50), 1, 500)
	offset := max(query_int(req, "offset", 0), 0)

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	f := parse_measurement_filter(req)
	where_sql, args, nargs := build_measurement_where(f)

	out := Measurements_Response {
		ok     = true,
		limit  = limit,
		offset = offset,
		items  = make([dynamic]Measurement_Row, 0, limit),
	}

	cstmt := db.prepare(
		&G.conn,
		strings.concatenate({"SELECT COUNT(*)", MEASUREMENT_FROM, where_sql}, context.temp_allocator),
	)
	if cstmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	bind_args(cstmt, args[:nargs])
	if db.step(cstmt) == db.SQLITE_ROW {
		out.total = db.col_int(cstmt, 0)
	}
	db.finalize(cstmt)

	stmt := db.prepare(
		&G.conn,
		strings.concatenate(
			{MEASUREMENT_SELECT, MEASUREMENT_FROM, where_sql, " ORDER BY m.ts_ms DESC LIMIT ? OFFSET ?"},
			context.temp_allocator,
		),
	)
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(stmt)
	idx := bind_args(stmt, args[:nargs])
	db.bind_int(stmt, idx, limit)
	db.bind_int(stmt, idx + 1, offset)
	for db.step(stmt) == db.SQLITE_ROW {
		append(
			&out.items,
			Measurement_Row {
				uid = db.col_text_dup(stmt, 0, context.temp_allocator),
				client_id = db.col_text_dup(stmt, 1, context.temp_allocator),
				member_id = db.col_text_dup(stmt, 2, context.temp_allocator),
				member_name = db.col_text_dup(stmt, 3, context.temp_allocator),
				device_id = db.col_text_dup(stmt, 4, context.temp_allocator),
				device_name = db.col_text_dup(stmt, 5, context.temp_allocator),
				ts_ms = db.col_int64(stmt, 6),
				kg = db.col_double(stmt, 7),
				received_at = db.col_int64(stmt, 8),
				batch_id = db.col_text_dup(stmt, 9, context.temp_allocator),
			},
		)
	}

	web.response_json_status(res, .OK, out)
}

// Canonical `ts` rendering: epoch seconds with exactly 3 decimals.
csv_write_ts :: proc(sb: ^strings.Builder, ts_ms: i64) {
	fmt.sbprintf(sb, "%d.%03d", ts_ms / 1000, ts_ms % 1000)
}

csv_write :: proc(sb: ^strings.Builder, s: string) {
	quoted := strings.contains_any(s, ",\"\n\r")
	if quoted {
		strings.write_byte(sb, '"')
	}
	for i in 0 ..< len(s) {
		if s[i] == '"' {
			strings.write_byte(sb, '"')
		}
		strings.write_byte(sb, s[i])
	}
	if quoted {
		strings.write_byte(sb, '"')
	}
}

handle_admin_measurements_csv :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	f := parse_measurement_filter(req)
	where_sql, args, nargs := build_measurement_where(f)

	stmt := db.prepare(
		&G.conn,
		strings.concatenate(
			{
				"SELECT m.ts_ms, m.client_id, m.member_id, COALESCE(mm.name, ''), COALESCE(m.device_id, ''), COALESCE(dv.name, ''), m.kg",
				MEASUREMENT_FROM,
				where_sql,
				" ORDER BY m.ts_ms ASC LIMIT 100000",
			},
			context.temp_allocator,
		),
	)
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(stmt)
	bind_args(stmt, args[:nargs])

	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	// BOM keeps Excel on Windows from mis-detecting UTF-8 Chinese names.
	strings.write_string(&sb, "\xEF\xBB\xBF")
	strings.write_string(&sb, CSV_HEADER)
	strings.write_byte(&sb, '\n')
	for db.step(stmt) == db.SQLITE_ROW {
		csv_write_ts(&sb, db.col_int64(stmt, 0))
		strings.write_byte(&sb, ',')
		csv_write(&sb, db.col_text(stmt, 1))
		strings.write_byte(&sb, ',')
		csv_write(&sb, db.col_text(stmt, 4))
		strings.write_byte(&sb, ',')
		csv_write(&sb, db.col_text(stmt, 5))
		strings.write_byte(&sb, ',')
		csv_write(&sb, db.col_text(stmt, 2))
		strings.write_byte(&sb, ',')
		csv_write(&sb, db.col_text(stmt, 3))
		fmt.sbprintf(&sb, ",%.3f\n", db.col_double(stmt, 6))
	}

	web.response_set_header(res, "Content-Type", "text/csv; charset=utf-8")
	web.response_set_header(
		res,
		"Content-Disposition",
		"attachment; filename=\"litescale-measurements.csv\"",
	)
	web.response_set_header(res, "Cache-Control", "no-store")
	web.response_write_string(res, strings.to_string(sb))
}

handle_admin_measurement_delete :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}

	// Two shapes: ?uid=... for one row, or JSON {"uids": [...]} for a batch.
	batch: Bulk_Delete_Request
	single := strings.trim_space(query_value(req, "uid"))
	if len(req.body) > 0 {
		if json_unmarshal(req.body, &batch) != "" {
			fail(res, .Bad_Request, "invalid JSON body")
			return
		}
	}
	if len(batch.uids) == 0 && single == "" {
		fail(res, .Bad_Request, "missing uid")
		return
	}
	if len(batch.uids) > 500 {
		fail(res, .Bad_Request, "too many uids (max 500)")
		return
	}

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	conn := &G.conn
	if !db.exec(conn, "BEGIN IMMEDIATE") {
		fail(res, .Internal_Error, "database error")
		return
	}
	committed := false
	defer {
		if !committed {
			db.exec(conn, "ROLLBACK")
		}
	}

	stmt := db.prepare(conn, "DELETE FROM measurements WHERE uid = ?1")
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(stmt)

	deleted := 0
	if len(batch.uids) > 0 {
		for uid in batch.uids {
			if uid == "" {
				continue
			}
			db.reset(stmt)
			db.bind_text(stmt, 1, uid)
			if db.step(stmt) != db.SQLITE_DONE {
				fmt.eprintfln("bulk delete %s: %s", uid, db.last_error(conn))
				fail(res, .Internal_Error, "database error")
				return
			}
			deleted += db.changes(conn)
		}
	} else {
		db.bind_text(stmt, 1, single)
		if db.step(stmt) != db.SQLITE_DONE {
			fail(res, .Internal_Error, "database error")
			return
		}
		deleted = db.changes(conn)
	}

	if !db.exec(conn, "COMMIT") {
		fail(res, .Internal_Error, "database error")
		return
	}
	committed = true
	web.response_json_status(res, .OK, Action_Response{ok = true, deleted = deleted})
}

// handle_admin_measurement_update edits weight / timestamp / member. The
// content-derived uid changes with the content, so it is recomputed; a clash
// with another row means the edit would create a duplicate and is rejected.
handle_admin_measurement_update :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	uid, has_uid := web.request_param(req, "uid")
	if !has_uid || uid == "" {
		fail(res, .Bad_Request, "missing uid")
		return
	}

	payload: Measurement_Update
	if len(req.body) == 0 || json_unmarshal(req.body, &payload) != "" {
		fail(res, .Bad_Request, "invalid JSON body")
		return
	}
	min_ts := i64(946684800000)
	if payload.ts_ms < min_ts || payload.ts_ms > now_ms() + 24 * 60 * 60 * 1000 {
		fail(res, .Bad_Request, "timestamp out of range")
		return
	}
	if !valid_weight(payload.kg) {
		fail(res, .Bad_Request, "weight out of range")
		return
	}
	if payload.member_id != "" && !valid_key(payload.member_id, 64) {
		fail(res, .Bad_Request, "invalid member id")
		return
	}

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	conn := &G.conn
	cur := db.prepare(
		conn,
		"SELECT client_id, member_id, COALESCE(device_id, '') FROM measurements WHERE uid = ?1",
	)
	if cur == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	db.bind_text(cur, 1, uid)
	if db.step(cur) != db.SQLITE_ROW {
		db.finalize(cur)
		fail(res, .Not_Found, "measurement not found")
		return
	}
	client_id := db.col_text_dup(cur, 0, context.temp_allocator)
	member_id := db.col_text_dup(cur, 1, context.temp_allocator)
	device_id := db.col_text_dup(cur, 2, context.temp_allocator)
	db.finalize(cur)

	if payload.member_id != "" {
		if !member_exists(conn, client_id, payload.member_id) {
			fail(res, .Bad_Request, "unknown member")
			return
		}
		member_id = payload.member_id
	}

	new_uid := record_uid(client_id, member_id, device_id, payload.ts_ms, payload.kg)
	stmt := db.prepare(
		conn,
		"UPDATE measurements SET uid = ?1, member_id = ?2, ts_ms = ?3, kg = ?4 WHERE uid = ?5",
	)
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, new_uid)
	db.bind_text(stmt, 2, member_id)
	db.bind_int64(stmt, 3, payload.ts_ms)
	db.bind_double(stmt, 4, payload.kg)
	db.bind_text(stmt, 5, uid)
	if db.step(stmt) != db.SQLITE_DONE {
		msg := db.last_error(conn)
		if strings.contains(msg, "UNIQUE") {
			fail(res, .Conflict, "another measurement with the same content exists")
			return
		}
		fmt.eprintfln("update measurement %s: %s", uid, msg)
		fail(res, .Internal_Error, "database error")
		return
	}
	web.response_json_status(res, .OK, Measurement_Update_Response{ok = true, uid = new_uid})
}

// ---- CSV import ----------------------------------------------------------

// parse_csv_line splits one CSV record, honouring double quotes and "" escapes.
parse_csv_line :: proc(line: string) -> [dynamic]string {
	fields := make([dynamic]string, 0, 8, context.temp_allocator)
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	in_quotes := false
	i := 0
	for i < len(line) {
		c := line[i]
		if in_quotes {
			if c == '"' {
				if i + 1 < len(line) && line[i + 1] == '"' {
					strings.write_byte(&sb, '"')
					i += 2
					continue
				}
				in_quotes = false
				i += 1
				continue
			}
			strings.write_byte(&sb, c)
			i += 1
			continue
		}
		switch c {
		case '"':
			in_quotes = true
		case ',':
			append(&fields, strings.to_string(sb))
			strings.builder_init(&sb, context.temp_allocator)
		case:
			strings.write_byte(&sb, c)
		}
		i += 1
	}
	append(&fields, strings.to_string(sb))
	return fields
}

// Canonical measurement CSV schema, shared with the app and the mini program.
// `ts` is Unix epoch seconds with exactly 3 decimals (millisecond precision).
CSV_HEADER :: "ts,client_id,device_id,device_name,member_id,member_name,kg"

CSV_Columns :: struct {
	ts:       int,
	kg:       int,
	client:   int,
	member:   int,
	member_n: int,
	device:   int,
	device_n: int,
	valid:    bool,
}

csv_empty_columns :: proc() -> CSV_Columns {
	return CSV_Columns {
		ts = -1, kg = -1, client = -1, member = -1, member_n = -1, device = -1, device_n = -1,
	}
}

csv_header_name :: proc(f: string, i: int) -> string {
	name := strings.to_lower(strings.trim_space(f))
	if i == 0 {
		name = strings.trim_prefix(name, "\xEF\xBB\xBF")
	}
	return name
}

// csv_header_index resolves the canonical schema only; this is the import
// contract. Unknown columns are ignored.
csv_header_index :: proc(fields: []string) -> CSV_Columns {
	cols := csv_empty_columns()
	for f, i in fields {
		switch csv_header_name(f, i) {
		case "ts":
			cols.ts = i
		case "kg":
			cols.kg = i
		case "client_id":
			cols.client = i
		case "member_id":
			cols.member = i
		case "member_name":
			cols.member_n = i
		case "device_id":
			cols.device = i
		case "device_name":
			cols.device_n = i
		}
	}
	cols.valid = cols.ts >= 0 && cols.kg >= 0
	return cols
}

// csv_compat_header_index recognises headers from older builds and third-party
// tools. Compatibility is applied only after the canonical lookup has failed,
// and only fills columns it left unresolved.
csv_compat_header_index :: proc(base: CSV_Columns, fields: []string) -> CSV_Columns {
	cols := base
	for f, i in fields {
		switch csv_header_name(f, i) {
		case "ts_ms", "timestamp_ms", "timestamp", "time", "t":
			if cols.ts < 0 { cols.ts = i }
		case "weight_kg", "weight":
			if cols.kg < 0 { cols.kg = i }
		}
	}
	cols.valid = cols.ts >= 0 && cols.kg >= 0
	return cols
}

csv_field :: proc(fields: []string, idx: int) -> string {
	if idx < 0 || idx >= len(fields) {
		return ""
	}
	return strings.trim_space(fields[idx])
}

// parse_csv_ts reads the canonical `ts` (epoch seconds, 3 decimals). Integer
// milliseconds from older exports are accepted as a compatibility fallback.
parse_csv_ts :: proc(value: string) -> (ts_ms: i64, ok: bool) {
	v, v_ok := strconv.parse_f64(value)
	// The range check also rejects NaN.
	if !v_ok || !(v >= 946684800 && v < 1e15) {
		return 0, false
	}
	if v >= 100_000_000_000 {
		return i64(v + 0.5), true
	}
	return i64(v * 1000 + 0.5), true
}

// lookup_member resolves a member by id, then by name, and creates it only when
// a name is available. Returns the member id, whether it was created, and ok.
lookup_member :: proc(
	conn: ^db.Conn,
	client_id, member_id, member_name: string,
) -> (
	resolved: string,
	created: bool,
	ok: bool,
) {
	if member_id != "" && valid_key(member_id, 64) {
		if member_exists(conn, client_id, member_id) {
			return member_id, false, true
		}
		if member_name == "" || len(member_name) > 128 {
			return "", false, false
		}
		stmt := db.prepare(
			conn,
			`INSERT INTO members (client_id, id, name, avatar, color, updated_at)
			 VALUES (?1, ?2, ?3, 'a01', 0, ?4)`,
		)
		if stmt == nil {
			return "", false, false
		}
		db.bind_text(stmt, 1, client_id)
		db.bind_text(stmt, 2, member_id)
		db.bind_text(stmt, 3, member_name)
		db.bind_int64(stmt, 4, now_ms())
		code := db.step(stmt)
		db.finalize(stmt)
		if code != db.SQLITE_DONE {
			return "", false, false
		}
		return member_id, true, true
	}

	if member_name == "" || len(member_name) > 128 {
		return "", false, false
	}
	stmt := db.prepare(conn, "SELECT id FROM members WHERE client_id = ?1 AND name = ?2 LIMIT 1")
	if stmt == nil {
		return "", false, false
	}
	db.bind_text(stmt, 1, client_id)
	db.bind_text(stmt, 2, member_name)
	found := db.step(stmt) == db.SQLITE_ROW
	id := ""
	if found {
		id = db.col_text_dup(stmt, 0, context.temp_allocator)
	}
	db.finalize(stmt)
	if found {
		return id, false, true
	}

	hash := sha256_hex_str(member_name)
	defer delete(hash)
	new_id := fmt.tprintf("csv-%.8s", hash)
	stmt = db.prepare(
		conn,
		`INSERT INTO members (client_id, id, name, avatar, color, updated_at)
		 VALUES (?1, ?2, ?3, 'a01', 0, ?4) ON CONFLICT(client_id, id) DO NOTHING`,
	)
	if stmt == nil {
		return "", false, false
	}
	db.bind_text(stmt, 1, client_id)
	db.bind_text(stmt, 2, new_id)
	db.bind_text(stmt, 3, member_name)
	db.bind_int64(stmt, 4, now_ms())
	code := db.step(stmt)
	db.finalize(stmt)
	if code != db.SQLITE_DONE {
		return "", false, false
	}
	return new_id, true, true
}

IMPORT_MAX_ROWS :: 20000

handle_admin_measurements_import :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	if len(req.body) == 0 {
		fail(res, .Bad_Request, "empty CSV body")
		return
	}
	if len(req.body) > G.cfg.max_body {
		fail(res, .Payload_Too_Large, "file too large")
		return
	}

	fallback_client := strings.trim_space(query_value(req, "client_id"))
	text := string(req.body)
	lines := strings.split_lines(text, context.temp_allocator)

	out := Import_Response{ok = true, rejected = make([dynamic]Rejected, 0, 8)}
	cols := csv_empty_columns()
	header_seen := false

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	conn := &G.conn
	if !db.exec(conn, "BEGIN IMMEDIATE") {
		fail(res, .Internal_Error, "database error")
		return
	}
	committed := false
	defer {
		if !committed {
			db.exec(conn, "ROLLBACK")
		}
	}

	ins := db.prepare(
		conn,
		`INSERT INTO measurements (uid, client_id, member_id, device_id, ts_ms, kg, received_at, batch_id)
		 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8) ON CONFLICT(uid) DO NOTHING`,
	)
	if ins == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(ins)

	// Names in the file are display labels; keep an existing name when the row
	// does not carry one so a name-less export cannot erase client metadata.
	dev := db.prepare(
		conn,
		`INSERT INTO devices (client_id, id, name, last_seen)
		 VALUES (?1, ?2, ?3, ?4)
		 ON CONFLICT(client_id, id) DO UPDATE SET
		   name = CASE WHEN excluded.name <> '' THEN excluded.name ELSE devices.name END,
		   last_seen = MAX(devices.last_seen, excluded.last_seen)`,
	)
	if dev == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(dev)

	at := now_ms()
	batch_client := fallback_client
	batch_id := fmt.tprintf("admin-import-%d-%s", at, random_hex(4))
	min_ts := i64(946684800000)
	future := at + 24 * 60 * 60 * 1000

	for raw, lineno in lines {
		line := strings.trim_space(raw)
		if line == "" {
			continue
		}
		fields := parse_csv_line(line)
		if !header_seen {
			header_seen = true
			cols = csv_header_index(fields[:])
			if !cols.valid {
				// Compatibility: headers from older builds / other tools.
				cols = csv_compat_header_index(cols, fields[:])
			}
			if !cols.valid {
				fail(res, .Bad_Request, "CSV header must contain ts (epoch seconds, 3 decimals) and kg")
				return
			}
			continue
		}
		if out.total >= IMPORT_MAX_ROWS {
			break
		}
		out.total += 1

		ts, ts_ok := parse_csv_ts(csv_field(fields[:], cols.ts))
		if !ts_ok || ts < min_ts || ts > future {
			append(&out.rejected, Rejected{index = lineno + 1, reason = "bad timestamp"})
			continue
		}
		kg, kg_ok := strconv.parse_f64(csv_field(fields[:], cols.kg))
		if !kg_ok || !valid_weight(kg) {
			append(&out.rejected, Rejected{index = lineno + 1, reason = "weight out of range"})
			continue
		}

		client_id := csv_field(fields[:], cols.client)
		if client_id == "" {
			client_id = fallback_client
		}
		if client_id == "" {
			append(&out.rejected, Rejected{index = lineno + 1, reason = "missing client_id"})
			continue
		}
		if !find_client(conn, client_id) {
			append(&out.rejected, Rejected{index = lineno + 1, reason = "unknown client"})
			continue
		}
		if batch_client == "" {
			batch_client = client_id
		}

		supplied_device := csv_field(fields[:], cols.device)
		if supplied_device != "" && !valid_key(supplied_device, 128) {
			append(&out.rejected, Rejected{index = lineno + 1, reason = "invalid device id"})
			continue
		}
		supplied_device_name := csv_field(fields[:], cols.device_n)
		if len(supplied_device_name) > 128 {
			append(&out.rejected, Rejected{index = lineno + 1, reason = "invalid device name"})
			continue
		}

		member_id, created, member_ok := lookup_member(
			conn,
			client_id,
			csv_field(fields[:], cols.member),
			csv_field(fields[:], cols.member_n),
		)
		if !member_ok {
			append(&out.rejected, Rejected{index = lineno + 1, reason = "unknown member"})
			continue
		}
		if created {
			out.members_created += 1
		}

		if supplied_device != "" {
			db.reset(dev)
			db.bind_text(dev, 1, client_id)
			db.bind_text(dev, 2, supplied_device)
			db.bind_text(dev, 3, supplied_device_name)
			db.bind_int64(dev, 4, ts)
			if db.step(dev) != db.SQLITE_DONE {
				fmt.eprintfln("import row %d device: %s", lineno + 1, db.last_error(conn))
				fail(res, .Internal_Error, "database error")
				return
			}
		}

		uid := record_uid(client_id, member_id, supplied_device, ts, kg)
		db.reset(ins)
		db.bind_text(ins, 1, uid)
		db.bind_text(ins, 2, client_id)
		db.bind_text(ins, 3, member_id)
		if supplied_device == "" {
			db.bind_null(ins, 4)
		} else {
			db.bind_text(ins, 4, supplied_device)
		}
		db.bind_int64(ins, 5, ts)
		db.bind_double(ins, 6, kg)
		db.bind_int64(ins, 7, at)
		db.bind_text(ins, 8, batch_id)
		if db.step(ins) != db.SQLITE_DONE {
			fmt.eprintfln("import row %d: %s", lineno + 1, db.last_error(conn))
			fail(res, .Internal_Error, "database error")
			return
		}
		if db.changes(conn) == 1 {
			out.imported += 1
		} else {
			out.duplicates += 1
		}
		delete(uid)
	}

	if !header_seen {
		fail(res, .Bad_Request, "empty CSV body")
		return
	}

	bstmt := db.prepare(
		conn,
		`INSERT INTO batches (id, client_id, received_at, payload_sha256, records, accepted, duplicates)
		 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
	)
	if bstmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	sha := sha256_hex(req.body)
	db.bind_text(bstmt, 1, batch_id)
	db.bind_text(bstmt, 2, batch_client)
	db.bind_int64(bstmt, 3, at)
	db.bind_text(bstmt, 4, sha)
	db.bind_int(bstmt, 5, out.total)
	db.bind_int(bstmt, 6, out.imported)
	db.bind_int(bstmt, 7, out.duplicates)
	code := db.step(bstmt)
	db.finalize(bstmt)
	if code != db.SQLITE_DONE {
		fail(res, .Internal_Error, "database error")
		return
	}

	if !db.exec(conn, "COMMIT") {
		fail(res, .Internal_Error, "database error")
		return
	}
	committed = true

	web.response_json_status(res, .OK, out)
}

// ---- batches -------------------------------------------------------------

handle_admin_batches :: proc(req: ^web.Request, res: ^web.Response) {
	if !authenticate_admin(req) {
		fail(res, .Unauthorized, "admin token required")
		return
	}
	limit := clamp(query_int(req, "limit", 50), 1, 500)
	offset := max(query_int(req, "offset", 0), 0)
	client_id := query_value(req, "client_id")

	sync.lock(&G.mu)
	defer sync.unlock(&G.mu)

	out := Batches_Response{ok = true, limit = limit, offset = offset, items = make([dynamic]Batch_Out, 0, limit)}

	cstmt := db.prepare(&G.conn, "SELECT COUNT(*) FROM batches WHERE (?1 = '' OR client_id = ?1)")
	if cstmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	db.bind_text(cstmt, 1, client_id)
	if db.step(cstmt) == db.SQLITE_ROW {
		out.total = db.col_int(cstmt, 0)
	}
	db.finalize(cstmt)

	stmt := db.prepare(
		&G.conn,
		`SELECT id, client_id, received_at, payload_sha256, records, accepted, duplicates
		 FROM batches WHERE (?1 = '' OR client_id = ?1)
		 ORDER BY received_at DESC LIMIT ?2 OFFSET ?3`,
	)
	if stmt == nil {
		fail(res, .Internal_Error, "database error")
		return
	}
	defer db.finalize(stmt)
	db.bind_text(stmt, 1, client_id)
	db.bind_int(stmt, 2, limit)
	db.bind_int(stmt, 3, offset)
	for db.step(stmt) == db.SQLITE_ROW {
		append(
			&out.items,
			Batch_Out {
				id = db.col_text_dup(stmt, 0, context.temp_allocator),
				client_id = db.col_text_dup(stmt, 1, context.temp_allocator),
				received_at = db.col_int64(stmt, 2),
				payload_sha256 = db.col_text_dup(stmt, 3, context.temp_allocator),
				records = db.col_int(stmt, 4),
				accepted = db.col_int(stmt, 5),
				duplicates = db.col_int(stmt, 6),
			},
		)
	}

	web.response_json_status(res, .OK, out)
}

register_admin_routes :: proc() {
	web.router_get(&G.router, "/", handle_root)
	web.router_get(&G.router, "/admin", handle_admin_index)
	web.router_get(&G.router, "/admin/", handle_admin_index)
	web.router_get(&G.router, "/admin/alpine.js", handle_admin_js)
	web.router_get(&G.router, "/admin/avatar/:id", handle_admin_avatar)

	web.router_get(&G.router, "/api/v1/admin/overview", handle_admin_overview)
	web.router_get(&G.router, "/api/v1/admin/clients", handle_admin_clients)
	web.router_get(&G.router, "/api/v1/admin/clients/:id", handle_admin_client_detail)
	web.router_get(&G.router, "/api/v1/admin/measurements", handle_admin_measurements)
	web.router_get(&G.router, "/api/v1/admin/measurements.csv", handle_admin_measurements_csv)
	web.router_get(&G.router, "/api/v1/admin/batches", handle_admin_batches)

	web.router_post(&G.router, "/api/v1/admin/clients/:cid/members/:mid", handle_admin_member_update)
	web.router_put(&G.router, "/api/v1/admin/clients/:cid/goal", handle_admin_goal_update)
	web.router_put(
		&G.router,
		"/api/v1/admin/clients/:cid/members/:mid/goals/:date",
		handle_admin_member_goal_update,
	)
	web.router_delete(&G.router, "/api/v1/admin/clients/:cid", handle_admin_client_delete)
	web.router_delete(&G.router, "/api/v1/admin/measurements", handle_admin_measurement_delete)
	web.router_put(&G.router, "/api/v1/admin/measurements/:uid", handle_admin_measurement_update)
	web.router_post(&G.router, "/api/v1/admin/measurements/import", handle_admin_measurements_import)
}
