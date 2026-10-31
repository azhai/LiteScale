#!/usr/bin/env bash
# End-to-end check for litescale-server: registers a client, uploads batches
# twice (idempotency + content dedup), trips every validation branch, then
# exercises the admin API and the admin page.
set -euo pipefail

BIN=${1:-./bin/litescale-server}
PORT=${PORT:-19429}
BASE="http://127.0.0.1:${PORT}"
ADMIN="e2e-admin-token"
DATA=$(mktemp -d "${TMPDIR:-/tmp}/ls-e2e.XXXXXX")
PID=""

cleanup() {
	if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
		kill "$PID" 2>/dev/null || true
		wait "$PID" 2>/dev/null || true
	fi
	rm -rf "$DATA"
}
trap cleanup EXIT

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3 (got '$1', want '$2')"; pass "$3"; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
sha() { python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
jassert() { python3 -c "import json,sys;d=json.load(sys.stdin);assert $1, d"; }
jprint() { python3 -c "import json,sys;d=json.load(sys.stdin);print($1)"; }

[ -x "$BIN" ] || fail "binary not found: $BIN (run make build)"
"$BIN" -addr "127.0.0.1:${PORT}" -data "$DATA" -admin-token "$ADMIN" >"$DATA/server.log" 2>&1 &
PID=$!

ready=""
for _ in $(seq 1 60); do
	if curl -fsS "$BASE/api/v1/ping" >/dev/null 2>&1; then ready=1; break; fi
	sleep 0.1
done
[ -n "$ready" ] || { cat "$DATA/server.log" >&2; fail "server did not start on ${PORT}"; }
pass "server started"

# ---- static + bootstrap ---------------------------------------------------
curl -fsS "$BASE/api/v1/ping" | jassert "d['ok'] and d['version']=='1.0.8'"
pass "ping"

eq "$(code "$BASE/admin/")" 200 "admin page"
HTML=$(curl -fsS "$BASE/admin/")
case "$HTML" in *"LiteScale 控制台"*) pass "admin page embeds UI" ;; *) fail "admin page missing title" ;; esac
eq "$(code "$BASE/admin/alpine.js")" 200 "admin alpine.js"
eq "$(code "$BASE/")" 302 "root redirects to /admin/"
eq "$(code "$BASE/api/v1/admin/overview")" 401 "admin requires token"

# ---- register -------------------------------------------------------------
python3 - "$DATA/reg.json" <<'PY'
import json,sys
json.dump({"id":"client-e2e-001","name":"端到端","app_version":"1.0.8","platform":"ios","lang":"zh"},
          open(sys.argv[1],"w"), ensure_ascii=False)
PY
curl -fsS -X POST "$BASE/api/v1/clients" -H 'Content-Type: application/json' \
	--data-binary @"$DATA/reg.json" >"$DATA/reg.out"
