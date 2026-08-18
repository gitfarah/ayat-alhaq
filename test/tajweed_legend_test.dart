// Regression coverage for a real complaint: the on-page tajweed legend
// looked "incomplete" because it was a single-line horizontal scroll
// strip a reader had to swipe through — unlike the multi-line Wrap
// Settings already showed, which reveals every rule at once. Both now
// share ONE widget (TajweedLegendChips) so they can never drift apart
// again, and these tests pin that every rule actually renders.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_app_v1/services/settings_service.dart';
import 'package:quran_app_v1/services/tajweed_service.dart';
import 'package:quran_app_v1/widgets/tajweed_legend_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'TajweedLegendChips names every rule in legendOrder, not a subset',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TajweedLegendChips(lang: 'ar', textColor: Colors.black),
        ),
      ),
    ));

    for (final rule in TajweedService.legendOrder) {
      final name = TajweedService.ruleNames['ar']![rule]!;
      expect(find.text(name), findsOneWidget,
          reason: '"$name" ($rule) is missing from the legend');
    }
    // Not a scrolling strip: everything lays out via Wrap, so nothing
    // needs a swipe to be found.
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('the on-page bar opens expanded, showing the full legend',
      (tester) async {
    // expanded/onToggle are owned by the CALLER (not private State) so
    // a host screen can reserve matching bottom padding for whichever
    // height the bar is currently at — see mushaf_reader_screen.dart's
    // _bottomReserve. Exercised here with a small stateful harness
    // standing in for that caller.
    var expanded = true;
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => SettingsService())],
      child: MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            return SingleChildScrollView(
              child: TajweedLegendBar(
                isDark: false,
                expanded: expanded,
                onToggle: () => setState(() => expanded = !expanded),
              ),
            );
          }),
        ),
      ),
    ));
    await tester.pump();

    for (final rule in TajweedService.legendOrder) {
      expect(find.text(TajweedService.ruleNames['ar']![rule]!), findsOneWidget);
    }

    // The chevron collapses it away, for a reader who wants the space
    // back — and expands it again.
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pump();
    expect(
        find.text(TajweedService.ruleNames['ar']!['ghunnah']!), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_less_rounded));
    await tester.pump();
    expect(
        find.text(TajweedService.ruleNames['ar']!['ghunnah']!), findsOneWidget);
  });
}
