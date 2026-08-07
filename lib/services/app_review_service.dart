import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks — rarely, and only after the reader has earned something — for
/// an App Store / Play Store rating, using the platform's own native
/// sheet.
///
/// Apple REQUIRES this API: App Store Review Guideline 1.1.7 disallows
/// custom "rate us" dialogs. It also caps the prompt at three showings
/// per user per 365 days and enforces that itself, so the counters here
/// are not about obeying the quota — they are about not spending it
/// badly. A prompt the system swallows is a prompt wasted.
///
/// Two rules shape the design:
///
///  * Apple says not to call [requestReview] from a button tap. The
///    "rate this app" row in settings therefore uses
///    [openStoreListing], which has no quota and is meant for exactly
///    that.
///  * Never interrupt someone mid-recitation. Finishing a juz happens
///    while the reader is deep in a page, so the milestone only ARMS
///    the request ([noteMilestone]); it is spent later, when they next
///    look at the khatma tracker and see the juz ticked off.
class AppReviewService {
  /// Numeric App Store ID (App Store Connect → App Information →
  /// "Apple ID"), needed to open the iOS listing. Android ignores it
  /// and resolves the listing from the package name instead.
  ///
  /// If this is ever emptied, the settings row hides itself on iOS
  /// rather than sending readers to some other app's page — see
  /// [canOpenListing]. The native prompt never needs it.
  // Deliberately nullable: [canOpenListing] and openStoreListing() both
  // handle a null ID, so emptying this stays a one-line, safe change.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const String? appStoreId = '6794894864';

  static const _firstSeenKey = 'review.firstSeen';
  static const _daysKey = 'review.days';
  static const _lastAskedKey = 'review.lastAsked';
  static const _askCountKey = 'review.askCount';
  static const _pendingKey = 'review.pending';

  /// Engagement bar before the reader is asked anything.
  static const _minDistinctDays = 3;
  static const _minDaysSinceFirstSeen = 3;

  /// Upper bound on the remembered day list — well above
  /// [_minDistinctDays], which is all it is ever compared against.
  static const _maxTrackedDays = 30;

  /// Well clear of Apple's 3-per-365-days cap: at most one ask a
  /// season, so a reader who declines is not chased.
  static const _minDaysBetweenAsks = 120;
  static const _maxAsks = 3;

  /// Test seam. Left null in the app so the real plugin is used.
  static InAppReview? debugOverride;
  static InAppReview get _review => debugOverride ?? InAppReview.instance;

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// Call once per app launch. Records that the app was opened today,
  /// which is what the "used on N different days" bar counts.
  static Future<void> recordSession() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString(_firstSeenKey) == null) {
      await p.setString(_firstSeenKey, DateTime.now().toIso8601String());
    }

    final stored = p.getStringList(_daysKey) ?? [];
    final days = stored.toSet()..add(_today());

    // Only the COUNT matters and the bar is small, so keep the most
    // recent days and drop the rest — otherwise this grows one entry
    // per day for the life of the install. Trimmed unconditionally,
    // not just when today is new: a list left over-long by an earlier
    // build would otherwise never shrink.
    final recent = days.toList()..sort();
    if (recent.length > _maxTrackedDays) {
      recent.removeRange(0, recent.length - _maxTrackedDays);
    }
    if (recent.length != stored.length || !recent.every(stored.contains)) {
      await p.setStringList(_daysKey, recent);
    }
  }

  /// Arms a request after a genuine achievement (a juz completed by
  /// actually reading its pages). Does NOT show anything: the reader is
  /// mid-page when this fires.
  static Future<void> noteMilestone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_pendingKey, true);
  }

  /// Whether an armed milestone has cleared every gate. Split out so
  /// the rules can be tested without the platform plugin.
  static Future<bool> shouldAsk() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_pendingKey) ?? false)) return false;
    if ((p.getInt(_askCountKey) ?? 0) >= _maxAsks) return false;

    final days = (p.getStringList(_daysKey) ?? []).length;
    if (days < _minDistinctDays) return false;

    final firstSeen = DateTime.tryParse(p.getString(_firstSeenKey) ?? '');
    if (firstSeen == null ||
        DateTime.now().difference(firstSeen).inDays < _minDaysSinceFirstSeen) {
      return false;
    }

    final lastAsked = DateTime.tryParse(p.getString(_lastAskedKey) ?? '');
    if (lastAsked != null &&
        DateTime.now().difference(lastAsked).inDays < _minDaysBetweenAsks) {
      return false;
    }
    return true;
  }

  /// Spends an armed milestone if every gate is clear. Safe to call
  /// from any quiet screen; does nothing the vast majority of the time.
  ///
  /// The pending flag is cleared whether or not the system actually
  /// drew the sheet — [requestReview] reports neither, and re-arming on
  /// silence would turn one milestone into repeated attempts.
  static Future<void> maybeRequestReview() async {
    if (!await shouldAsk()) return;

    final p = await SharedPreferences.getInstance();
    await p.setBool(_pendingKey, false);

    try {
      if (!await _review.isAvailable()) return;
      await p.setString(_lastAskedKey, DateTime.now().toIso8601String());
      await p.setInt(_askCountKey, (p.getInt(_askCountKey) ?? 0) + 1);
      await _review.requestReview();
    } catch (_) {
      // No store, no Play Services, an unsupported platform — asking
      // for a rating must never be able to break the app.
    }
  }

  /// True when the store listing can actually be reached. Android
  /// resolves it from the package name; iOS/macOS need [appStoreId],
  /// so until that is filled in the settings row stays hidden there
  /// rather than opening some other app's page.
  static bool get canOpenListing =>
      defaultTargetPlatform == TargetPlatform.android || appStoreId != null;

  /// Opens the store listing directly. This is the ONLY form allowed
  /// behind a button: [requestReview] must not be wired to a tap.
  static Future<void> openStoreListing() async {
    try {
      await _review.openStoreListing(appStoreId: appStoreId);
    } catch (_) {
      // Nothing useful to tell the reader if the store is unreachable.
    }
  }
}
