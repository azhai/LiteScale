// Storage layer for the mini program: members, devices, records, settings.
// Mirrors lib/service/app_controller.dart so both apps read the same CSV.

const KEY_RECORDS = 'records';
const KEY_SETTINGS = 'settings';
const KEY_MEMBERS = 'members';
const KEY_DEVICES = 'devices';

const DEFAULT_MEMBER_ID = 'me';
// Avatars are local-only decoration, never exported.
const AVATARS = ['🙂', '😎', '🧑', '👩', '👨', '🐱'];

function read(key, fallback) {
  const value = wx.getStorageSync(key);
  if (value === '' || value === undefined || value === null) return fallback;
  return value;
}

// --- members ---------------------------------------------------------------

function getMembers() {
  const list = read(KEY_MEMBERS, []);
  return Array.isArray(list) ? list : [];
}

function saveMembers(list) {
  wx.setStorageSync(KEY_MEMBERS, list);
}

function ensureMembers(lang) {
  let list = getMembers();
  if (!list.length) {
    list = [
      {
        id: DEFAULT_MEMBER_ID,
        name: lang === 'en' ? 'Me' : '我',
        avatar: AVATARS[0],
        color: 0,
      },
    ];
    saveMembers(list);
  }
  return list;
}

function memberById(id) {
  const list = getMembers();
  for (const m of list) {
    if (m.id === id) return m;
  }
  return list.length ? list[0] : { id: DEFAULT_MEMBER_ID, name: 'Me', avatar: AVATARS[0], color: 0 };
}

function memberName(id) {
  return memberById(id).name;
}

function addMember(name) {
  const list = getMembers();
  const clean = String(name || '').trim() || String(list.length + 1);
  const member = {
    id: 'm' + Date.now(),
    name: clean,
    avatar: AVATARS[list.length % AVATARS.length],
    color: list.length % 6,
  };
  list.push(member);
  saveMembers(list);
  return member;
}

function renameMember(id, name) {
  const clean = String(name || '').trim();
  if (!clean) return;
  saveMembers(getMembers().map((m) => (m.id === id ? Object.assign({}, m, { name: clean }) : m)));
}

function setMemberAvatar(id, avatar) {
  saveMembers(getMembers().map((m) => (m.id === id ? Object.assign({}, m, { avatar }) : m)));
}

// Records of a removed member move to the first remaining member.
function removeMember(id) {
  const list = getMembers();
  if (list.length <= 1) return false;
  const remaining = list.filter((m) => m.id !== id);
  const fallback = remaining[0].id;
  saveRecords(
    getRecords().map((r) => ((r.m || DEFAULT_MEMBER_ID) === id ? Object.assign({}, r, { m: fallback }) : r))
  );
  saveMembers(remaining);
  if (getActiveMemberId() === id) setActiveMemberId(fallback);
  return true;
}

// --- devices ---------------------------------------------------------------

function getDevices() {
  const list = read(KEY_DEVICES, []);
  return Array.isArray(list) ? list : [];
}

function saveDevices(list) {
  wx.setStorageSync(KEY_DEVICES, list);
}

function rememberDevice(id, name) {
  if (!id) return;
  const list = getDevices();
  const now = Date.now();
  const index = list.findIndex((d) => d.id === id);
  if (index >= 0) {
    const existing = list[index];
    // Do not rewrite storage on every advertisement.
    if ((existing.name || '') === (name || '') && now - (existing.seen || 0) < 30000) return;
    list[index] = { id, name: name || existing.name || '', seen: now };
  } else {
    list.push({ id, name: name || '', seen: now });
  }
  saveDevices(list);
}

function renameDevice(id, name) {
  saveDevices(getDevices().map((d) => (d.id === id ? Object.assign({}, d, { name: String(name || '').trim() }) : d)));
}

function removeDevice(id) {
  saveDevices(getDevices().filter((d) => d.id !== id));
}

function deviceName(id) {
  if (!id) return '';
  const found = getDevices().filter((d) => d.id === id)[0];
  if (!found) return id;
  return found.name || found.id;
}

// --- records ---------------------------------------------------------------

function getRecords() {
  const list = read(KEY_RECORDS, []);
  if (!Array.isArray(list)) return [];
  return list.slice().sort((a, b) => a.t - b.t);
}

function saveRecords(list) {
  wx.setStorageSync(KEY_RECORDS, list.slice().sort((a, b) => a.t - b.t));
}

// Drops readings that repeat the same weight within 60s (the scale keeps
// broadcasting while you stand on it).
function addRecord(kg, memberId, deviceId) {
  const list = getRecords();
  const now = Date.now();
  const mine = list.filter((r) => (r.m || DEFAULT_MEMBER_ID) === memberId);
  const last = mine[mine.length - 1];
  if (last && Math.abs(last.kg - kg) < 0.05 && now - last.t < 60000) return false;
  list.push({
    t: now,
    kg: Math.round(kg * 1000) / 1000,
    m: memberId || DEFAULT_MEMBER_ID,
    d: deviceId || null,
  });
  saveRecords(list);
  return true;
}

