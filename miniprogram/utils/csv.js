// CSV import / export. Keeps exactly the same columns as the Flutter app
// (lib/service/csv.dart) and the server:
//
//   ts,client_id,device_id,device_name,member_id,member_name,kg
//
// `ts` is Unix epoch seconds with exactly 3 decimals (millisecond precision).
// `client_id` is optional: the mini program has no uploader identity, so it is
// blank by default. Import maps columns by header name, ignores extra columns
// and skips rows without a valid timestamp / weight.

const store = require('./store');

const HEADER = 'ts,client_id,device_id,device_name,member_id,member_name,kg';

// Compatibility: headers written by older builds or third-party tools.
// Applied only after the canonical names, and never for new fields.
const TIME_HEADERS = ['ts', 'ts_ms', 't', 'timestamp_ms', 'timestamp', 'time'];
const LEGACY_HEADERS = {
  ts_ms: 'ts',
  t: 'ts',
  timestamp_ms: 'ts',
  timestamp: 'ts',
  time: 'ts',
  weight_kg: 'kg',
  weight: 'kg',
};

// Canonical `ts`: epoch seconds with exactly 3 decimals.
function formatTs(ms) {
  const sec = Math.floor(ms / 1000);
  let frac = String(ms - sec * 1000);
  while (frac.length < 3) frac = '0' + frac;
  return sec + '.' + frac;
}

// Canonical `ts` is epoch seconds with 3 decimals. Epoch milliseconds and
// ISO-8601 are accepted for compatibility with older exports.
function parseTime(raw) {
  const text = String(raw === null || raw === undefined ? '' : raw).trim();
  if (!text) return NaN;
  if (/^-?\d+(\.\d+)?$/.test(text)) {
    const value = Number(text);
    if (!isFinite(value)) return NaN;
    const ms = Math.abs(value) < 100000000000 ? value * 1000 : value;
    if (ms < 946684800000 || ms > 4102444800000) return NaN;
    return Math.round(ms);
  }
  return Date.parse(text);
}

function normalizeHeader(value) {
  return String(value === null || value === undefined ? '' : value)
    .replace(/^\ufeff/, '')
    .trim()
    .toLowerCase();
}

function at(cells, index) {
  return index >= 0 && index < cells.length ? String(cells[index]).trim() : '';
}

function escapeCell(value) {
  const text = String(value === null || value === undefined ? '' : value);
  if (text.indexOf(',') >= 0 || text.indexOf('"') >= 0 || text.indexOf('\n') >= 0) {
    return '"' + text.replace(/"/g, '""') + '"';
  }
  return text;
}

function splitLine(line) {
  const out = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch === ',' && !inQuotes) {
      out.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  out.push(current);
  return out;
}

function build(records, clientId) {
  const lines = [HEADER];
  records.forEach((r) => {
    lines.push(
      [
        formatTs(r.t),
        escapeCell(clientId || ''),
        escapeCell(r.d || ''),
        escapeCell(r.d ? store.deviceName(r.d) : ''),
        escapeCell(r.m || store.DEFAULT_MEMBER_ID),
        escapeCell(store.memberName(r.m || store.DEFAULT_MEMBER_ID)),
        Number(r.kg).toFixed(3),
      ].join(',')
    );
  });
  return lines.join('\n') + '\n';
}

// Returns { records, newMembers, deviceNames }; newMembers holds names that do
// not exist yet and are referenced as `pending:<name>` in the rows, deviceNames
// maps device ids to the display labels declared in the file.
function parse(text) {
  const byKey = {};
  store.getMembers().forEach((m) => {
    byKey[m.id] = m.id;
    byKey[m.name] = m.id;
  });

  const records = [];
  const newMembers = [];
  const deviceNames = {};
  const lines = String(text || '')
    .split(/\r?\n/)
    .filter((line) => line.trim().length);
  if (!lines.length) return { records, newMembers, deviceNames };

  // Canonical columns first; compatibility aliases are applied last, so the
  // schema above stays the import contract. Headerless files fall back to the
  // positional layout of the original export.
  const first = splitLine(lines[0]);
  const hasHeader = first.some(
    (cell) => TIME_HEADERS.indexOf(normalizeHeader(cell)) >= 0
  );
  const cols = {};
  if (hasHeader) {
    first.forEach((cell, i) => {
      cols[normalizeHeader(cell)] = i;
    });
    Object.keys(LEGACY_HEADERS).forEach((from) => {
      const to = LEGACY_HEADERS[from];
      if (cols[from] !== undefined && cols[to] === undefined) cols[to] = cols[from];
    });
  }
  const timeCol = hasHeader ? (cols.ts === undefined ? -1 : cols.ts) : 0;
  if (timeCol < 0) return { records, newMembers, deviceNames };
  const kgCol = hasHeader ? (cols.kg === undefined ? -1 : cols.kg) : -1;
  const deviceCol = hasHeader ? (cols.device_id === undefined ? -1 : cols.device_id) : 1;
  const deviceNameCol = hasHeader ? (cols.device_name === undefined ? -1 : cols.device_name) : 2;
  const nameCol = hasHeader ? (cols.member_name === undefined ? -1 : cols.member_name) : -1;
  const idCol = hasHeader ? (cols.member_id === undefined ? -1 : cols.member_id) : -1;

  for (let i = hasHeader ? 1 : 0; i < lines.length; i++) {
    const cells = splitLine(lines[i]);
    if (cells.length < 2) continue;

    const time = parseTime(at(cells, timeCol));
    const kg = parseFloat(at(cells, kgCol >= 0 ? kgCol : cells.length - 1));
    if (isNaN(time) || isNaN(kg) || kg <= 0) continue;

    const deviceId = at(cells, deviceCol);
    const deviceName = at(cells, deviceNameCol);
    if (deviceId && deviceName) deviceNames[deviceId] = deviceName;
    const memberName = at(cells, hasHeader ? nameCol : cells.length > 4 ? 4 : -1);
    const memberIdCell = at(cells, hasHeader ? idCol : cells.length > 3 ? 3 : -1);
    const memberKey = memberName || memberIdCell;

    let memberId = store.DEFAULT_MEMBER_ID;
    if (memberKey) {
      if (byKey[memberKey]) {
        memberId = byKey[memberKey];
      } else if (memberKey.length > 20) {
        memberId = memberKey; // looks like an id, keep it
      } else {
        if (newMembers.indexOf(memberKey) < 0) newMembers.push(memberKey);
        memberId = 'pending:' + memberKey;
      }
    }

    records.push({ t: time, kg, m: memberId, d: deviceId || null });
  }

  return { records, newMembers, deviceNames };
}

module.exports = { HEADER, build, parse };
