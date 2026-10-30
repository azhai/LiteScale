package main

import "core:fmt"
import "core:os"
import "core:strings"

import web "../vendor/opus"
import oboe "../vendor/oboe"
import db "../lib/db"

main :: proc() {
	cfg := parse_config()
	G.cfg = cfg

	if !ensure_dir(cfg.data_dir) {
		fmt.eprintfln("无法创建数据目录 %s", cfg.data_dir)
		os.exit(1)
	}
	if cfg.raw_log && !ensure_dir(cfg.log_dir) {
		fmt.eprintfln("无法创建日志目录 %s", cfg.log_dir)
		os.exit(1)
	}

	conn, opened := db.open(cfg.db_path)
	if !opened {
		fmt.eprintfln("无法打开数据库 %s: %s", cfg.db_path, db.last_error(&conn))
		os.exit(1)
	}
	G.conn = conn
	defer db.close(&G.conn)

	if !db.exec(&G.conn, SCHEMA_SQL) {
		fmt.eprintfln("初始化数据库失败: %s", db.last_error(&G.conn))
		os.exit(1)
	}
	fmt.printfln("SQLite: %s", cfg.db_path)

	cache_cfg := oboe.default_cache_config()
	cache_cfg.max_bytes = 64 << 20
	G.cache = oboe.cache_init(cache_cfg)
	defer oboe.cache_destroy(G.cache)

	if cfg.raw_log {
		store_cfg := oboe.default_store_config()
		store_cfg.data_path = cfg.log_dir
		store_cfg.stream_fields = []string{"client_id"}
		G.log_fields = store_cfg.stream_fields
		G.log_store = oboe.store_init(store_cfg, true)
		if G.log_store == nil {
			fmt.eprintfln("oboe 日志初始化失败，已禁用原始批次日志")
		} else {
			fmt.printfln("oboe 日志: %s（可用 LogsQL 查询 /insert/jsonline 同源数据）", cfg.log_dir)
		}
	}
	defer {
		if G.log_store != nil {
			oboe.store_close(G.log_store)
		}
	}

	load_admin_token(&cfg)
	fmt.printfln("管理台: http://%s/admin/  （Bearer %s）", cfg.addr, mask_token(G.admin_token))

	register_routes()

	if !web.server_init(&G.srv, cfg.addr) {
		fmt.eprintfln("无法监听 %s", cfg.addr)
		os.exit(1)
	}
	G.srv.max_body_size = cfg.max_body
	G.srv.max_conns = 4096
	G.srv.handler = web.router_handle
	G.srv.user_ptr = &G.router

	fmt.printfln("LiteScale server %s 监听 %s", VERSION, cfg.addr)
	if err := web.server_run(&G.srv); err != nil {
		fmt.eprintfln("server error: %v", err)
	}
	web.server_destroy(&G.srv)
}

// ensure_dir treats "already exists" as success; core:os reports it as an
// error from make_directory_all even when the directory is usable.
ensure_dir :: proc(path: string) -> bool {
	err := os.make_directory_all(path)
	return err == nil || err == .Exist
}

// load_admin_token prefers -admin-token, then the persisted token file, and
// otherwise generates one so the admin UI works on a fresh install.
load_admin_token :: proc(cfg: ^Config) {
	if cfg.admin_token != "" {
		G.admin_token = cfg.admin_token
		return
	}

	if data, err := os.read_entire_file_from_path(cfg.token_file, context.allocator); err == nil {
		defer delete(data)
		token := strings.trim_space(string(data))
		if token != "" {
			G.admin_token = strings.clone(token)
			return
		}
	}

	token := random_hex(24)
	if token == "" {
		fmt.eprintln("无法生成管理令牌")
		return
	}
	err := os.write_entire_file_from_string(cfg.token_file, token)
	if err != nil {
		fmt.eprintfln("无法写入 %s: %v（令牌仅本次有效）", cfg.token_file, err)
	} else {
		fmt.printfln("已生成管理令牌: %s（保存在 %s）", token, cfg.token_file)
	}
	G.admin_token = token
}

mask_token :: proc(token: string) -> string {
	if len(token) <= 6 {
		return "******"
	}
	return fmt.tprintf("%s…%s", token[:3], token[len(token) - 3:])
}
