// Generates the compact runtime layout used by the KFGQPC V4 Mushaf view.
//
// Source: QUL's KFGQPC V4 layout (1441H print):
// https://qul.tarteel.ai/resources/mushaf-layout/19
// QUL source code is MIT licensed: https://github.com/TarteelAI/quranic-universal-library
//
// Run from the project root:
//   dart run tool/generate_qul_v4_layout.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _baseUrl = 'https://qul.tarteel.ai/resources/mushaf-layout/19?page=';
const _output = 'assets/quran/mushaf_v4_1441h_layout.json';

Future<void> main() async {
  final client = HttpClient()..userAgent = 'QuranApp-layout-generator/1.0';
  final pages = List<Map<String, Object?>?>.filled(604, null);
  var next = 1;

  Future<void> worker() async {
    while (true) {
      final page = next++;
      if (page > 604) return;
      pages[page - 1] = await _fetchPage(client, page);
    }
  }

  try {
    await Future.wait(List.generate(20, (_) => worker()));
  } finally {
    client.close(force: true);
  }

  final file = File(_output);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode({
    'source': 'https://qul.tarteel.ai/resources/mushaf-layout/19',
    'name': 'KFGQPC V4 layout (1441H print)',
    'pages': pages,
  }));
  stdout.writeln('Wrote ${file.path} (${await file.length()} bytes)');
}

Future<Map<String, Object?>> _fetchPage(HttpClient client, int page) async {
  Object? lastError;
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      final request = await client.getUrl(Uri.parse('$_baseUrl$page'));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for page $page');
      }
      final html = await response.transform(utf8.decoder).join();
      return _parsePage(html, page);
    } catch (error) {
      lastError = error;
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
  }
  throw StateError('Could not fetch QUL page $page: $lastError');
}

Map<String, Object?> _parsePage(String html, int page) {
  final pageStart = html.indexOf('id="page-$page"');
  if (pageStart < 0) throw FormatException('Missing page-$page');
  final pageEnd = html.indexOf('</turbo-frame>', pageStart);
  final body = html.substring(pageStart, pageEnd < 0 ? html.length : pageEnd);
  final starts = RegExp(r'<div class="line-container" data-line="(\d+)">')
      .allMatches(body)
      .toList();
  if (starts.isEmpty) throw FormatException('No lines on page $page');

  final lines = <Map<String, Object?>>[];
  for (var i = 0; i < starts.length; i++) {
    final match = starts[i];
    final end = i + 1 < starts.length ? starts[i + 1].start : body.length;
    final chunk = body.substring(match.start, end);
    final number = int.parse(match.group(1)!);
    final classMatch = RegExp(r'<div class="line ([^"]*)"').firstMatch(chunk);
    final classes = classMatch?.group(1) ?? '';

    if (classes.contains('line--surah-name')) {
      final surah = RegExp(r'surah(\d{3})').firstMatch(chunk);
      if (surah == null) {
        throw FormatException('Missing surah on $page:$number');
      }
      lines.add({'n': number, 't': 's', 's': int.parse(surah.group(1)!)});
      continue;
    }
    if (classes.contains('line--bismillah')) {
      lines.add({'n': number, 't': 'b'});
      continue;
    }

    final words = <List<Object>>[];
    final wordPattern = RegExp(
      r'<span class="char\s+([^"]*)"[\s\S]*?data-location="([0-9:]+)"[\s\S]*?data-ayah="([0-9:]+)"[\s\S]*?<a[^>]*>\s*([^<]+?)\s*</a>',
    );
    for (final word in wordPattern.allMatches(chunk)) {
      final item = <Object>[word.group(4)!.trim(), word.group(3)!];
      if (word.group(1)!.contains('char-end')) item.add(1);
      words.add(item);
    }
    if (words.isEmpty) continue;
    lines.add({
      'n': number,
      't': 'a',
      if (classes.contains('line--center')) 'c': 1,
      'w': words,
    });
  }
  return {'p': page, 'l': lines};
}
