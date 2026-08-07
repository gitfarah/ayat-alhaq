import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quran_app_v1/models/quran_page_meta.dart';
import 'package:quran_app_v1/services/khatma_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<bool>> khatmaDone() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('khatma');
    if (raw == null) return List.filled(30, false);
    return (jsonDecode(raw)['done'] as List).map((e) => e as bool).toList();
  }

  test('reading every page of juz 30 auto-completes it — and only it',
      () async {
    SharedPreferences.setMockInitialValues({});
    final start = QuranPageMeta.juzStartPages[29]; // 582
    for (var page = start; page <= 604; page++) {
      await KhatmaService.markPageRead(page);
    }
    final done = await khatmaDone();
    expect(done[29], isTrue);
    expect(done.sublist(0, 29).any((d) => d), isFalse);
  });

  test('a partially read juz stays unchecked', () async {
    SharedPreferences.setMockInitialValues({});
    // All of juz 1 except its last page.
    for (var page = 1; page <= QuranPageMeta.juzStartPages[1] - 2; page++) {
      await KhatmaService.markPageRead(page);
    }
    expect((await khatmaDone())[0], isFalse);
    // Reading the final page completes it.
    await KhatmaService.markPageRead(QuranPageMeta.juzStartPages[1] - 1);
    expect((await khatmaDone())[0], isTrue);
  });

  test('manual khatma progress is preserved when a juz auto-completes',
      () async {
    SharedPreferences.setMockInitialValues({
      'khatma': jsonEncode({
        'done': [for (var i = 0; i < 30; i++) i == 4],
        'start': DateTime(2026, 1, 1).toIso8601String(),
      }),
    });
    final start = QuranPageMeta.juzStartPages[29];
    for (var page = start; page <= 604; page++) {
      await KhatmaService.markPageRead(page);
    }
    final done = await khatmaDone();
    expect(done[4], isTrue); // manual tick untouched
    expect(done[29], isTrue); // auto tick added
  });

  test('resetReadPages clears the page record', () async {
    SharedPreferences.setMockInitialValues({});
    await KhatmaService.markPageRead(10);
    expect(await KhatmaService.readPageCount(), 1);
    await KhatmaService.resetReadPages();
    expect(await KhatmaService.readPageCount(), 0);
  });

  test('completing a juz arms a rating request — and reading on does not '
      'arm anything by itself', () async {
    SharedPreferences.setMockInitialValues({});
    Future<bool> armed() async =>
        (await SharedPreferences.getInstance()).getBool('review.pending') ??
        false;

    // Most of juz 30 read: an achievement in progress, not yet earned.
    final start = QuranPageMeta.juzStartPages[29];
    for (var page = start; page < 604; page++) {
      await KhatmaService.markPageRead(page);
    }
    expect(await armed(), isFalse);

    // The page that completes it.
    await KhatmaService.markPageRead(604);
    expect(await armed(), isTrue,
        reason: 'a finished juz is the milestone worth asking on');
  });
}