TOKEN=$(jprint "d['token']" <"$DATA/reg.out")
[ ${#TOKEN} -eq 64 ] || fail "register token length"
pass "client registered"

auth() { curl -sS -H "Authorization: Bearer $TOKEN" "$@"; }
admin() { curl -sS -H "Authorization: Bearer $ADMIN" "$@"; }

# ---- ingest ---------------------------------------------------------------
python3 - "$DATA/batch1.json" <<'PY'
import json,sys
p = {
  "schema_version": 1,
  "client": {"id":"client-e2e-001","name":"端到端","app_version":"1.0.8","platform":"ios","lang":"zh"},
  "devices": [{"id":"scale-1","name":"体脂秤","last_seen":1793332000000}],
  "members": [
    {"id":"m1","name":"阿债","avatar":"🐷","color":5337227,"height_cm":172,"gender":"female","birth":"1990-05","updated_at":1793332000000},
    {"id":"m2","name":"小美","avatar":"🐱","color":14204461,"height_cm":160,"gender":"male","birth":"1985-11","updated_at":1793332000000}
  ],
  "members_snapshot": True,
  "goal": {"cleared": False, "member_id": "m1", "kg": 72.5, "updated_at": 1793332000000},
  "goals_snapshot": True,
  "goals": [
    {"member_id":"m1","date":"2026-10-29","kg":70.0,"actual_kg":72.30,"updated_at":1793332000000},
    {"member_id":"m2","date":"2026-10-28","kg":54.0,"actual_kg":55.20,"updated_at":1793332000000},
    {"member_id":"m2","date":"2026-10-29","kg":53.5,"actual_kg":55.10,"updated_at":1793332000000},
    {"member_id":"ghost","date":"2026-10-29","kg":60.0,"actual_kg":0,"updated_at":1793332000000}
  ],
  "records": [
    {"t":1793331000000,"kg":72.35,"m":"m1","d":"scale-1"},
    {"t":1793331100000,"kg":72.30,"m":"m1","d":"scale-1"},
    {"t":1793331200000,"kg":55.20,"m":"m2","d":"scale-1"}
  ]
}
json.dump(p, open(sys.argv[1],"w"), ensure_ascii=False)
PY

ingest() { auth -X POST "$BASE/api/v1/ingest" -H 'Content-Type: application/json' \
	-H "X-Idempotency-Key: $1" -H "X-Body-Sha256: $(sha "$2")" --data-binary @"$2"; }

ingest batch-0001 "$DATA/batch1.json" >"$DATA/r1.json"
jassert "d['accepted']==3 and d['duplicates']==0 and d['duplicate']==False" <"$DATA/r1.json"
pass "batch accepted 3 records"

ingest batch-0001 "$DATA/batch1.json" >"$DATA/r2.json"
jassert "d['duplicate']==True and d['accepted']==3" <"$DATA/r2.json"
pass "same idempotency key replays as duplicate batch"

# Same records, new batch id: content-derived uid makes them all duplicates.
ingest batch-0001-again "$DATA/batch1.json" >"$DATA/r3.json"
jassert "d['duplicate']==False and d['accepted']==0 and d['duplicates']==3" <"$DATA/r3.json"
pass "same records in a new batch dedup by content uid"

python3 - "$DATA/batch2.json" <<'PY'
import json,sys
p = {
  "schema_version": 1,
  "client": {"id":"client-e2e-001","name":"端到端","app_version":"1.0.8","platform":"ios","lang":"zh"},
  "devices": [], "members": [],
  "goal": {"cleared": False, "member_id": "m1", "kg": 70, "updated_at": 1793332000000},
  "records": [
    {"t":1793331200000,"kg":55.20,"m":"m2","d":"scale-1"},
    {"t":1793331300000,"kg":55.10,"m":"m2","d":"scale-1"}
  ]
}
json.dump(p, open(sys.argv[1],"w"), ensure_ascii=False)
PY
ingest batch-0002 "$DATA/batch2.json" >"$DATA/r4.json"
jassert "d['accepted']==1 and d['duplicates']==1" <"$DATA/r4.json"
pass "overlapping record counted once"

# ---- ingest validation ----------------------------------------------------
eq "$(code -X POST "$BASE/api/v1/ingest" -H "Authorization: Bearer $TOKEN" \
	-H "X-Idempotency-Key: batch-0003" -H "X-Body-Sha256: $(printf 'a%.0s' $(seq 64))" \
	--data-binary @"$DATA/batch2.json")" 400 "checksum mismatch rejected"
eq "$(code -X POST "$BASE/api/v1/ingest" -H "Authorization: Bearer $TOKEN" \
	-H "X-Body-Sha256: $(sha "$DATA/batch2.json")" --data-binary @"$DATA/batch2.json")" 400 "missing idempotency key rejected"
eq "$(code -X POST "$BASE/api/v1/ingest" -H "Authorization: Bearer wrong" \
	-H "X-Idempotency-Key: batch-0004" -H "X-Body-Sha256: $(sha "$DATA/batch2.json")" \
	--data-binary @"$DATA/batch2.json")" 401 "bad token rejected"

python3 - "$DATA/batch3.json" <<'PY'
import json,sys
p = {
  "schema_version": 1,
  "client": {"id":"other-client","name":"x","app_version":"1.0.8","platform":"ios","lang":"zh"},
  "devices": [], "members": [],
  "goal": {"cleared": False, "kg": 0, "updated_at": 0},
  "records": []
}
json.dump(p, open(sys.argv[1],"w"))
PY
eq "$(code -X POST "$BASE/api/v1/ingest" -H "Authorization: Bearer $TOKEN" \
	-H "X-Idempotency-Key: batch-0005" -H "X-Body-Sha256: $(sha "$DATA/batch3.json")" \
	--data-binary @"$DATA/batch3.json")" 403 "client id must match token"

python3 - "$DATA/batch4.json" <<'PY'
import json,sys
p = {
  "schema_version": 1,
  "client": {"id":"client-e2e-001","name":"端到端","app_version":"1.0.8","platform":"ios","lang":"zh"},
  "devices": [], "members": [],
  "goal": {"cleared": False, "kg": 0, "updated_at": 0},
  "records": [
    {"t":1793331400000,"kg":60.0,"m":"ghost","d":"scale-1"},
    {"t":1793331500000,"kg":900.0,"m":"m1","d":"scale-1"},
    {"t":1,"kg":60.0,"m":"m1","d":"scale-1"}
  ]
}
json.dump(p, open(sys.argv[1],"w"), ensure_ascii=False)
PY
ingest batch-0006 "$DATA/batch4.json" >"$DATA/r5.json"
jassert "d['accepted']==0 and len(d['rejected'])==3 and d['duplicates']==0" <"$DATA/r5.json"
pass "unknown member / bad weight / bad timestamp rejected"

auth "$BASE/api/v1/clients/me" | jassert "d['measurements']==4 and d['members']==2 and d['devices']==1 and d['last_ts']==1793331300000"
pass "client summary"

# ---- admin read -----------------------------------------------------------
admin "$BASE/api/v1/admin/overview" >"$DATA/ov.json"
jassert "d['clients']==1 and d['members']==2 and d['devices']==1 and d['measurements']==4 and d['goals']==3 and d['batches']==4 and d['db_bytes']>0" <"$DATA/ov.json"
pass "admin overview"

admin "$BASE/api/v1/admin/clients?q=%E7%AB%AF%E5%88%B0%E7%AB%AF" | jassert "d['total']==1 and d['items'][0]['id']=='client-e2e-001'"
pass "admin client search"

admin "$BASE/api/v1/admin/clients/client-e2e-001" >"$DATA/detail.json"
jassert "len(d['members'])==2 and len(d['devices'])==1 and d['goal']['set'] and d['stats']['measurements']==4" <"$DATA/detail.json"
pass "admin client detail"
jassert "next(m for m in d['members'] if m['id']=='m1')['height_cm']==172" <"$DATA/detail.json"
pass "member height stored"
jassert "next(m for m in d['members'] if m['id']=='m1')['gender']=='female' and next(m for m in d['members'] if m['id']=='m1')['birth']=='1990-05'" <"$DATA/detail.json"
pass "member gender and birth stored"
jassert "len(d['goals'])==3 and next(g for g in d['goals'] if g['member_id']=='m1' and g['date']=='2026-10-29')['actual_kg']==72.30" <"$DATA/detail.json"
pass "goals snapshot stored with actual weight"

admin "$BASE/api/v1/admin/measurements?member_id=m2" | jassert "d['total']==2"
pass "measurement filter by member"
admin "$BASE/api/v1/admin/measurements?from=1793331150000&to=1793331250000" | jassert "d['total']==1 and d['items'][0]['kg']==55.2"
pass "measurement filter by time range"
admin "$BASE/api/v1/admin/measurements?q=%E4%BD%93%E8%84%82" | jassert "d['total']==4"
pass "measurement free-text filter (device name)"
admin "$BASE/api/v1/admin/batches" | jassert "d['total']==4"
pass "batch list"

CSV=$(admin "$BASE/api/v1/admin/measurements.csv")
echo "$CSV" | head -1 | grep -q "ts,client_id,device_id,device_name,member_id,member_name,kg" || fail "csv header"
echo "$CSV" | grep -m1 -E '^[0-9]' | grep -Eq '^[0-9]+\.[0-9]{3},' || fail "csv ts keeps 3 decimals"
eq "$(echo "$CSV" | grep -c '^[0-9]')" 4 "csv rows"
pass "csv export"

# ---- admin write ----------------------------------------------------------
admin -X POST "$BASE/api/v1/admin/clients/client-e2e-001/members/m1" \
	-H 'Content-Type: application/json' -d '{"name":"阿债(改)","avatar":"🐻","color":3050327,"height_cm":173,"gender":"male","birth":"1990-06"}' \
	| jassert "d['ok']"
admin "$BASE/api/v1/admin/clients/client-e2e-001" \
	| jassert "any(m['name']=='阿债(改)' and m['height_cm']==173 and m['gender']=='male' and m['birth']=='1990-06' for m in d['members'])"
pass "member rename + body data"
eq "$(code -X POST "$BASE/api/v1/admin/clients/client-e2e-001/members/m1" \
	-H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
	-d '{"name":"阿债(改)","gender":"x"}')" 400 "invalid gender rejected"
eq "$(code -X POST "$BASE/api/v1/admin/clients/client-e2e-001/members/m1" \
	-H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
	-d '{"name":"阿债(改)","birth":"1990-13"}')" 400 "invalid birth month rejected"

