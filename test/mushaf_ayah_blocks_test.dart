import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/mushaf_v2_service.dart';

/// Re-cutting a printed page at ayah boundaries — what lets the
/// ayah-by-ayah reader give each verse its own block, and put a
/// translation under it, while still setting the page's own glyphs.
///
/// Built from hand-made lines rather than a real page so the cases that
/// actually break this (an ayah split across lines, two ayahs sharing
/// one line) can be stated outright instead of hunted for in the
/// layout.
MushafV2Page _page(List<MushafV2Line> lines) => MushafV2Page(
      pageNumber: 1,
      lines: lines,
      fontFamily: 'F',
      surahFontFamily: 'S',
      bismillahFontFamily: 'B',
      usesColorFont: false,
    );

MushafV2Line _ayahLine(int n, List<(String, int, int)> words) => MushafV2Line(
      number: n,
      type: MushafV2LineType.ayah,
      words: [for (final w in words) MushafV2Word(w.$1, w.$2, w.$3)],
    );

void main() {
  test('an ayah the print splits across lines comes back as one block', () {
    final blocks = _page([
      _ayahLine(1, [('a', 2, 1), ('b', 2, 1)]),
      _ayahLine(2, [('c', 2, 1), ('d', 2, 1)]),
    ]).blocks;

    expect(blocks.length, 1);
    expect(blocks.single.kind, MushafBlockKind.ayah);
    expect(blocks.single.ayah, 1);
    // In reading order, and with no line break smuggled in — the whole
    // point is that the reader sees a verse, not two half-verses.
    expect(blocks.single.glyphs, 'abcd');
  });

  test('two ayahs sharing one printed line are cut apart', () {
    final blocks = _page([
      _ayahLine(1, [('a', 2, 1), ('b', 2, 2)]),
    ]).blocks;

    expect(blocks.map((b) => (b.ayah, b.glyphs)).toList(),
        [(1, 'a'), (2, 'b')]);
  });

  test('a surah header and its basmala keep their place between verses', () {
    final blocks = _page([
      _ayahLine(1, [('z', 1, 7)]),
      const MushafV2Line(
          number: 2, type: MushafV2LineType.surah, surah: 2, centered: true),
      const MushafV2Line(
          number: 3, type: MushafV2LineType.basmala, centered: true),
      _ayahLine(4, [('a', 2, 1)]),
    ]).blocks;

    expect(blocks.map((b) => b.kind).toList(), [
      MushafBlockKind.ayah,
      MushafBlockKind.surahHeader,
      MushafBlockKind.basmala,
      MushafBlockKind.ayah,
    ]);
    expect(blocks[1].surah, 2);
    // The verse before the header must not have swallowed the verse
    // after it just because no other ayah intervened.
    expect(blocks.first.glyphs, 'z');
    expect(blocks.last.glyphs, 'a');
  });

  test('the same ayah number in a different surah is a different block', () {
    final blocks = _page([
      _ayahLine(1, [('a', 2, 1), ('b', 3, 1)]),
    ]).blocks;

    expect(blocks.length, 2);
    expect(blocks.map((b) => b.surah).toList(), [2, 3]);
  });

  test('a page carrying nothing but a header yields no empty ayah block', () {
    final blocks = _page([
      const MushafV2Line(
          number: 1, type: MushafV2LineType.surah, surah: 114, centered: true),
    ]).blocks;

    expect(blocks.length, 1);
    expect(blocks.single.kind, MushafBlockKind.surahHeader);
  });

  test('every real page of the V4 layout re-cuts without losing a word',
      () async {
    // The invariant that matters: regrouping only moves the cuts, it
    // never drops, duplicates or reorders a glyph. Checked against the
    // bundled layout itself so a future layout revision cannot quietly
    // break it.
    TestWidgetsFlutterBinding.ensureInitialized();
    final raw = await rootBundle
        .loadString('assets/quran/mushaf_v4_1441h_layout.json');
    final pages = (jsonDecode(raw) as Map<String, dynamic>)['pages'] as List;

    for (final p in pages) {
      final lines = [
        for (final line in (p as Map<String, dynamic>)['l'] as List)
          MushafV2Line.fromJson(line as Map<String, dynamic>),
      ];
      final printed = lines.expand((l) => l.words).map((w) => w.glyph).join();
      final regrouped = _page(lines)
          .blocks
          .where((b) => b.kind == MushafBlockKind.ayah)
          .map((b) => b.glyphs)
          .join();
      expect(regrouped, printed, reason: 'page ${p['p']} lost or moved glyphs');
    }
  });

  _paletteTests();

  group('tajweed switch', () {
    test('picks between two real V4 cuts, not a colouring pass', () {
      expect(MushafV2Service.editionFor('hafs', tajweed: true), 'hafs');
      expect(MushafV2Service.editionFor('hafs', tajweed: false), 'hafs_plain');
      // Turning it back on from the plain cut has to return to 'hafs',
      // or the switch would be one-way.
      expect(MushafV2Service.editionFor('hafs_plain', tajweed: true), 'hafs');
    });

    test('leaves V1 and V2 alone — neither ships a tajweed cut', () {
      for (final id in ['madinah1421', 'madinah1405']) {
        expect(MushafV2Service.editionFor(id, tajweed: true), id);
        expect(MushafV2Service.editionFor(id, tajweed: false), id);
        expect(MushafV2Service.hasTajweedCut(id), isFalse);
      }
      expect(MushafV2Service.hasTajweedCut('hafs'), isTrue);
    });
  });
}

