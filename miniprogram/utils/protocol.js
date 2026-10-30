const KG_PER_LB = 0.45359237;
const KG_PER_STONE = 6.35029318;
const LB_PER_KG = 2.20462262185;

const UNITS = ['jin', 'kg', 'lb', 'st'];

function toDisplay(kg, unit) {
  switch (unit) {
    case 'lb': return kg * LB_PER_KG;
    case 'jin': return kg * 2;
    case 'st': return kg / KG_PER_STONE;
    default: return kg;
  }
}

function fromDisplay(value, unit) {
  switch (unit) {
    case 'lb': return value * KG_PER_LB;
    case 'jin': return value / 2;
    case 'st': return value * KG_PER_STONE;
    default: return value;
  }
}

function label(unit, lang) {
  if (unit === 'jin') return lang === 'zh' ? '斤' : 'jin';
  return unit;
}

function format(kg, unit, lang) {
  const v = toDisplay(kg, unit);
  return `${v.toFixed(unit === 'st' ? 2 : 1)} ${label(unit, lang)}`;
}

// unitBits: 0 kg, 1 jin, 2 lb, 3 st:lb  -> value is in that unit
function toKg(value, unitBits) {
  switch (unitBits) {
    case 1: return value * 0.5;
    case 2: return value * KG_PER_LB;
    default: return value;
  }
}

const KNOWN_PROPS = [0x24, 0x25, 0x30, 0x31, 0x38, 0x39];

// Chipsea advertisement payload:
//   [0..1] weight (big endian), [2..5] resistance, [6] unit + lock
function parseChipsea(p) {
  if (p.length < 7) return null;
  const props = p[6];
  if (KNOWN_PROPS.indexOf(props) < 0) return null;
  const raw = (p[0] << 8) | p[1];
  if (raw <= 0 || raw > 30000) return null;
  const unitBits = (props >> 3) & 0x03;
  const locked = (props & 0x01) === 0x01;
  if (unitBits === 3) {
    const stones = raw >> 8;
    const pounds = (raw & 0xff) / 10;
    return { kg: stones * KG_PER_STONE + pounds * KG_PER_LB, locked };
  }
  const value = unitBits === 2 ? raw / 10 : raw / 100;
  return { kg: toKg(value, unitBits), locked };
}

// OKOK 1.1 frame: CA 11 <len> <lock> <type> <wMSB> <wLSB> ... <props@11>
function parseOkokFrame(p) {
  if (p.length < 12 || p[0] !== 0xca) return null;
  const len = p[2];
  if (p.length < 3 + len + 1) return null;
  const raw = (p[5] << 8) | p[6];
  const props = p[11];
  const unitBits = (props >> 3) & 0x03;
  const decBits = (props >> 1) & 0x03;
  const decimals = decBits === 1 ? 0 : (decBits === 2 ? 2 : 1);
  if (raw <= 0 || raw > 30000) return null;
  return { kg: toKg(raw / Math.pow(10, decimals), unitBits), locked: p[3] === 0x01 };
}

// WeChat hands us the advertisement bytes; depending on the device the payload
// may or may not include the 2-byte company id, so both offsets are tried.
function parseAdvertisement(buffer) {
  if (!buffer) return null;
  const bytes = new Uint8Array(buffer);
  if (!bytes.length) return null;

  for (let i = 0; i + 12 <= bytes.length; i++) {
    const frame = parseOkokFrame(bytes.subarray(i));
    if (frame) return frame;
  }
  const offsets = [0, 2];
  for (let o = 0; o < offsets.length; o++) {
    const p = bytes.subarray(offsets[o]);
    const r = parseChipsea(p);
    if (r) return r;
  }
  return null;
}

module.exports = {
  UNITS,
  KG_PER_LB,
  KG_PER_STONE,
  LB_PER_KG,
  toDisplay,
  fromDisplay,
  label,
  format,
  parseAdvertisement,
};