# Per-member goal endpoint: upsert, keep actual, reject bad input, delete.
admin -X PUT "$BASE/api/v1/admin/clients/client-e2e-001/members/m1/goals/2026-11-15" \
	-H 'Content-Type: application/json' -d '{"cleared":false,"kg":69}' | jassert "d['ok']"
admin "$BASE/api/v1/admin/clients/client-e2e-001" | jassert "len(d['goals'])==4 and any(g['date']=='2026-11-15' and abs(g['target_kg']-69)<0.001 for g in d['goals'])"
pass "member goal added"
admin -X PUT "$BASE/api/v1/admin/clients/client-e2e-001/members/m1/goals/2026-10-29" \
	-H 'Content-Type: application/json' -d '{"cleared":false,"kg":71.5}' | jassert "d['ok']"
admin "$BASE/api/v1/admin/clients/client-e2e-001" \
	| jassert "next(g for g in d['goals'] if g['date']=='2026-10-29' and g['member_id']=='m1')['actual_kg']==72.30"
pass "goal edit keeps client actual weight"
eq "$(code -X PUT "$BASE/api/v1/admin/clients/client-e2e-001/members/m1/goals/2026-11-15" \
	-H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' -d '{"cleared":false,"kg":999}')" 400 "member goal range check"
eq "$(code -X PUT "$BASE/api/v1/admin/clients/client-e2e-001/members/m1/goals/2026-13-01" \
	-H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' -d '{"cleared":false,"kg":69}')" 400 "member goal date check"
