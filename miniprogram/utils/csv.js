// CSV import / export. Keeps exactly the same columns as the Flutter app
// (lib/service/csv.dart):
//
//   timestamp,device_id,device_name,member_id,member_name,weight_kg
//
// Timestamps are ISO-8601 local time. Extra columns are ignored on import and
// rows without a valid timestamp / weight are skipped.

const store = require('./store');

const HEADER = 'timestamp,device_id,device_name,member_id,member_name,weight_kg';

function pad(value, width) {
  let text = String(value);
  while (text.length < (width || 2)) text = '0' + text;
  return text;
}

function isoLocal(ms) {
  const d = new Date(ms);
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.${pad(d.getMilliseconds(), 3)}`
  );
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

function build(records) {
  const lines = [HEADER];
  records.forEach((r) => {
    lines.push(
      [
        isoLocal(r.t),
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

// Returns { records, newMembers }; newMembers holds names that do not exist yet
// and are referenced as `pending:<name>` in the rows.
function parse(text) {
  const byKey = {};
  store.getMembers().forEach((m) => {
    byKey[m.id] = m.id;
    byKey[m.name] = m.id;
  });

  const records = [];
  const newMembers = [];
  const lines = String(text || '')
    .split(/\r?\n/)
    .filter((line) => line.trim().length);
  if (!lines.length) return { records, newMembers };

  let start = 0;
  const first = splitLine(lines[0]);
  if (first.length && first[0].replace(/^\ufeff/, '').toLowerCase().indexOf('time') >= 0) {
    start = 1;
  }

  for (let i = start; i < lines.length; i++) {
    const cells = splitLine(lines[i]);
    if (cells.length < 2) continue;

    const time = Date.parse(cells[0].trim());
    const kg = parseFloat(cells[cells.length - 1].trim());
    if (isNaN(time) || isNaN(kg) || kg <= 0) continue;

    const deviceId = cells.length > 1 ? cells[1].trim() : '';
    const memberKey = cells.length > 4 ? cells[4].trim() : cells.length > 3 ? cells[3].trim() : '';

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

  return { records, newMembers };
}

module.exports = { HEADER, build, parse, isoLocal };