/// A minimal sfnt carrying one CPAL table, so the palette swap can be
/// tested without pulling a 280 KB font over the network.
///
/// [palettes] is a list of palettes, each a list of RGBA colour records.
Uint8List _fontWithCpal(List<List<int>> palettes) {
  final entries = palettes.first.length;
  final records = <int>[];
  for (final p in palettes) {
    for (final c in p) {
      // CPAL stores BGRA.
      records.addAll([c & 0xff, (c >> 8) & 0xff, (c >> 16) & 0xff, 0xff]);
    }
  }
  final headerLen = 12 + palettes.length * 2;
  final cpal = BytesBuilder();
  final head = ByteData(headerLen);
  head.setUint16(0, 0); // version
  head.setUint16(2, entries);
  head.setUint16(4, palettes.length);
  head.setUint16(6, records.length ~/ 4);
  head.setUint32(8, headerLen); // offset to first colour record
  for (var i = 0; i < palettes.length; i++) {
    head.setUint16(12 + i * 2, i * entries);
  }
  cpal.add(head.buffer.asUint8List());
  cpal.add(records);
  final cpalBytes = cpal.toBytes();

  // sfnt: header + one table record + the table itself.
  const tableOffset = 12 + 16;
  final out = BytesBuilder();
  final sfnt = ByteData(tableOffset);
  sfnt.setUint32(0, 0x00010000);
  sfnt.setUint16(4, 1); // numTables
  sfnt.setUint8(12, 0x43); // 'C'
  sfnt.setUint8(13, 0x50); // 'P'
  sfnt.setUint8(14, 0x41); // 'A'
  sfnt.setUint8(15, 0x4C); // 'L'
  sfnt.setUint32(20, tableOffset);
  sfnt.setUint32(24, cpalBytes.length);
  out.add(sfnt.buffer.asUint8List());
  out.add(cpalBytes);
  return out.toBytes();
}

/// Reads entry [entry] of the palette [font]'s default-palette pointer
/// currently resolves to.
int _defaultPaletteEntry(Uint8List font, int entry) {
  final d = ByteData.sublistView(font);
  final cpal = d.getUint32(12 + 8);
  final first = d.getUint32(cpal + 8);
  final idx = d.getUint16(cpal + 12);
  final o = cpal + first + (idx + entry) * 4;
  return (font[o + 2] << 16) | (font[o + 1] << 8) | font[o];
}

