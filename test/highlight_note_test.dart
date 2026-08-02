import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quran_app_v1/services/highlight_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Highlight mark(String color, {String? note}) => Highlight(
        surahNumber: 2,
        ayahNumber: 255,
        surahName: 'البقرة',
        color: color,
        note: note,
        createdAt: DateTime(2026, 1, 1),
        page: 42,
      );

  Future<Highlight?> read() => HighlightService.getHighlight(2, 255);

  test('a note is written onto an existing colour mark', () async {
    SharedPreferences.setMockInitialValues({});
    await HighlightService.addHighlight(mark('green'));

    await HighlightService.setNote(2, 255, note: '  تدبر آية الكرسي  ');

    final h = await read();
    expect(h!.note, 'تدبر آية الكرسي', reason: 'stored trimmed');
    expect(h.hasNote, isTrue);
    expect(h.color, 'green', reason: 'the colour mark is untouched');
    expect(h.page, 42, reason: 'origin is preserved');
  });

  test('recolouring a marked ayah keeps its note', () async {
    SharedPreferences.setMockInitialValues({});
    await HighlightService.addHighlight(mark('green'));
    await HighlightService.setNote(2, 255, note: 'ملاحظة');

    // The colour pickers build a fresh Highlight carrying no note.
    await HighlightService.addHighlight(mark('blue'));

    final h = await read();
    expect(h!.color, 'blue');
    expect(h.note, 'ملاحظة');
  });

  test('a note on an unmarked ayah creates the mark too', () async {
    SharedPreferences.setMockInitialValues({});

    await HighlightService.setNote(2, 255,
        note: 'ملاحظة', surahName: 'البقرة', page: 42);

    final h = await read();
    expect(h, isNotNull);
    expect(h!.color, 'yellow', reason: 'default colour');
    expect(h.surahName, 'البقرة');
    expect(h.page, 42);
  });

  test('a blank note on an unmarked ayah creates nothing', () async {
    SharedPreferences.setMockInitialValues({});

    await HighlightService.setNote(2, 255, note: '   ');

    expect(await read(), isNull);
    expect(await HighlightService.getAllHighlights(), isEmpty);
  });

  test('clearing a note keeps the colour mark', () async {
    SharedPreferences.setMockInitialValues({});
    await HighlightService.addHighlight(mark('pink'));
    await HighlightService.setNote(2, 255, note: 'ملاحظة');

    await HighlightService.setNote(2, 255, note: null);

    final h = await read();
    expect(h, isNotNull, reason: 'deleting a note is not deleting the mark');
    expect(h!.hasNote, isFalse);
    expect(h.note, isNull);
    expect(h.color, 'pink');
  });

  test('notes survive a save/load round trip and stay per-ayah', () async {
    SharedPreferences.setMockInitialValues({});
    await HighlightService.setNote(2, 255, note: 'أولى', surahName: 'البقرة');
    await HighlightService.setNote(2, 256, note: 'ثانية', surahName: 'البقرة');

    final all = await HighlightService.getAllHighlights();
    expect(all.length, 2);
    expect((await HighlightService.getHighlight(2, 255))!.note, 'أولى');
    expect((await HighlightService.getHighlight(2, 256))!.note, 'ثانية');

    // Deleting one mark leaves the other's note intact.
    await HighlightService.deleteHighlight(2, 255);
    expect(await HighlightService.getHighlight(2, 255), isNull);
    expect((await HighlightService.getHighlight(2, 256))!.note, 'ثانية');
  });
}
