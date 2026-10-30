package db

import "core:c"
import "core:mem"
import "core:strings"

// db.odin — 在 sqlite.odin 的裸 ccall 之上包一层「够用就好」的过程式 API。
//
// 设计取向（贴合 Odin 语言天花板，也贴合「直连、不引 ORM」的诉求）：
//   - 无对象方法/无闭包回调：都是自由 proc，句柄用 ^Conn / ^Stmt。
//   - 错误：exec/prepare 返回 bool（配合 last_error 取 errmsg）；step 直接透传 Code。
//   - 内存：入参 string→cstring 用 mem.temp_allocator 造 null 结尾副本（SQLITE_TRANSIENT
//     让 sqlite 立即拷走，故可安全越出临时作用域）；出参文本列默认「借用」sqlite 内部
//     缓冲（step/finalize 前有效），需要留存时用 col_text_dup 拷进给定 allocator。
//
// 注：连接句柄形参统一叫 conn（不叫 c，避免遮蔽 core:c 包名里的 c.char/c.int）。

Conn :: struct {
	h: ^Sqlite3,
}

// dup_cz 用 mem.temp_allocator 造一个 null 结尾副本，供 cstring 入参使用。
dup_cz :: proc(s: string) -> cstring {
	buf := make([]byte, len(s) + 1, context.temp_allocator)
	copy(buf, s)
	buf[len(s)] = 0
	return transmute(cstring)(&buf[0])
}

// cz_len 数 cstring 长度（自带 null 结尾扫描），避开本版对 cstring_len 内建名的歧义。
cz_len :: proc(p: cstring) -> int {
	if p == nil { return 0 }
	b := transmute([^]byte)(p)
	n := 0
	for b[n] != 0 { n += 1 }
	return n
}

// cz_str 把 cstring 前 n 字节转成 Odin string（零拷贝视图，指向 sqlite 内部缓冲）。
cz_str :: proc(p: cstring, n: int) -> string {
	if p == nil || n <= 0 { return "" }
	b := transmute([^]byte)(p)
	return transmute(string)(b[0:n])
}

// —— 生命周期 ——

// open 打开（或创建）db 文件；":memory:" 走内存库。失败返回 ok=false。
open :: proc(path: string) -> (conn: Conn, ok: bool) {
	h: ^Sqlite3
	code := sqlite3_open_v2(dup_cz(path), &h, SQLITE_OPEN_FLAGS, nil)
	if code != SQLITE_OK || h == nil {
		if h != nil { sqlite3_close(h) }
		return Conn{}, false
	}
	// page cache 显式压到 1 MiB（SQLite 默认 -2000 KiB = 2 MiB）：本服务的 DB 只放
	// 设置/账号/存储/索引行，媒体清单走 .index.jsonl 侧车，命中集很小；省下的 1 MiB
	// 在空闲 footprint 上直接可见（2026-10-22 实测缓存随查询增长 ~0.5 MiB）。
	exec(&Conn{h = h}, "PRAGMA cache_size=-1024")
	return Conn{h = h}, true
}

close :: proc(conn: ^Conn) {
	if conn == nil || conn.h == nil { return }
	sqlite3_close(conn.h)
	conn.h = nil
}

// last_error 取最近一次错误信息（无错时为空串）。errmsg 是 cstring，用 csize_len 求长。
last_error :: proc(conn: ^Conn) -> string {
	if conn == nil || conn.h == nil { return "" }
	p := sqlite3_errmsg(conn.h)
	return cz_str(p, cz_len(p))
}

// exec 执行无需绑定参数的 SQL（DDL、批量语句）。
exec :: proc(conn: ^Conn, sql: string) -> (ok: bool) {
	errz: ^c.char
	code := sqlite3_exec(conn.h, dup_cz(sql), nil, nil, &errz)
	if errz != nil { sqlite3_free(errz) }
	return code == SQLITE_OK
}

// —— 预编译语句 ——

// prepare 编译一条 SQL；失败返回 nil（错误信息见 last_error）。
prepare :: proc(conn: ^Conn, sql: string) -> ^Stmt {
	s: ^Stmt
	code := sqlite3_prepare_v2(conn.h, dup_cz(sql), c.int(len(sql)) + 1, &s, nil)
	if code != SQLITE_OK { return nil }
	return s
}

step     :: proc(s: ^Stmt) -> Code     { return sqlite3_step(s) }
finalize :: proc(s: ^Stmt) -> Code     { return sqlite3_finalize(s) }
reset    :: proc(s: ^Stmt) -> Code     { return sqlite3_reset(s) }

// —— 绑定（idx 从 1 起，遵循 SQLite 约定）——

bind_int    :: proc(s: ^Stmt, idx: int, v: int) -> Code  { return sqlite3_bind_int(s, c.int(idx), c.int(v)) }
bind_int64  :: proc(s: ^Stmt, idx: int, v: i64) -> Code  { return sqlite3_bind_int64(s, c.int(idx), v) }
bind_double :: proc(s: ^Stmt, idx: int, v: f64) -> Code  { return sqlite3_bind_double(s, c.int(idx), v) }
bind_bool   :: proc(s: ^Stmt, idx: int, v: bool) -> Code { return sqlite3_bind_int(s, c.int(idx), bool_to_int(v)) }
bind_null   :: proc(s: ^Stmt, idx: int) -> Code          { return sqlite3_bind_null(s, c.int(idx)) }

// bind_text：SQLITE_TRANSIENT 让 sqlite 立即拷贝，临时 cstring 副本随即失效无妨。
bind_text :: proc(s: ^Stmt, idx: int, v: string) -> Code {
	p := dup_cz(v)
	return sqlite3_bind_text(s, c.int(idx), p, c.int(len(v)), SQLITE_TRANSIENT)
}

// —— 取列（col 从 0 起）——

col_int    :: proc(s: ^Stmt, col: int) -> int  { return int(sqlite3_column_int(s, c.int(col))) }
col_int64  :: proc(s: ^Stmt, col: int) -> i64  { return sqlite3_column_int64(s, c.int(col)) }
col_double :: proc(s: ^Stmt, col: int) -> f64  { return sqlite3_column_double(s, c.int(col)) }
col_bool   :: proc(s: ^Stmt, col: int) -> bool { return sqlite3_column_int(s, c.int(col)) != 0 }

// col_text 返回借用 sqlite 内部缓冲的 string（下一次 step/finalize 前有效）。
col_text :: proc(s: ^Stmt, col: int) -> string {
	p := sqlite3_column_text(s, c.int(col))
	n := int(sqlite3_column_bytes(s, c.int(col)))
	return cz_str(p, n)
}

// col_text_dup 把文本列拷进给定 allocator，供越过 step 生命周期留存。
col_text_dup :: proc(s: ^Stmt, col: int, alloc: mem.Allocator) -> string {
	p := sqlite3_column_text(s, c.int(col))
	n := int(sqlite3_column_bytes(s, c.int(col)))
	if p == nil || n <= 0 { return "" }
	dup, _ := strings.clone(cz_str(p, n), alloc)
	return dup
}

// —— 便捷标量 ——

last_insert_rowid :: proc(conn: ^Conn) -> i64 { return sqlite3_last_insert_rowid(conn.h) }
changes           :: proc(conn: ^Conn) -> int { return int(sqlite3_changes(conn.h)) }

bool_to_int :: proc(b: bool) -> c.int {
	if b { return 1 }
	return 0
}
