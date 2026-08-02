// The reading screens must hold the display on, and must let go of it
// again — a leaked wake lock would drain a phone left on a Mushaf page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quran_app_v1/services/screen_awake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.omar.quran_app_v1/screen_awake');
  late List<bool> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setKeepAwake') {
        calls.add((call.arguments as Map)['enabled'] as bool);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('a reading screen holds the display on and releases it',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Reading()));
    await tester.pumpAndSettle();
    expect(calls, [true], reason: 'acquired when the screen opened');

    // Leaving the screen releases it.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(calls, [true, false]);
  });

  testWidgets('stacked reading screens hold one lock until the last closes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Column(children: [_Reading(), _Reading()])));
    await tester.pumpAndSettle();
    expect(calls, [true], reason: 'the second holder must not re-send');

    // Only one of the two goes away — the lock stays.
    await tester.pumpWidget(const MaterialApp(home: _Reading()));
    await tester.pumpAndSettle();
    expect(calls, [true]);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(calls, [true, false], reason: 'released once the last one closed');
  });
}

/// Stand-in for the Mushaf/reader screens, which use the same mixin.
class _Reading extends StatefulWidget {
  const _Reading();
  @override
  State<_Reading> createState() => _ReadingState();
}

class _ReadingState extends State<_Reading> with KeepsScreenAwake<_Reading> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