function setRecordMember(t, memberId) {
  saveRecords(getRecords().map((r) => (r.t === t ? Object.assign({}, r, { m: memberId }) : r)));
}

function removeRecord(t) {
  saveRecords(getRecords().filter((r) => r.t !== t));
}

function clearRecords() {
  saveRecords([]);
}

function findRecord(t) {
  return getRecords().filter((r) => r.t === t)[0] || null;
}

// Merges imported rows; members named `pending:<name>` are created first and
// duplicates (same timestamp + weight) are skipped. Returns rows added.
function importRecords(rows) {
  const pending = {};
  const byName = {};
  getMembers().forEach((m) => {
    byName[m.name] = m.id;
  });
  rows.forEach((r) => {
    const key = String(r.m || '');
    if (key.indexOf('pending:') !== 0) return;
    const name = key.slice('pending:'.length);
    if (pending[name]) return;
    pending[name] = byName[name] || addMember(name).id;
  });

  const all = getRecords();
  const seen = {};
  all.forEach((r) => {
    seen[`${r.t}|${r.kg}`] = true;
  });

  let added = 0;
  rows.forEach((r) => {
    const raw = String(r.m || '');
    let memberId = raw;
    if (raw.indexOf('pending:') === 0) {
      memberId = pending[raw.slice('pending:'.length)] || (getMembers()[0] || {}).id || DEFAULT_MEMBER_ID;
    }
    const record = { t: r.t, kg: r.kg, m: memberId, d: r.d || null };
    const key = `${record.t}|${record.kg}`;
    if (seen[key]) return;
    seen[key] = true;
    all.push(record);
    added++;
  });

  if (added) saveRecords(all);
  return added;
}

// --- settings --------------------------------------------------------------

function getSettings() {
  const value = read(KEY_SETTINGS, {});
  return value && typeof value === 'object' ? value : {};
}

function saveSettings(patch) {
  const next = Object.assign({}, getSettings(), patch);
  wx.setStorageSync(KEY_SETTINGS, next);
  return next;
}

function getActiveMemberId() {
  const id = getSettings().activeMemberId;
  const list = getMembers();
  if (id && list.some((m) => m.id === id)) return id;
  return list.length ? list[0].id : DEFAULT_MEMBER_ID;
}

function setActiveMemberId(id) {
  saveSettings({ activeMemberId: id });
}

// --- queries ---------------------------------------------------------------

// memberId / deviceId of null or '' means "no filter"; days 0 means everything.
function filterRecords(list, memberId, deviceId, days) {
  const from = days ? Date.now() - days * 86400000 : 0;
  return list.filter((r) => {
    if (memberId && (r.m || DEFAULT_MEMBER_ID) !== memberId) return false;
    if (deviceId && (r.d || '') !== deviceId) return false;
    if (from && r.t < from) return false;
    return true;
  });
}

function changeOver(list, days) {
  if (!list.length) return null;
  const latest = list[list.length - 1].kg;
  const target = list[list.length - 1].t - days * 86400000;
  let best = null;
  for (const r of list) {
    if (r.t > target) break;
    best = r;
  }
  return best ? latest - best.kg : null;
}

function bmi(kg, heightCm) {
  if (!heightCm || heightCm <= 0) return null;
  const m = heightCm / 100;
  return kg / (m * m);
}

// Upgrades data written by the single-member version of the app.
function migrate() {
  const raw = read(KEY_RECORDS, []);
  if (Array.isArray(raw)) {
    let changed = false;
    const list = raw.map((r) => {
      if (r && r.m) return r;
      changed = true;
      return { t: r.t, kg: r.kg, m: DEFAULT_MEMBER_ID, d: null };
    });
    if (changed) saveRecords(list);
  }
  ensureMembers(getSettings().lang || 'zh');
}

module.exports = {
  DEFAULT_MEMBER_ID,
  AVATARS,
  migrate,
  getMembers,
  saveMembers,
  ensureMembers,
  memberById,
  memberName,
  addMember,
  renameMember,
  setMemberAvatar,
  removeMember,
  getDevices,
  rememberDevice,
  renameDevice,
  removeDevice,
  deviceName,
  getRecords,
  saveRecords,
  addRecord,
  setRecordMember,
  removeRecord,
  clearRecords,
  findRecord,
  importRecords,
  getSettings,
  saveSettings,
  getActiveMemberId,
  setActiveMemberId,
  filterRecords,
  changeOver,
  bmi,
};