admin -X PUT "$BASE/api/v1/admin/clients/client-e2e-001/members/m1/goals/2026-11-15" \
	-H 'Content-Type: application/json' -d '{"cleared":true}' | jassert "d['ok']"
admin "$BASE/api/v1/admin/clients/client-e2e-001" | jassert "len(d['goals'])==3"
pass "member goal deleted"

admin -X PUT "$BASE/api/v1/admin/clients/client-e2e-001/goal" \
	-H 'Content-Type: application/json' -d '{"cleared":false,"kg":68.4}' | jassert "d['ok']"
admin "$BASE/api/v1/admin/clients/client-e2e-001" | jassert "d['goal']['set'] and abs(d['goal']['kg']-68.4)<0.001"
pass "goal update"
eq "$(code -X PUT "$BASE/api/v1/admin/clients/client-e2e-001/goal" \
	-H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' -d '{"cleared":false,"kg":999}')" 400 "goal range check"
admin -X PUT "$BASE/api/v1/admin/clients/client-e2e-001/goal" \
	-H 'Content-Type: application/json' -d '{"cleared":true}' | jassert "d['ok']"
admin "$BASE/api/v1/admin/clients/client-e2e-001" | jassert "not d['goal']['set']"
pass "goal clear"

MUID=$(admin "$BASE/api/v1/admin/measurements?limit=1" | jprint "d['items'][0]['uid']")
admin -X DELETE "$BASE/api/v1/admin/measurements?uid=${MUID}" | jassert "d['deleted']==1"
admin "$BASE/api/v1/admin/overview" | jassert "d['measurements']==3"
pass "measurement delete"

# ---- measurement edit / bulk delete / csv import --------------------------
admin "$BASE/api/v1/admin/measurements?member_id=m1&limit=1" >"$DATA/m1.json"
MUID=$(jprint "d['items'][0]['uid']" <"$DATA/m1.json")
MTS=$(jprint "d['items'][0]['ts_ms']" <"$DATA/m1.json")
admin -X PUT "$BASE/api/v1/admin/measurements/${MUID}" -H 'Content-Type: application/json' \
	-d "{\"ts_ms\":$MTS,\"kg\":72.25,\"member_id\":\"m1\"}" >"$DATA/edit.json"
jassert "d['ok'] and d['uid']!='$MUID'" <"$DATA/edit.json"
NEW_UID=$(jprint "d['uid']" <"$DATA/edit.json")
pass "measurement edit recomputes uid"

admin "$BASE/api/v1/admin/measurements?member_id=m1" >"$DATA/m1b.json"
jassert "any(abs(i['kg']-72.25)<0.001 for i in d['items'])" <"$DATA/m1b.json"
OTHER_TS=$(jprint "min(i['ts_ms'] for i in d['items'] if abs(i['kg']-72.25)>0.001)" <"$DATA/m1b.json")
OTHER_KG=$(jprint "min(i['kg'] for i in d['items'] if abs(i['kg']-72.25)>0.001)" <"$DATA/m1b.json")
printf '{"ts_ms":%s,"kg":%s,"member_id":"m1"}' "$OTHER_TS" "$OTHER_KG" >"$DATA/conflict.json"
eq "$(code -X PUT "$BASE/api/v1/admin/measurements/${NEW_UID}" -H "Authorization: Bearer $ADMIN" \
	-H 'Content-Type: application/json' --data-binary @"$DATA/conflict.json")" 409 "duplicate edit conflicts"

