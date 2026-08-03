// L10n.of must be safe to call both during build (where it should
// watch, so widgets rebuild on a language change) and from an event
// handler like onTap/onLongPress (where `context.watch` is invalid and
// throws Provider's own debug assertion — see the 2026-08-02 incident
// where this crashed every long-press menu and audio control in the
// app before any bottom sheet was ever built).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/l10n/app_strings.dart';
import 'package:quran_app_v1/services/settings_service.dart';

void main() {
  // SettingsService.setAppLanguage persists via SharedPreferences.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host({required Widget Function(BuildContext) builder}) =>
      ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: MaterialApp(home: Builder(builder: builder)),
      );

  testWidgets('called during build, it reads the current language',
      (tester) async {
    late String code;
    await tester.pumpWidget(host(builder: (context) {
      code = L10n.of(context).code;
      return const SizedBox();
    }));
    expect(code, 'ar');
  });

  testWidgets(
      'called from an event handler (outside build), it does not throw',
      (tester) async {
    late BuildContext savedContext;
    Object? caught;

    await tester.pumpWidget(host(builder: (context) {
      savedContext = context;
      return ElevatedButton(
        onPressed: () {
          // This is the exact failure mode: Provider.of/watch is only
          // valid while `context.owner!.debugBuilding` is true, which
          // is false here — we're inside a button's onPressed, not a
          // build() call.
          try {
            L10n.of(savedContext);
          } catch (e) {
            caught = e;
          }
        },
        child: const Text('go'),
      );
    }));

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(caught, isNull,
        reason: 'L10n.of threw when called from an event handler — '
            'this is the exact regression that broke every popup menu');
  });

  testWidgets('the value read from an event handler is still correct',
      (tester) async {
    late BuildContext savedContext;
    String? result;

    await tester.pumpWidget(host(builder: (context) {
      savedContext = context;
      return ElevatedButton(
        onPressed: () => result = L10n.of(savedContext)('tafsir'),
        child: const Text('go'),
      );
    }));

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(result, 'التفسير');
  });

  testWidgets('a build-time caller still rebuilds when the language changes',
      (tester) async {
    // The fallback to `read` must only kick in for the invalid
    // (outside-build) case — legitimate build-time callers must keep
    // rebuilding on a language change, or settings/home screens would
    // go stale after switching language.
    var buildCount = 0;
    late SettingsService settings;

    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SettingsService(),
      child: MaterialApp(
        home: Builder(builder: (context) {
          settings = context.read<SettingsService>();
          buildCount++;
          return Text(L10n.of(context)('tafsir'));
        }),
      ),
    ));

    final before = buildCount;
    await settings.setAppLanguage('en');
    await tester.pump();

    expect(buildCount, greaterThan(before));
    expect(find.text('Tafsir'), findsOneWidget);
  });
}
