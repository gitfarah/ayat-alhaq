// The bundled Quran typeface is load-bearing for the TEXT, not just for
// looks, and the reason is easy to lose.
//
// ٱلْءَاخِرَةِ (2:4) has a word-internal standalone hamza. Most Uthmani
// faces cannot join it and split the word in two around the hamza. Of
// eight rendered and compared, only TWO joined it as the KFGQPC Mushaf
// page itself prints it (ٱلْأَخِرَة): Amiri Quran — the face now bundled
// — and "me_quran", which it replaced. Both KFGQPC HAFS Uthmanic Script
// v0.18 AND its v2.2 release split it — which is why "just upgrade the
// KFGQPC font" is not a fix, and was tried and shipped once before
// being caught.
//
// So this asserts the bundled face is one of the two known-good ones.
// Swapping in anything else needs the word RENDERED and looked at;
// font-table inspection gave the wrong answer here twice.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

int _be16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

/// Every `name` table record, keyed by nameID.
Map<int, Set<String>> _names(Uint8List b) {
  final numTables = _be16(b, 4);
  var nameOff = -1;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    if (String.fromCharCodes(b.sublist(rec, rec + 4)) == 'name') {
      nameOff = _be32(b, rec + 8);
    }
  }
  expect(nameOff, greaterThan(0), reason: 'font has no name table');

  final count = _be16(b, nameOff + 2);
  final storage = nameOff + _be16(b, nameOff + 4);
  final out = <int, Set<String>>{};
  for (var i = 0; i < count; i++) {
    final r = nameOff + 6 + i * 12;
    final platform = _be16(b, r);
    final nameId = _be16(b, r + 6);
    final len = _be16(b, r + 8);
    final off = _be16(b, r + 10);
    final raw = b.sublist(storage + off, storage + off + len);
    // Platform 3 (Windows) stores UTF-16BE; platform 1 (Mac) is ASCII.
    final value = platform == 3
        ? String.fromCharCodes([
            for (var k = 0; k + 1 < raw.length; k += 2)
              (raw[k] << 8) | raw[k + 1]
          ])
        : ascii.decode(raw, allowInvalid: true);
    (out[nameId] ??= <String>{}).add(value);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled Quran face is one that JOINS a word-internal hamza',
      () async {
    final data = await rootBundle.load('assets/fonts/AmiriQuran.ttf');
    final names = _names(data.buffer.asUint8List());

    // Family name as the font itself declares it.
    expect(names[1], contains('Amiri Quran'),
        reason: 'the reader must use a face verified to join ٱلْأَخِرَة — '
            'Amiri Quran or me_quran. If this is being changed, RENDER '
            'ٱلْءَاخِرَةِ in the new face and look at it first.');
  });

  group('faces already proven to SPLIT the word are not the BODY font', () {
    // Both KFGQPC HAFS versions were the body font at some point and
    // both are wrong for that job. Named individually so a swap back is
    // caught by name, not just by absence.
    for (final asset in const [
      'assets/fonts/HafsQuran.ttf', // KFGQPC HAFS v0.18
      'assets/fonts/UthmanicHafs_V22.ttf', // KFGQPC HAFS v2.2
    ]) {
      test('$asset is gone', () async {
        var present = true;
        try {
          await rootBundle.load(asset);
        } catch (_) {
          present = false;
        }
        expect(present, isFalse,
            reason: '$asset splits ٱلْءَاخِرَةِ and must not be the body '
                'font. A KFGQPC face is still bundled for ayah medallions '
                'as AyahMarkHafs.ttf — that is a different job.');
      });
    }
  });

  test('a KFGQPC face IS bundled for the ayah medallions', () async {
    // The reflowing page prints ayah numbers as bare digits and relies
    // on the font to enclose them in the ornate circle. me_quran does
    // not — it draws them plain with square marks above and below, which
    // is what "the number and its frame are squashed between the words"
    // looked like. This face does the enclosing.
    final data = await rootBundle.load('assets/fonts/AyahMarkHafs.ttf');
    final names = _names(data.buffer.asUint8List());
    expect(names[1], contains('KFGQPC HAFS Uthmanic Script'),
        reason: 'the medallion convention is a KFGQPC one — a face that '
            'does not follow it will draw bare digits again');
  });
}
