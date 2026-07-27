// Measures where each surah's NAME is printed on the quranpedia Mushaf
// pages, per edition, so the app can paint an ornamental frame behind it.
//
// The artwork draws the name as plain glyphs with no banner, and every
// riwayah breaks its lines differently, so the position has to be
// measured from the rendered page rather than assumed.
//
// Anchoring on the ayah polygons does not work: they are bounding boxes,
// and a multi-line ayah's box swallows the lines around it. What IS
// unmistakable optically is that the surah name and the Basmala are the
// only SHORT, CENTRED lines on a page — every line of Quran text is
// justified edge to edge, and a surah's final partial line hugs the
// right margin (RTL). So: find the centred narrow lines, in order, and
// hand them out to the surahs that start on the page (name, Basmala,
// name, Basmala, ...; Al-Fatiha and At-Tawbah print no Basmala).
//
//   node measure.js <edition> [surah,surah,...]

const { chromium } = require('playwright');
const https = require('https');

const BASE = 'https://raw.githubusercontent.com/quranpedia/quran-svg/main/mushafs';
const pad = n => String(n).padStart(3, '0');
const get = u => new Promise((res, rej) => https.get(u, r => {
  let d = '';
  r.on('data', c => d += c);
  r.on('end', () => r.statusCode === 200 ? res(d) : rej(new Error('HTTP ' + r.statusCode)));
}).on('error', rej));

const SCALE = 4;

// Every band of inked rows on the page: [top, bottom, xMin, xMax] in
// viewBox units.
async function inkRuns(tab, svg) {
  return tab.evaluate(async (args) => {
    const svg = args.svg, SCALE = args.SCALE;
    const vb = svg
      .match(/viewBox="\s*(-?[\d.]+)[,\s]+(-?[\d.]+)[,\s]+(-?[\d.]+)[,\s]+(-?[\d.]+)/)
      .slice(1).map(Number);
    const minX = vb[0], minY = vb[1], w = vb[2], h = vb[3];

    const img = new Image();
    img.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svg)));
    await img.decode();
    const c = document.createElement('canvas');
    c.width = Math.round(w * SCALE);
    c.height = Math.round(h * SCALE);
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, c.width, c.height);
    ctx.drawImage(img, 0, 0, c.width, c.height);
    const d = ctx.getImageData(0, 0, c.width, c.height).data;

    const first = new Int32Array(c.height).fill(-1);
    const last = new Int32Array(c.height).fill(-1);
    for (let y = 0; y < c.height; y++) {
      const off = y * c.width * 4;
      for (let x = 0; x < c.width; x++) {
        if (d[off + x * 4] < 200) {
          if (first[y] < 0) first[y] = x;
          last[y] = x;
        }
      }
    }
    const runs = [];
    let start = -1, blank = 0;
    const close = (endY) => {
      let xa = Infinity, xb = -Infinity;
      for (let y = start; y <= endY; y++) {
        if (first[y] >= 0) { xa = Math.min(xa, first[y]); xb = Math.max(xb, last[y]); }
      }
      runs.push([
        minY + start / SCALE, minY + endY / SCALE,
        minX + xa / SCALE, minX + xb / SCALE,
      ]);
      start = -1;
    };
    for (let y = 0; y < c.height; y++) {
      if (first[y] >= 0) { if (start < 0) start = y; blank = 0; }
      else if (start >= 0 && ++blank > 2) close(y - blank);
    }
    if (start >= 0) close(c.height - 1);
    return { runs: runs.filter(r => r[1] - r[0] > 2), minX: minX, width: w };
  }, { svg: svg, SCALE: SCALE });
}

// Bands for every surah starting on , in page order.
//
// The Basmala is the anchor: it is the same rendered string on every
// page, so its ink is a near-constant 54% of the page width — nothing
// else on a page looks like that. The surah name is then simply the ink
// row directly above it. (At-Tawbah prints no Basmala, so its name is
// found as the narrow centred row instead.)
async function bandsForPage(ed, page, surahs, tab) {
  const svg = await get(BASE + '/' + ed + '/kfqc/svg/' + pad(page) + '.svg');
  const res = await inkRuns(tab, svg);
  const runs = res.runs, W = res.width, mid = res.minX + W / 2;
  const frac = r => (r[3] - r[2]) / W;
  const centred = r => Math.abs((r[2] + r[3]) / 2 - mid) < W * 0.025;

  // The name rows: well under half the width and dead-centred.
  // Body lines run 93-96%, the Basmala 54%, and a surah's short closing
  // line hugs the right margin (RTL) so it is never centred.
  let names = runs.filter(r => frac(r) < 0.40 && centred(r));

  const wanted = surahs.filter(s => s > 2).length;
  // A short surah's closing line can also come out narrow and centred.
  // When that happens, keep only the candidates actually followed by a
  // Basmala row — a real surah opening always is.
  if (names.length > wanted) {
    const followed = names.filter(r => {
      const next = runs[runs.indexOf(r) + 1];
      return next && frac(next) > 0.45 && frac(next) < 0.75;
    });
    if (followed.length === wanted) names = followed;
  }
  if (names.length !== wanted) {
    return { error: 'found ' + names.length + ' name rows, expected ' + wanted };
  }
  const out = [];
  let i = 0;
  for (const s of surahs) {
    if (s <= 2) continue;                // pages 1-2 use the illuminated frame
    const r = names[i++];
    out.push({ s: s, p: page, t: +r[0].toFixed(2), b: +r[1].toFixed(2) });
  }
  return { bands: out };
}

(async () => {
  const ed = process.argv[2] || 'hafs';
  const only = process.argv[3] ? process.argv[3].split(',').map(Number) : null;
  const surahStartPages = require('./starts.js').surahStartPages;

  const byPage = new Map();
  for (let s = 1; s <= 114; s++) {
    if (only && only.indexOf(s) < 0) continue;
    const p = surahStartPages[s - 1];
    if (!byPage.has(p)) byPage.set(p, []);
    byPage.get(p).push(s);
  }

  const browser = await chromium.launch({ channel: 'chrome' });
  const tab = await browser.newPage();
  const out = [];
  for (const [p, surahs] of [...byPage.entries()].sort((a, b) => a[0] - b[0])) {
    try {
      const r = await bandsForPage(ed, p, surahs, tab);
      if (r.bands) out.push(...r.bands);
      else console.error('  p' + p + ' s[' + surahs + ']: ' + r.error);
    } catch (e) {
      console.error('  p' + p + ' s[' + surahs + ']: ' + e.message);
    }
  }
  await browser.close();
  console.log(JSON.stringify(out));
})();
