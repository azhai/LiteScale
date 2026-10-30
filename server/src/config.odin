package main

import "core:fmt"
import "core:os"

VERSION :: "1.0.5"

Config :: struct {
	addr:        string,
	data_dir:    string,
	db_path:     string,
	log_dir:     string,
	token_file:  string,
	enroll_key:  string,
	admin_token: string,
	raw_log:     bool,
	max_body:    int,
}

print_usage :: proc() {
	fmt.eprintln(`litescale-server — LiteScale 数据上传服务

用法:
  litescale-server [-addr 0.0.0.0:9429] [-data ./data] [-enroll-key KEY] [-no-raw-log]

选项:
  -addr ADDR        监听地址，默认 0.0.0.0:9429
  -data DIR         数据目录（SQLite 库与 oboe 日志），默认 ./data
  -enroll-key KEY   客户端注册密钥；设置后 /api/v1/clients 需要 X-Enroll-Key
  -admin-token TK    管理台令牌；不传则读取/生成 <data>/admin_token
  -no-raw-log       关闭 oboe 原始批次日志
`)
}

parse_config :: proc() -> Config {
	cfg := Config {
		addr     = "0.0.0.0:9429",
		data_dir = "data",
		raw_log  = true,
		max_body = 8 << 20,
	}

	args := os.args[1:]
	i := 0
	for i < len(args) {
		arg := args[i]
		i += 1
		switch arg {
		case "-addr", "--addr":
			if i < len(args) {
				cfg.addr = args[i]
				i += 1
			}
		case "-data", "--data":
			if i < len(args) {
				cfg.data_dir = args[i]
				i += 1
			}
		case "-enroll-key", "--enroll-key":
			if i < len(args) {
				cfg.enroll_key = args[i]
				i += 1
			}
		case "-admin-token", "--admin-token":
			if i < len(args) {
				cfg.admin_token = args[i]
				i += 1
			}
		case "-no-raw-log":
			cfg.raw_log = false
		case "-h", "--help":
			print_usage()
			os.exit(0)
		case:
			fmt.eprintfln("未知参数 %q（-h 查看用法）", arg)
			os.exit(2)
		}
	}

	cfg.db_path = fmt.tprintf("%s/litescale.db", cfg.data_dir)
	cfg.log_dir = fmt.tprintf("%s/logs", cfg.data_dir)
	cfg.token_file = fmt.tprintf("%s/admin_token", cfg.data_dir)
	return cfg
}