# bulk delete both m1 rows, leaving the single m2 row
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({'uids':[i['uid'] for i in d['items']]}))" \
	"$DATA/m1b.json" >"$DATA/bulk.json"
admin -X DELETE "$BASE/api/v1/admin/measurements" -H 'Content-Type: application/json' \
	--data-binary @"$DATA/bulk.json" | jassert "d['deleted']==2"
admin "$BASE/api/v1/admin/overview" | jassert "d['measurements']==1"
pass "bulk delete by uid list"
python3 -c 'import json; print(json.dumps({"uids":["x"]*501}))' >"$DATA/uids501.json"
eq "$(code -X DELETE "$BASE/api/v1/admin/measurements" -H "Authorization: Bearer $ADMIN" \
	-H 'Content-Type: application/json' --data-binary @"$DATA/uids501.json")" 400 "bulk delete rejects >500 uids"
pass "bulk delete cap enforced"

# Compatibility: legacy header names (timestamp/weight_kg) and integer
# seconds/milliseconds still import after the canonical lookup fails.
cat >"$DATA/import.csv" <<'CSV'
timestamp,client_id,device_id,member_id,member_name,weight_kg
1793332000,client-e2e-001,scale-1,m2,小美,70.10
1793332100000,,scale-1,m1,阿债(改),70.05
1793332200,unknown-client,scale-1,m1,x,70.00
CSV
admin -X POST "$BASE/api/v1/admin/measurements/import?client_id=client-e2e-001" \
	-H 'Content-Type: text/csv' --data-binary @"$DATA/import.csv" >"$DATA/imp.json"
jassert "d['total']==3 and d['imported']==2 and d['duplicates']==0 and len(d['rejected'])==1 and d['rejected'][0]['index']==4 and d['members_created']==0" <"$DATA/imp.json"
pass "csv import with fallback client"
admin -X POST "$BASE/api/v1/admin/measurements/import?client_id=client-e2e-001" \
	-H 'Content-Type: text/csv' --data-binary @"$DATA/import.csv" >"$DATA/imp2.json"
jassert "d['imported']==0 and d['duplicates']==2 and len(d['rejected'])==1" <"$DATA/imp2.json"
admin "$BASE/api/v1/admin/overview" | jassert "d['measurements']==3"
pass "csv re-import dedups"

cat >"$DATA/import-canonical.csv" <<'CSV'
ts,client_id,device_id,device_name,member_id,member_name,kg
1793332300.750,client-e2e-001,scale-2,新秤,m1,阿债(改),70.02
CSV
admin -X POST "$BASE/api/v1/admin/measurements/import" \
	-H 'Content-Type: text/csv' --data-binary @"$DATA/import-canonical.csv" >"$DATA/imp3.json"
jassert "d['total']==1 and d['imported']==1 and d['duplicates']==0 and len(d['rejected'])==0" <"$DATA/imp3.json"
admin "$BASE/api/v1/admin/overview" | jassert "d['measurements']==4"
pass "csv import canonical schema, client from column only"
# An unknown device id becomes a device row carrying the file's display name,
# so exporting after importing is lossless.
admin "$BASE/api/v1/admin/measurements.csv" >"$DATA/after-import.csv"
grep -q "scale-2,新秤" "$DATA/after-import.csv" || fail "csv import keeps device name"
pass "csv import keeps device name"

# ---- rate limit (120/min per client) --------------------------------------
limited=0
for _ in $(seq 1 130); do
	c=$(code -X POST "$BASE/api/v1/ingest" -H "Authorization: Bearer $TOKEN" \
		-H "X-Idempotency-Key: batch-0001" -H "X-Body-Sha256: $(sha "$DATA/batch1.json")" \
		--data-binary @"$DATA/batch1.json")
	[ "$c" = "429" ] && limited=$((limited + 1))
done
[ "$limited" -gt 0 ] || fail "rate limit never triggered"
pass "rate limit returns 429 (${limited} requests)"

# ---- purge ----------------------------------------------------------------
admin -X DELETE "$BASE/api/v1/admin/clients/client-e2e-001" | jassert "d['ok'] and d['deleted']==4"
admin "$BASE/api/v1/admin/overview" | jassert "d['clients']==0 and d['members']==0 and d['devices']==0 and d['measurements']==0 and d['batches']==0 and d['goals']==0"
pass "purge removes every table for the client"

echo "all e2e checks passed"