const _softWhite = 0xF2F0ED; // AppColors.darkText

void _paletteTests() {
  group('dark palette', () {
    test('repoints the default palette at the dark one', () {
      // Palette 0 draws the base letter black, palette 1 draws it white —
      // the arrangement KFGQPC actually ships. Only 2 entries, so
      // neither font here carries the medallion-frame entries (13/14)
      // that a real one does.
      final font = _fontWithCpal([
        [0x000000, 0xb50000],
        [0xffffff, 0xe30000],
      ]);
      expect(_defaultPaletteEntry(font, 0), 0x000000);

      final dark = MushafV2Service.repaletteForDarkForTesting(font)!;
      // Retuned to the app's soft dark-mode ink, not left at the pure
      // white KFGQPC ships — that pure white is the bug being fixed.
      expect(_defaultPaletteEntry(dark, 0), _softWhite,
          reason: 'the plain-ink entry must be softened, not left white');
      // A rule colour (entry 1) is untouched — this is the one
      // colour distinguishing the two palettes besides the base ink.
      expect(_defaultPaletteEntry(dark, 1), 0xe30000,
          reason: 'a tajweed-rule colour must not be retuned');
      expect(dark.length, font.length,
          reason: 'nothing may be inserted, only repointed/recoloured');
      // The original must be left intact — it is what stays cached.
      expect(_defaultPaletteEntry(font, 0), 0x000000);
    });

    test(
        'entries 0, 13 and 14 are softened; every tajweed-rule colour '
        'in between is left exactly as KFGQPC ships it', () {
      // A 16-entry stand-in for the real font's palette shape: 0 is the
      // plain letter, 1..12 are distinct rule colours, 13/14 are the
      // medallion-frame's plain sides, 15 is a secondary muted tone.
      final light = [
        for (var i = 0; i < 16; i++) 0x100000 + i, // all distinct, checkable
      ]..[0] = 0x000000;
      final dark = [
        for (var i = 0; i < 16; i++) 0x200000 + i,
      ]..[0] = 0xffffff
        ..[13] = 0xffffff
        ..[14] = 0xfbffff;
      final font = _fontWithCpal([light, dark]);

      final patched = MushafV2Service.repaletteForDarkForTesting(font)!;
      expect(_defaultPaletteEntry(patched, 0), _softWhite);
      expect(_defaultPaletteEntry(patched, 13), _softWhite);
      expect(_defaultPaletteEntry(patched, 14), _softWhite);
      // Every rule colour (1..12) and the secondary tone (15) survive
      // untouched — a reader's ability to tell one tajweed rule from
      // another must not move.
      for (final entry in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15]) {
        expect(_defaultPaletteEntry(patched, entry), dark[entry],
            reason: 'entry $entry must be left exactly as shipped');
      }
    });

    test('a font with a single palette is left exactly as it is', () {
      final font = _fontWithCpal([
        [0x000000, 0xb50000],
      ]);
      expect(MushafV2Service.repaletteForDarkForTesting(font), isNull);
    });

    test('a font with no CPAL at all is left alone', () {
      // The plain V4 cut has no colour tables; asking for a dark palette
      // must not mangle it, because its colour comes from TextStyle.
      final plain = Uint8List.fromList([
        0, 1, 0, 0, // sfnt version
        0, 0, // numTables = 0
        0, 0, 0, 0, 0, 0,
      ]);
      expect(MushafV2Service.repaletteForDarkForTesting(plain), isNull);
    });

    test('garbage is refused rather than thrown out of', () {
      expect(
          MushafV2Service.repaletteForDarkForTesting(
              Uint8List.fromList(List.filled(40, 0xAB))),
          isNull);
    });
  });
}
