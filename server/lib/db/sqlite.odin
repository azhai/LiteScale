package db

import "core:c"

// sqlite.odin —— SQLite **直连**薄绑定（ccall 到系统 libsqlite3），取代 Go 侧的 goent ORM。
//
// 只包一层够用的 API：open/close/exec + 预编译语句（prepare/bind/step/column）+
// last_insert_rowid/changes/errmsg。业务 SQL 由上层手写，不引任何 ORM。
//
// 链接：foreign import "system:sqlite3" 让链接器带 `-lsqlite3`（macOS/Linux 系统自带）。
// 约定：foreign 块内 proc 名必须等于 C 符号名（sqlite3_*），故此处保留全名。
// 字符串入参用 cstring（Odin 字符串字面量即 cstring，null 结尾）；文本列出参用
// column_text 拿 cstring，再转回 Odin string（借用 sqlite 内部缓冲，step/finalize 前有效）。

Sqlite3 :: struct {}
Stmt   :: struct {}

// Code 一个 C 返回码（SQLITE_*）。
Code :: c.int

SQLITE_OK          :: Code(0)
SQLITE_ROW         :: Code(100)
SQLITE_DONE        :: Code(101)
SQLITE_OPEN_READWRITE :: 0x00000002
SQLITE_OPEN_CREATE    :: 0x00000004
// 连接线程模式二选一（互斥位）。服务在 nbio 多线程上共享同一个 sqlite3 句柄：
// 不显式指定时虽名义上继承 THREADSAFE 默认，但实测本环境并发 prepare 仍会打坏连接内部分配器
// （sqlite3Prepare 里 KERN_INVALID_ADDRESS → SIGSEGV）。显式 FULLMUTEX 强制每连接串行化，
// 让任意一次 sqlite3_* 调用内部互斥，杜绝「漏加应用锁」把共享句柄改坏。
SQLITE_OPEN_NOMUTEX   :: 0x00008000
SQLITE_OPEN_FULLMUTEX :: 0x00010000

// SQLITE_TRANSIENT：bind 时让 sqlite 立即拷贝字符串，调用方可复用/释放自己的缓冲。
// C 里是 (void*)-1，用 uintptr 全 1 位表示再转 rawptr。
SQLITE_TRANSIENT :: cast(rawptr)~uintptr(0)

// 打开标志组合。FULLMUTEX：共享单连接跨 nbio 线程并发访问时强制串行化（见上注释 + ADR 0009）。
SQLITE_OPEN_FLAGS :: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

foreign import lib {
	"system:sqlite3",
}

foreign lib {
	sqlite3_open_v2     :: proc(filename: cstring, pp: ^^Sqlite3, flags: c.int, vfs: ^c.char) -> Code ---
	sqlite3_close       :: proc(db: ^Sqlite3) -> Code ---
	sqlite3_exec        :: proc(db: ^Sqlite3, sql: cstring, cb: rawptr, arg: rawptr, err: ^^c.char) -> Code ---

	sqlite3_prepare_v2  :: proc(db: ^Sqlite3, sql: cstring, nbyte: c.int, pp: ^^Stmt, tail: ^^c.char) -> Code ---
	sqlite3_step        :: proc(stmt: ^Stmt) -> Code ---
	sqlite3_finalize    :: proc(stmt: ^Stmt) -> Code ---
	sqlite3_reset       :: proc(stmt: ^Stmt) -> Code ---

	sqlite3_column_text   :: proc(stmt: ^Stmt, col: c.int) -> cstring ---
	sqlite3_column_int    :: proc(stmt: ^Stmt, col: c.int) -> c.int ---
	sqlite3_column_int64  :: proc(stmt: ^Stmt, col: c.int) -> i64 ---
	sqlite3_column_double :: proc(stmt: ^Stmt, col: c.int) -> f64 ---
	sqlite3_column_bytes  :: proc(stmt: ^Stmt, col: c.int) -> c.int ---
	sqlite3_column_name   :: proc(stmt: ^Stmt, col: c.int) -> cstring ---

	sqlite3_bind_text   :: proc(stmt: ^Stmt, idx: c.int, text: cstring, n: c.int, destruct: rawptr) -> Code ---
	sqlite3_bind_int    :: proc(stmt: ^Stmt, idx: c.int, val: c.int) -> Code ---
	sqlite3_bind_int64  :: proc(stmt: ^Stmt, idx: c.int, val: i64) -> Code ---
	sqlite3_bind_double :: proc(stmt: ^Stmt, idx: c.int, val: f64) -> Code ---
	sqlite3_bind_null   :: proc(stmt: ^Stmt, idx: c.int) -> Code ---

	sqlite3_last_insert_rowid :: proc(db: ^Sqlite3) -> i64 ---
	sqlite3_changes           :: proc(db: ^Sqlite3) -> c.int ---
	sqlite3_errmsg            :: proc(db: ^Sqlite3) -> cstring ---
	sqlite3_free              :: proc(p: ^c.char) ---
}
