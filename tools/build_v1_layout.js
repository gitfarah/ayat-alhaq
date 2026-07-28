// Converts the quran.com-images layout database into the compact asset
// the app uses to typeset the KFGQPC V1 (1405H) Mushaf.
//
// Source: https://github.com/quran/quran.com-images  sql/02-database.sql
// That dump carries, for the 604-page 15-line Madani layout:
//   glyph            glyph_id -> font_file, glyph_code, page
//   glyph_page_line  glyph_id -> page, line, position, line_type
//   glyph_ayah       glyph_id -> surah, ayah, position
// Its glyph_ayah_bbox / glyph_page_line_bbox tables are defined but
// EMPTY, so there are no pixel boxes to be had — and none are needed:
// the page is typeset with its own font and the text layout gives the
// boxes back for free.
//
//   node tools/build_v1_layout.js <path-to-02-database.sql>
//     -> assets/quran/mushaf_v1_layout.json
//
// Output shape, keyed by page number:
//   [ { "t": "s"|"b"|"a",      // sura header / basmalah / ayah text
//       "f": "p"|"b",          // page font, or the shared BSML font
//       "x": "<glyph string>", // codepoints, one char per glyph
//       "v": [[surah, ayah, startIndex, length], ...]   // ayah lines
//     }, ... ]

const fs = require('fs');
const path = require('path');

const src = process.argv[2];
if (!src) {
  console.error('usage: node tools/build_v1_layout.js <02-database.sql>');
  process.exit(1);
}
const sql = fs.readFileSync(src, 'latin1');

function eachInsert(table, tupleRe, fn) {
  const re = new RegExp('INSERT INTO `' + table + '` VALUES ([^;]*);', 'g');
  let m;
  let n = 0;
  while ((m = re.exec(sql))) {
    const tup = new RegExp(tupleRe, 'g');
    let t;
    while ((t = tup.exec(m[1]))) {
      fn(t);
      n++;
    }
  }
  return n;
}

// glyph_id -> glyph code, and which font it belongs to. Ayah text uses
// the page's own font; surah headers and the Basmalah come from the
// shared QCF_BSML font, which is why a line has to say which one it
// needs.
const code = new Map();
const fontOf = new Map();
eachInsert(
  'glyph',
  "\\((\\d+),'([^']*)',(\\d+),(\\d+),(?:(\\d+)|NULL),(?:(\\d+)|NULL),(?:'[^']*'|NULL)\\)",
  t => {
    code.set(+t[1], +t[3]);
    fontOf.set(+t[1], t[2]);
  });

// glyph_id -> "surah:ayah" (ayah-text glyphs only)
const ayahOf = new Map();
eachInsert('glyph_ayah', '\\((\\d+),(\\d+),(\\d+),(\\d+),(\\d+)\\)',
  t => ayahOf.set(+t[2], [+t[3], +t[4]]));

// page -> line -> [{position, glyphId, type}]
const pages = new Map();
eachInsert('glyph_page_line',
  "\\((\\d+),(\\d+),(\\d+),(\\d+),(\\d+),'([a-z-]*)'\\)",
  t => {
    const [gid, page, line, pos, type] = [+t[2], +t[3], +t[4], +t[5], t[6]];
    if (!pages.has(page)) pages.set(page, new Map());
    const lines = pages.get(page);
    if (!lines.has(line)) lines.set(line, []);
    lines.get(line).push({ pos, gid, type });
  });

const TYPE = { sura: 's', bismillah: 'b', ayah: 'a' };
const out = {};
let glyphs = 0;
const seenAyahs = new Set();

for (const page of [...pages.keys()].sort((a, b) => a - b)) {
  const lines = pages.get(page);
  const rendered = [];
  for (const lineNo of [...lines.keys()].sort((a, b) => a - b)) {
    const items = lines.get(lineNo).sort((a, b) => a.pos - b.pos);
    let text = '';
    const spans = [];
    for (const it of items) {
      const c = code.get(it.gid);
      if (c === undefined) throw new Error('glyph ' + it.gid + ' has no code');
      const at = text.length;
      text += String.fromCharCode(c);
      glyphs++;
      const a = ayahOf.get(it.gid);
      if (!a) continue;
      seenAyahs.add(a[0] + ':' + a[1]);
      const last = spans[spans.length - 1];
      // Runs of one ayah collapse into a single span.
      if (last && last[0] === a[0] && last[1] === a[1] &&
          last[2] + last[3] === at) {
        last[3]++;
      } else {
        spans.push([a[0], a[1], at, 1]);
      }
    }
    const type = TYPE[items[0].type] || 'a';
    const line = { t: type, x: text };
    // 'b' = the shared QCF_BSML font, 'p' = this page's own font.
    line.f = (fontOf.get(items[0].gid) || '').startsWith('QCF_BSML')
      ? 'b'
      : 'p';
    if (spans.length) line.v = spans;
    rendered.push(line);
  }
  out[page] = rendered;
}

const dest = path.join(__dirname, '..', 'assets', 'quran',
  'mushaf_v1_layout.json');
fs.writeFileSync(dest, JSON.stringify(out));

const bytes = fs.statSync(dest).size;
console.log('pages      :', Object.keys(out).length);
console.log('glyphs     :', glyphs);
console.log('ayahs seen :', seenAyahs.size, '(expect 6236)');
console.log('written    :', dest, (bytes / 1048576).toFixed(2), 'MB');
