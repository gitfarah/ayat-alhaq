// The bundled Quran typeface is load-bearing for the TEXT, not just its
// looks: the previously shipped KFGQPC HAFS v0.18 could not shape a
// word-internal hamza, and every attempt to work around that in the text
// produced a misreading (ٱلْءَاخِرَةِ rendering as ٱلْكَاخِرَة).
//
// The app now ships v2.2, the King Fahd Complex's released version, and
// the text is left exactly as the source spells it. These assert the
// font asset is actually the one that behaviour depends on — a silent
// swap back would reintroduce a wrong word in the Quran with nothing
// else failing.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Big-endian reads over the sfnt container.
int _be16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

/// Every `name` table record, keyed by nameID.
Map<int, Set<String>> _names(Uint8List b) {
  final numTables = _be16(b, 4);
  var nameOff = -1;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(b.sublist(rec, rec + 4));
    if (tag == 'name') nameOff = _be32(b, rec + 8);
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
            for (var k = 0; k + 1 < raw.length; k += 2) (raw[k] << 8) | raw[k + 1]
          ])
        : ascii.decode(raw, allowInvalid: true);
    (out[nameId] ??= <String>{}).add(value);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled Quran face is KFGQPC HAFS v2.2, not the v0.18 beta',
      () async {
    final data = await rootBundle.load('assets/fonts/UthmanicHafs_V22.ttf');
    final bytes = data.buffer.asUint8List();
    final names = _names(bytes);

    expect(names[1], contains('KFGQPC HAFS Uthmanic Script'),
        reason: 'family must still be the KFGQPC Uthmanic Hafs face');

    final version = names[5]!.first;
    expect(version, contains('2.2'),
        reason: 'shipped version must be 2.2 — v0.18 cannot shape a '
            'word-internal hamza and silently misrenders ٱلْءَاخِرَةِ');
    expect(version, isNot(contains('0.18')));
  });

  test('the v0.18 beta is gone from the bundle', () async {
    // Leaving it bundled would let the old rendering come back without
    // any test noticing.
    var stillBundled = true;
    try {
      await rootBundle.load('assets/fonts/HafsQuran.ttf');
    } catch (_) {
      stillBundled = false;
    }
    expect(stillBundled, isFalse,
        reason: 'the superseded v0.18 font must not still be bundled');
  });
}
