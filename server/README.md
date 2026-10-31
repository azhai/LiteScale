# LiteScale Server

Odin + [opus](https://github.com/odin-lang/opus) HTTP 服务，接收 LiteScale 客户端上传的成员（含身高）、按日期目标、设备与测量数据，并提供内置 Web 管理台。

## 架构

```
Flutter 客户端 ──HTTPS/1.1 JSON 批量──▶ opus (路由/连接池)
                                        │
                      ┌─────────────────┼──────────────────┐
                      ▼                 ▼                  ▼
               SQLite (权威存储)   oboe 原始批次日志    oboe 内存缓存
               去重/事务/查询      追查与审计          限流计数器
```

- **SQLite 是唯一权威存储。** oboe 的 store 是追加写的列式日志，不支持按主键更新、事务和多维查询，适合留存原始批次而不适合做业务库。两者职责分离：写入走 `BEGIN IMMEDIATE` 事务，审计留痕走 oboe。
- 所有写操作串行化在一把互斥锁内；读操作同样加锁（SQLite 连接为 FULLMUTEX + WAL）。单机可稳稳支撑每秒数百批的上传；再往上应换 PostgreSQL/分片，而不是改缓存层。
- 选 HTTP/1.1 批量 JSON 而不是 MQTT/HTTP3/UDP：客户端的网络需求是低频、可重试、需要强一致确认，HTTP 自带幂等头+状态码即可表达"收到/重复/拒绝"，无需再引入消息中间件与乱序补偿。

## 数据模型

| 表 | 主键 | 说明 |
|---|---|---|
| `clients` | `id` | 客户端安装实例，`token_hash` 只存 SHA-256 |
| `devices` | `(client_id, id)` | 体重秤，`last_seen` 取最大值合并 |
| `members` | `(client_id, id)` | 家庭成员，`updated_at` 由服务端落时间 |
| `member_profiles` | `(client_id, member_id)` | 成员身高（cm），缺失表示未设置 |
| `member_details` | `(client_id, member_id)` | 成员性别（`female`/`male`）与出生年月（`yyyy-MM`），空串表示未设置 |
| `member_goals` | `(client_id, member_id, date)` | 每个成员每天一个目标；`actual_kg` 是客户端当天最后一条体重 |
| `goals` | `client_id` | **旧版**单目标，仅兼容旧客户端；新客户端上传快照时清空 |
| `measurements` | `uid` | 内容寻址主键，见下节 |
| `batches` | `id` | 幂等批次记录，留存载荷 SHA-256 |

## 完整性与去重

客户端必须发送：

| 头 | 校验 |
|---|---|
| `Authorization: Bearer <token>` | 每安装令牌，注册时下发，服务端只存哈希 |
| `X-Idempotency-Key` | 8–128 字符，`[A-Za-z0-9-_:.|]`，整批重放直接返回首次结果 |
| `X-Body-Sha256` | 64 位十六进制，必须等于原始请求体的 SHA-256 |

记录级：

- `measurements.uid = sha256("litescale/record/v1\n<client>\n<member>\n<device>\n<ts_ms>\n<kg %.3f>")`，`INSERT ... ON CONFLICT DO NOTHING`。同一测量换批次重传也是空操作，响应里的 `accepted` / `duplicates` 如实反映结果。
- 校验：`schema_version` 必须为 1；客户端 ID 必须与令牌绑定；`client.id` 必须等于令牌归属；记录时间在 2000-01-01 与「服务端当前时间 + 24h」之间；体重 `0 < kg ≤ 500`；记录引用的成员必须已在同一批次或历史中出现。
- 批次级：单批 ≤ 500 条记录、≤ 64 成员、≤ 64 设备、≤ 512 目标，请求体 ≤ 8 MiB；每客户端 120 请求/分钟（超出返回 429）。
- 单批在事务内应用：成员、身高、性别/出生年月、目标、设备先写，再插记录，最后写批次行；任一步失败整批回滚，客户端可原样重试。
- 身高 `0 < cm ≤ 300`；`0`/缺省表示「本构建未设置」，不会覆盖服务端已有身高。
- 性别只接受 `female`/`male`/空；出生年月为 `yyyy-MM`（1900–2100）。`members_snapshot: true` 时空串会清除性别/出生年月；旧客户端不带该字段时，空串表示「未修改」，不会抹掉新客户端已上传的值。
- `goals_snapshot: true` 时 `goals` 是完整快照：先删除该客户端全部目标（含旧版 `goals` 行），再写入快照。`date` 必须是 `yyyy-MM-dd`；`actual_kg` 超出有效范围时按 0 存。旧客户端不发送该字段时仍按 `goal` 单目标处理。

## 构建与运行

依赖 Odin（`dev-2026-10` 及以上）、clang、SQLite3。

```bash
make -C server build          # server/bin/litescale-server（内嵌管理台资源）
make -C server run            # 127.0.0.1:9429，数据在 ./server/data
./scripts/build_server.sh     # 同时复制到 dist/litescale-server-<version>-<os>-<arch>
```

`scripts/build_server.sh` 会校验 `server/src/config.odin` 的 `VERSION` 与 `pubspec.yaml` 一致；管理台 HTML 与 Alpine.js 通过 `#load` 在编译期嵌入二进制，部署时只需拷贝单个可执行文件。
./server/bin/litescale-server \
  -addr 0.0.0.0:9429 \
  -data /var/lib/litescale \
  -admin-token '换成一串随机值' \
  -enroll-key '可选的注册码'
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `-addr` | `0.0.0.0:9429` | 监听地址 |
| `-data` | `./data` | SQLite 库、oboe 日志、管理令牌文件 |
| `-admin-token` | 自动生成 | 管理台/管理 API 令牌，不传则读或生成 `<data>/admin_token` |
| `-enroll-key` | 空 | 设置后 `/api/v1/clients` 必须带 `X-Enroll-Key` |
| `-no-raw-log` | 关 | 关闭 oboe 原始批次日志 |

启动日志会打印管理台地址与令牌（脱敏）。

## 客户端 API

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/v1/ping` | 健康检查 |
| POST | `/api/v1/clients` | 注册：`{id,name,app_version,platform,lang}` → `{client_id,token}`；同 ID 再次注册会轮换令牌 |
| POST | `/api/v1/ingest` | 上传批次（见上节头要求） |
| GET | `/api/v1/clients/me` | 本次安装的服务器端统计 |

批次体（`schema_version` 为 1）：

```json
{
  "schema_version": 1,
  "client":  {"id": "c-macos-1a2b3c4d", "name": "LiteScale · macOS", "app_version": "1.0.8", "platform": "macos", "lang": "zh"},
  "devices": [{"id": "C0:FF:EE:12:34:56", "name": "OKOK S3", "last_seen": 1761792000000}],
  "members": [{"id": "me", "name": "我", "avatar": "a15", "color": 0, "height_cm": 172, "gender": "female", "birth": "1990-05", "updated_at": 0}],
  "members_snapshot": true,
  "goal":    {"cleared": false, "member_id": "me", "kg": 68.5, "updated_at": 0},
  "goals_snapshot": true,
  "goals":   [
    {"member_id": "me", "date": "2026-11-30", "kg": 68.5, "actual_kg": 70.8, "updated_at": 0},
    {"member_id": "me", "date": "2026-10-29", "kg": 69.0, "actual_kg": 70.4, "updated_at": 0}
  ],
  "records": [{"t": 1761792000000, "kg": 70.8, "m": "me", "d": "C0:FF:EE:12:34:56"}]
}
```

响应：

```json
{"ok": true, "batch_id": "b-<sha256>", "accepted": 1, "duplicates": 0,
 "rejected": [], "duplicate": false, "server_time": 1761792001000}
```

`rejected` 为 `[{"index": 0, "reason": "weight out of range"}]`，被拒记录不影响同批其它记录。

## Web 管理台

浏览器打开 `http://<host>:9429/admin/`，粘贴 `-admin-token`（或 `<data>/admin_token`）进入；令牌存放在 localStorage，可随时「退出」。

- **概览**：客户端/成员/设备/测量/目标/批次计数、库大小、最近批次与最近测量。
- **客户端**：搜索；每行末尾的「详情」按钮与整行点击都能打开抽屉。抽屉里可改成员昵称/头像/颜色/身高/性别/出生年月（成员 ID 不在列表显示，也不可编辑），按成员和日期增删改目标，以及整客户端清除（事务内删测量/批次/目标/身高/性别/出生年月/成员/设备）。旧版单目标若仍存在会单独列出并可清除。
- **测量**：按客户端、成员、设备、时间范围、关键词过滤；单条/批量删除（勾选行或全选本页）；编辑测量时间、体重与成员（按内容重算 `uid`，与已有记录重复时拒绝并返回 409，接收时间保持不变）；导入 CSV（可选默认客户端，未知客户端整行拒绝，重复记录自动跳过，可按 `member_name` 自动建成员）；导出 CSV（带 BOM，`LIMIT 100000`）。
- **批次**：按客户端查看幂等批次、接收时间、载荷哈希、接受/重复计数。

管理 API 与页面同源：`/api/v1/admin/{overview,clients,measurements,batches}`，全部要求 `Authorization: Bearer <admin token>`。写入接口：

| 方法 | 路径 | 说明 |
|---|---|---|
| `PUT` | `/api/v1/admin/measurements/:uid` | 改时间/体重/成员；重新计算内容 `uid`，重复内容返回 409 |
| `DELETE` | `/api/v1/admin/measurements?uid=...` | 删除单条 |
| `DELETE` | `/api/v1/admin/measurements`（JSON `{"uids":[...]}`，≤500） | 批量删除，返回实际删除数 |
| `POST` | `/api/v1/admin/clients/:cid/members/:mid` | 修改成员 `{"name","avatar","color","height_cm","gender","birth"}`；`height_cm:0`、空 `gender`/`birth` 清除对应字段 |
| `PUT` | `/api/v1/admin/clients/:cid/members/:mid/goals/:date` | 新增/修改（`{"kg":68.5}`）或删除（`{"cleared":true}`）某个成员某天的目标；`date` 为 `yyyy-MM-dd` |
| `POST` | `/api/v1/admin/measurements/import?client_id=...` | 原始 CSV 请求体；`client_id` 作为缺省客户端；返回 `total/imported/duplicates/members_created/rejected[{index,reason}]` |

CSV 规范表头（App、小程序、服务端导出共用）：

```
ts,client_id,device_id,device_name,member_id,member_name,kg
```

`ts` 为 Unix 秒级时间戳、固定三位小数（如 `1793332000.500`），`kg` 为千克；`client_id` 可省略（用查询参数兜底）。导入先按规范列名取列，最后才走兼容层：旧表头（`ts_ms`/`timestamp`/`time`/`t`/`weight_kg`/`weight`）与整数毫秒时间戳仍可导入。`member_name` 缺失时会按名建成员；未知的 `device_id` 会建设备行并记下 `device_name`，空名不会覆盖已有设备名。页面资源（Alpine.js 3.17.5）已内嵌进二进制，修改 `src/ui/` 后需 `make build` 重新编译。

## 部署

- **务必置于 TLS 反向代理之后**（Caddy/Nginx）：客户端默认走 `https://`，令牌与体重数据不应明文过网。Caddy 示例：

  ```
  scale.example.com {
      reverse_proxy 127.0.0.1:9429
  }
  ```

- 备份只需复制 `<data>/litescale.db*`（WAL 模式下连同 `-wal`、`-shm` 一起，或先执行 `sqlite3 litescale.db ".backup ..."`）。
- 删除遵循"客户端清除"语义：管理台删客户端会级联删数据；客户端侧删除本地记录不会同步到服务器（上传是只增流）。

## 客户端上传开关

App「设置 → 上传到服务器」：

1. 服务器地址默认 `https://sc.xi-yun.top/`（443 端口），自建部署时改成自己的域名；如需注册码一并填写；
2. 打开开关即注册并全量同步（每次最多 300 条一批，按时间游标推进）；
3. 之后新增/修改数据会自动在 5 秒防抖后同步；「立即同步」可手动触发；
4. 「重新绑定」会丢弃本地令牌并在下次同步时重新注册。

每次请求的幂等键是请求体 SHA-256，因此断网重试、重复点击都不会产生重复记录。

## 测试

```bash
make -C server test              # 端到端：真实二进制 + curl，35+ 断言
flutter test                     # 含 test/upload_e2e_test.dart：真实客户端 → 真实服务端
```
