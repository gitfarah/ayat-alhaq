// The rating prompt is the one thing in this app that interrupts a
// reader, and Apple only allows three of them per year. These tests pin
// down when it is allowed to fire — and, mostly, when it is not.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/screens/main_screen.dart';
import 'package:quran_app_v1/services/app_review_service.dart';
import 'package:quran_app_v1/services/quran_audio_service.dart';
import 'package:quran_app_v1/services/settings_service.dart';

/// Stands in for the platform plugin so nothing reaches a real store.
class _FakeReview implements InAppReview {
  int requested = 0;
  int listingsOpened = 0;
  String? lastAppStoreId;

  /// Flipped by the test that covers a device with no reachable store.
  bool available = true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requested++;

  @override
  Future<void> openStoreListing({
    String? appStoreId,
    String? microsoftStoreId,
  }) async {
    lastAppStoreId = appStoreId;
    listingsOpened++;
  }
}

String _iso(int daysAgo) =>
    DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String();

/// Distinct calendar days, newest first, in the yyyy-MM-dd the service
/// writes.
List<String> _days(int count) => [
      for (var i = 0; i < count; i++)
        () {
          final d = DateTime.now().subtract(Duration(days: i));
          return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';
        }()
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeReview fake;

  setUp(() {
    fake = _FakeReview();
    AppReviewService.debugOverride = fake;
  });

  tearDown(() => AppReviewService.debugOverride = null);

  /// A reader who has cleared every engagement gate and just finished a
  /// juz — the one state in which asking is allowed.
  void earnedIt({int askCount = 0, String? lastAsked}) {
    SharedPreferences.setMockInitialValues({
      'review.pending': true,
      'review.days': _days(5),
      'review.firstSeen': _iso(30),
      'review.askCount': askCount,
      if (lastAsked != null) 'review.lastAsked': lastAsked,
    });
  }

  group('when the prompt is allowed', () {
    test('a completed juz from a long-time reader asks once', () async {
      earnedIt();
      expect(await AppReviewService.shouldAsk(), isTrue);

      await AppReviewService.maybeRequestReview();
      expect(fake.requested, 1);
    });

    test('the milestone is spent, not re-asked on every visit', () async {
      earnedIt();
      await AppReviewService.maybeRequestReview();
      // The khatma screen reloads on every tab switch — asking again
      // each time would burn the year's quota in an afternoon.
      await AppReviewService.maybeRequestReview();
      await AppReviewService.maybeRequestReview();
      expect(fake.requested, 1);
    });
  });

  group('when it must stay silent', () {
    test('no milestone armed', () async {
      SharedPreferences.setMockInitialValues({
        'review.days': _days(5),
        'review.firstSeen': _iso(30),
      });
      expect(await AppReviewService.shouldAsk(), isFalse);
      await AppReviewService.maybeRequestReview();
      expect(fake.requested, 0);
    });

    test('a brand-new reader who binge-read on day one', () async {
      // Every page of a juz read in one sitting, minutes after install.
      SharedPreferences.setMockInitialValues({
        'review.pending': true,
        'review.days': _days(1),
        'review.firstSeen': _iso(0),
      });
      expect(await AppReviewService.shouldAsk(), isFalse);
    });

    test('used on enough days, but only installed today', () async {
      SharedPreferences.setMockInitialValues({
        'review.pending': true,
        'review.days': _days(5),
        'review.firstSeen': _iso(1),
      });
      expect(await AppReviewService.shouldAsk(), isFalse);
    });

    test('asked recently — a decline is not chased', () async {
      earnedIt(askCount: 1, lastAsked: _iso(10));
      expect(await AppReviewService.shouldAsk(), isFalse);
    });

    test('asked long enough ago is allowed again', () async {
      earnedIt(askCount: 1, lastAsked: _iso(200));
      expect(await AppReviewService.shouldAsk(), isTrue);
    });

    test('never more than three times, whatever the interval', () async {
      earnedIt(askCount: 3, lastAsked: _iso(900));
      expect(await AppReviewService.shouldAsk(), isFalse);
    });
  });

  group('failure never reaches the reader', () {
    test('an unavailable store spends the milestone without throwing',
        () async {
      earnedIt();
      fake.available = false;

      await AppReviewService.maybeRequestReview();

      expect(fake.requested, 0);
      // Not re-armed: a device with no store would otherwise retry on
      // every single khatma-screen load, forever.
      expect(await AppReviewService.shouldAsk(), isFalse);
    });

    test('a throwing plugin is swallowed', () async {
      earnedIt();
      AppReviewService.debugOverride = _ThrowingReview();
      await expectLater(AppReviewService.maybeRequestReview(), completes);
    });
  });

  group('bookkeeping', () {
    test('recordSession stamps first-seen once and counts the day',
        () async {
      SharedPreferences.setMockInitialValues({});
      await AppReviewService.recordSession();

      final p = await SharedPreferences.getInstance();
      final firstSeen = p.getString('review.firstSeen');
      expect(firstSeen, isNotNull);
      expect(p.getStringList('review.days')!.length, 1);

      // Re-launching the same day must not move first-seen or inflate
      // the day count — that would let the engagement bar be cleared
      // by opening the app repeatedly in one sitting.
      await AppReviewService.recordSession();
      await AppReviewService.recordSession();
      expect(p.getString('review.firstSeen'), firstSeen);
      expect(p.getStringList('review.days')!.length, 1);
    });

    test('the day list does not grow without bound', () async {
      SharedPreferences.setMockInitialValues({'review.days': _days(40)});
      await AppReviewService.recordSession();

      final p = await SharedPreferences.getInstance();
      expect(p.getStringList('review.days')!.length, lessThanOrEqualTo(30));
    });

    test('noteMilestone only arms, it never shows anything', () async {
      SharedPreferences.setMockInitialValues({
        'review.days': _days(5),
        'review.firstSeen': _iso(30),
      });

      await AppReviewService.noteMilestone();

      // Nothing was drawn — the reader is mid-page when this fires.
      expect(fake.requested, 0);
      expect(await AppReviewService.shouldAsk(), isTrue,
          reason: 'armed and ready for the khatma screen to spend');
    });
  });

  group('store listing (the button-safe path)', () {
    test('opens the listing directly, never the quota-limited sheet',
        () async {
      SharedPreferences.setMockInitialValues({});
      await AppReviewService.openStoreListing();

      expect(fake.listingsOpened, 1);
      // Apple guideline 1.1.7: requestReview() must not be wired to a
      // tap. The settings row must never reach it.
      expect(fake.requested, 0);
    });

    test('carries the App Store ID through to the plugin', () async {
      SharedPreferences.setMockInitialValues({});
      await AppReviewService.openStoreListing();

      // iOS cannot resolve the listing without it, and a wrong or
      // missing value silently opens another app's page.
      expect(fake.lastAppStoreId, '6794894864');
      expect(AppReviewService.canOpenListing, isTrue,
          reason: 'with an ID set, the row shows on every platform');
    });
  });

  group('where the prompt is spent', () {
    Widget host() => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsService()),
            ChangeNotifierProvider(create: (_) => QuranAudioService()),
          ],
          child: const MaterialApp(home: MainScreen()),
        );

    testWidgets('NOT at app launch, even with a milestone armed and every '
        'gate clear', (tester) async {
      earnedIt();

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Every tab is built at start inside the IndexedStack. A hook on
      // the khatma screen's own load therefore fired the prompt on
      // launch, over whichever tab the reader was actually on.
      expect(fake.requested, 0,
          reason: 'launching the app must never trigger a rating prompt');
    });

    testWidgets('when the reader opens the khatma tracker', (tester) async {
      earnedIt();

      await tester.pumpWidget(host());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.check_circle_outline_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fake.requested, 1);
    });
  });
}

class _ThrowingReview implements InAppReview {
  @override
  Future<bool> isAvailable() async => throw Exception('no store');

  @override
  Future<void> requestReview() async => throw Exception('no store');

  @override
  Future<void> openStoreListing({
    String? appStoreId,
    String? microsoftStoreId,
  }) async =>
      throw Exception('no store');
}
