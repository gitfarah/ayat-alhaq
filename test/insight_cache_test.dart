// The read-through cache behind the ayah study layers.
//
// These works have no bulk endpoint, so the cache fills as the reader
// reads. That makes its merge behaviour load-bearing: losing an entry
// means an ayah silently stops working offline.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app_v1/services/ayah_insight_service.dart';
import 'package:quran_app_v1/services/storage/insight_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('insight_cache_test');
    // path_provider has no implementation under flutter_test; point its
    // channels at a real temp directory so the cache round-trips to
    // actual files rather than silently staying in memory.
    for (final name in const [
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/path_provider_android',
      'plugins.flutter.io/path_provider_windows',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              MethodChannel(name), (call) async => tmp.path);
    }
    await AyahInsightService.clearCache();
  });

  tearDown(() async {
    await AyahInsightService.clearCache();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('presence semantics', () {
    test('an ayah never fetched reports not-found', () async {
      final (found, value) = await InsightCache.read('eerab-word', 2, 255);
      expect(found, isFalse);
      expect(value, isNull);
    });

    test('a stored null is found — "the book has no entry" is an answer',
        () async {
      // Without this the tab would re-request a known gap on every open,
      // and would claim a network error when offline.
      await InsightCache.write('eerab-aya', 2, 255, null);
      final (found, value) = await InsightCache.read('eerab-aya', 2, 255);
      expect(found, isTrue);
      expect(value, isNull);
    });

    test('a stored empty list is found, not mistaken for absent', () async {
      await InsightCache.write('word-qeraat', 2, 255, const []);
      final (found, value) = await InsightCache.read('word-qeraat', 2, 255);
      expect(found, isTrue);
      expect(value, isEmpty);
    });

    test('payloads round-trip unchanged', () async {
      final payload = [
        {'word_number': 1, 'word': 'اللَّهُ', 'content': 'مبتدأ مرفوع'},
      ];
      await InsightCache.write('eerab-word', 2, 255, payload);
      final (found, value) = await InsightCache.read('eerab-word', 2, 255);
      expect(found, isTrue);
      expect((value as List).single['content'], 'مبتدأ مرفوع');
    });
  });

  group('isolation', () {
    test('books do not read each other\'s entries', () async {
      await InsightCache.write('eerab-word', 2, 255, const ['e']);
      expect((await InsightCache.read('word-tasreef', 2, 255)).$1, isFalse);
      expect((await InsightCache.read('eerab-word', 2, 254)).$1, isFalse);
      expect((await InsightCache.read('eerab-word', 3, 255)).$1, isFalse);
    });
  });

  group('concurrent writes', () {
    test('two ayahs of one surah saved at once both survive', () async {
      // The screen fetches four books for an ayah at once, and the
      // reader moves between ayahs freely. If two saves to the same
      // surah file each started from their own copy of the document,
      // whichever finished last would erase the other.
      await Future.wait([
        for (var ayah = 1; ayah <= 20; ayah++)
          InsightCache.write('eerab-word', 2, ayah, ['w$ayah']),
      ]);

      for (var ayah = 1; ayah <= 20; ayah++) {
        final (found, value) = await InsightCache.read('eerab-word', 2, ayah);
        expect(found, isTrue, reason: 'ayah $ayah was lost');
        expect((value as List).single, 'w$ayah');
      }
    });

    test('the file on disk holds every entry, not just the last',
        () async {
      await Future.wait([
        for (var ayah = 1; ayah <= 10; ayah++)
          InsightCache.write('word-tasreef', 5, ayah, ['w$ayah']),
      ]);

      final raw = await InsightFileStorage.readSurah('word-tasreef', 5);
      expect(raw, isNotNull,
          reason: 'nothing reached disk — the temp dir mock may be wrong');
      final doc = jsonDecode(raw!) as Map<String, dynamic>;
      expect(doc.keys.length, 10);
      expect(doc['7'], ['w7']);
    });
  });

  group('persistence across sessions', () {
    test('entries survive dropping the in-memory maps', () async {
      await InsightCache.write('meaning-word-oldv', 18, 10, ['معنى']);

      // Simulate a fresh launch: the process cache is gone, the files
      // are not. Reading must come back from disk.
      InsightCache.forgetInMemory();

      final (found, value) = await InsightCache.read('meaning-word-oldv', 18, 10);
      expect(found, isTrue, reason: 'the entry did not survive on disk');
      expect((value as List).single, 'معنى');
    });
  });

  // flutter_test answers every HTTP request with a 400, so anything
  // that reaches the network here throws. That makes these a real test
  // of the offline promise: an ayah opened once reads back with no
  // connection at all.
  group('reading offline', () {
    test('a cached ayah is served without touching the network', () async {
      await InsightCache.write('eerab-word', 2, 255, [
        {'word_number': 1, 'word': 'اللَّهُ', 'content': 'مبتدأ مرفوع'},
      ]);

      final got = await AyahInsightService.words(InsightKind.eerab, 2, 255);
      expect(got.single.content, 'مبتدأ مرفوع');
    });

    test('a cached ayah-level parse is served offline too', () async {
      await InsightCache.write('eerab-aya', 2, 255, 'إعراب الآية كاملة');

      expect(await AyahInsightService.ayahText(InsightKind.eerab, 2, 255),
          'إعراب الآية كاملة');
    });

    test('a cached "no entry" answers null instead of failing', () async {
      await InsightCache.write('eerab-aya', 2, 254, null);

      expect(await AyahInsightService.ayahText(InsightKind.eerab, 2, 254),
          isNull);
    });

    test('an ayah never opened still reports the failure', () async {
      await expectLater(
        AyahInsightService.words(InsightKind.eerab, 2, 100),
        throwsA(isA<Exception>()),
      );
    });

    test('the word strip survives every book being unreachable', () async {
      // wordTokens must not propagate a failure — an empty strip falls
      // back to the plain ayah text, a thrown error would blank the card.
      expect(await AyahInsightService.wordTokens(2, 101), isEmpty);
    });

    test('the word strip uses whatever is cached', () async {
      await InsightCache.write('eerab-word', 2, 102, [
        {'word_number': 2, 'word': 'ثانية', 'content': 'ج'},
        {'word_number': 1, 'word': 'أولى', 'content': 'ج'},
      ]);

      // Ordered by word number, whatever order the book returned them in.
      expect(await AyahInsightService.wordTokens(2, 102), ['أولى', 'ثانية']);
    });
  });

  group('clearing', () {
    test('removes everything and reports zero size', () async {
      await InsightCache.write('eerab-word', 2, 255, const ['x']);
      expect(await AyahInsightService.cachedSizeBytes(), greaterThan(0));

      await AyahInsightService.clearCache();

      expect(await AyahInsightService.cachedSizeBytes(), 0);
      expect((await InsightCache.read('eerab-word', 2, 255)).$1, isFalse);
    });
  });
}
