import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Draws a Mushaf page with the space between its printed lines opened
/// up, so the page fills the screen's height.
///
/// A Mushaf leaf is proportionally much wider than a phone, so fitting
/// its width always leaves vertical slack — dead space under the last
/// line. Giving that slack to the line spacing is what makes the small
/// print of a 604-page Mushaf comfortable to read.
///
/// The page artwork is a single enormous vector path (every glyph on the
/// page in one `<path>`), so the lines cannot be moved in the SVG. The
/// page is rasterised once and then redrawn as a handful of horizontal
/// strips under a CONTINUOUS vertical mapping: rows that carry ink are
/// translated rigidly, and only the blank rows between lines are
/// stretched.
///
/// The continuity matters more than anything else here. An earlier
/// version cut the page into one strip per line and moved each strip
/// down — which tore the top off any alif and the tail off any kasra
/// that reached into a neighbouring line, and in this script a great
/// many of them do. A mapping with no cuts in it cannot tear anything:
/// every pixel of the page still has exactly one destination, and the
/// only rows whose spacing changes are the ones between the lines.
class MushafPageStretch {
  /// Share of a page's typical row ink at or below which a row counts
  /// as lying BETWEEN two lines rather than on one. See [gapRunsOf].
  static const double gapInkFraction = 0.22;

  /// Source breakpoints in viewBox units, ascending. The first is the
  /// page top and the last the page bottom.
  final List<double> src;

  /// Where each breakpoint lands, in viewBox units. Piecewise-linear in
  /// between, monotonic, and equal to [src] at the top of the page.
  final List<double> dst;

  const MushafPageStretch(this.src, this.dst);

  int get segmentCount => src.length - 1;

  /// How much taller the page becomes.
  double get extraHeight => (dst.last - dst.first) - (src.last - src.first);

  /// Where [y] ends up.
  double mapY(double y) {
    if (y <= src.first) return dst.first + (y - src.first);
    if (y >= src.last) return dst.last + (y - src.last);
    for (var i = 0; i < segmentCount; i++) {
      if (y > src[i + 1]) continue;
      final span = src[i + 1] - src[i];
      final t = span <= 0 ? 0.0 : (y - src[i]) / span;
      return dst[i] + (dst[i + 1] - dst[i]) * t;
    }
    return y;
  }

  /// How far the page has moved at [y] — what the overlays are shifted
  /// by so a highlight travels with the line it belongs to.
  double offsetFor(double y) => mapY(y) - y;

  /// Stretched coordinates back to the printed page's own, for
  /// hit-testing a tap.
  double unmap(double y) {
    if (y <= dst.first) return src.first + (y - dst.first);
    if (y >= dst.last) return src.last + (y - dst.last);
    for (var i = 0; i < segmentCount; i++) {
      if (y > dst[i + 1]) continue;
      final span = dst[i + 1] - dst[i];
      final t = span <= 0 ? 0.0 : (y - dst[i]) / span;
      return src[i] + (src[i + 1] - src[i]) * t;
    }
    return y;
  }

  /// Builds the mapping that adds [extra] viewBox units of height,
  /// spending all of it on the runs in [gapRuns].
  ///
  /// [gapRuns] is a flat list of start/end pairs as fractions of the
  /// page height — the rows that fall between the printed lines.
  static MushafPageStretch? build(
    List<double> gapRuns, {
    required double top,
    required double height,
    required double extra,
  }) {
    if (gapRuns.length < 4 || gapRuns.length.isOdd || extra <= 0) {
      return null;
    }
    final gaps = [
      for (var i = 0; i + 1 < gapRuns.length; i += 2)
        (gapRuns[i + 1] - gapRuns[i]) * height,
    ];
    if (gaps.isEmpty) return null;

    // Share the slack out by RAISING THE SHORTEST GAPS FIRST, until they
    // are all the same or the slack runs out.
    //
    // Handing each gap a share proportional to its own size looked like
    // the obvious thing and was wrong: it widens the gaps that are
    // already wide and leaves the tight ones tight, so the page comes
    // out lumpier than it started. A printed page has one line rhythm,
    // so the slack should go where the rhythm is short.
    final sorted = [...gaps]..sort();
    var level = sorted.first;
    var covered = 0;
    var spent = 0.0;
    for (var i = 0; i < sorted.length; i++) {
      final next = i + 1 < sorted.length ? sorted[i + 1] : double.infinity;
      covered = i + 1;
      final costToNext = (next - level) * covered;
      if (spent + costToNext >= extra) {
        level += (extra - spent) / covered;
        spent = extra;
        break;
      }
      spent += costToNext;
      level = next;
    }
    if (spent < extra) level += (extra - spent) / covered;

    final src = <double>[top];
    final dst = <double>[top];
    var shift = 0.0;
    var gapIndex = 0;
    for (var i = 0; i + 1 < gapRuns.length; i += 2) {
      final runTop = top + gapRuns[i] * height;
      final runBottom = top + gapRuns[i + 1] * height;
      // The inked stretch above this run: carried down bodily, at unit
      // scale, so nothing on it is distorted.
      src.add(runTop);
      dst.add(runTop + shift);
      // The run itself: this is where the space goes.
      final add = level - gaps[gapIndex++];
      if (add > 0) shift += add;
      src.add(runBottom);
      dst.add(runBottom + shift);
    }
    src.add(top + height);
    dst.add(top + height + shift);
    return MushafPageStretch(src, dst);
  }

  /// The runs of rows that lie BETWEEN the printed lines of a rasterised
  /// page, as fractions of its height. [inkPerRow] is how many sampled
  /// columns carry ink on each row.
  ///
  /// Not "rows carrying no ink at all", which is what this used to look
  /// for and is why the pages went on ending in dead space. In this
  /// script the ascenders and descenders of neighbouring lines reach
  /// into the space between them: on a real Hafs page barely half the
  /// line gaps contain even one completely clear row, so the page failed
  /// the "is this set text at all" test and was drawn unstretched — the
  /// whole of the leftover height then piling up under the last line.
  ///
  /// What separates two lines is a VALLEY in the ink, not a void: a run
  /// of rows carrying a few per cent of what a line carries. Stretching
  /// a valley is every bit as safe as stretching a void, because what
  /// crosses one is almost always a near-vertical stroke — an alif's
  /// stem, a ya's tail — and making a vertical stroke slightly longer is
  /// not a distortion anyone can see. The bowls, ligatures and diacritic
  /// clusters that WOULD show it all sit in the line bodies, and those
  /// are still carried down rigidly, at unit scale.
  ///
  /// Only the runs between the first and last inked row count: the head
  /// and foot margins are not line spacing, and spending the slack there
  /// would just push the text off centre.
  static List<double>? gapRunsOf(List<int> inkPerRow) {
    final h = inkPerRow.length;
    if (h < 16) return null;

    var firstInk = -1;
    var lastInk = -1;
    for (var y = 0; y < h; y++) {
      if (inkPerRow[y] <= 0) continue;
      if (firstInk < 0) firstInk = y;
      lastInk = y;
    }
    if (firstInk < 0 || lastInk - firstInk < 8) return null;

    // The threshold comes from the page's OWN ink. Riwayah, page colour,
    // type size and raster width all move the absolute counts around;
    // the ratio between a line and the space beside it is what stays
    // put, and the median row of a page of set text sits squarely on a
    // line.
    final ranked = inkPerRow.sublist(firstInk, lastInk + 1)..sort();
    final median = ranked[ranked.length ~/ 2];
    final threshold = math.max(1, (median * gapInkFraction).round());

    final runs = <List<int>>[];
    var start = -1;
    for (var y = firstInk; y <= lastInk; y++) {
      final between = inkPerRow[y] <= threshold;
      if (between && start < 0) start = y;
      if (!between && start >= 0) {
        runs.add([start, y]);
        start = -1;
      }
    }
    if (start >= 0) runs.add([start, lastInk + 1]);

    // Drop the slivers. The pinch between a word's body and the marks
    // riding above it also dips under the threshold, and it is NOT line
    // spacing — while [build] hands the most height to the shortest
    // gaps, so leaving one in is precisely what would prise a single
    // line apart. Measured against the page's own gaps rather than a
    // fixed number of rows, because the raster width is not fixed.
    final lengths = [for (final r in runs) r[1] - r[0]]..sort();
    if (lengths.isEmpty) return null;
    final typical = lengths[lengths.length ~/ 2];
    final floor = math.max(2, (typical * 0.45).round());

    final out = <double>[];
    for (final r in runs) {
      if (r[1] - r[0] < floor) continue;
      out
        ..add(r[0] / h)
        ..add(r[1] / h);
    }
    // A page of lines has a gap between most of them; far fewer than
    // that means this is not a page of set text and is better left be.
    if (out.length < 12) return null;
    return out;
  }
}

/// The page artwork, rasterised once and redrawn under a stretch.
class MushafSpreadArtwork extends StatefulWidget {
  /// The page's SVG, already tinted by the caller.
  final String svg;

  /// Identifies the artwork for the raster cache — "edition:page".
  final String cacheKey;

  /// The stretch to draw under, or null to draw the page as it is.
  final MushafPageStretch? stretch;

  /// Rendered size of the page BEFORE stretching, in logical pixels.
  final double width;
  final double naturalHeight;

  /// Rendered pixels per viewBox unit.
  final double scale;

  /// viewBox origin and width, for mapping into the raster.
  final double minX;
  final double minY;
  final double viewBoxWidth;

  /// Shown while the page is being rasterised.
  final Color background;

  /// Reports the page's line gaps once the raster has been measured.
  /// The caller turns them into a stretch on a later build — until then
  /// the page is drawn whole, never torn.
  final void Function(List<double> gapRuns)? onMeasured;

  const MushafSpreadArtwork({
    super.key,
    required this.svg,
    required this.cacheKey,
    required this.width,
    required this.naturalHeight,
    required this.scale,
    required this.viewBoxWidth,
    required this.background,
    this.stretch,
    this.minX = 0,
    this.minY = 0,
    this.onMeasured,
  });

  @override
  State<MushafSpreadArtwork> createState() => _MushafSpreadArtworkState();

  /// Frees every cached raster — called when the reader switches edition,
  /// where none of the cached pages can be shown again.
  static void evictAll() => _MushafSpreadArtworkState._evictAll();
}

class _MushafSpreadArtworkState extends State<MushafSpreadArtwork> {
  // Rasters are keyed by page AND by the width they were drawn at, and
  // held across page turns: flipping back a page is the commonest thing
  // a reader does, and re-rasterising a 600 KB path each time would show.
  static final Map<String, ui.Image> _rasters = {};
  static final Map<String, Future<void>> _inFlight = {};
  static const int _maxRasters = 5;

  /// Line gaps per raster key. Kept after the image itself is evicted —
  /// it is a handful of doubles, and losing it would make the page
  /// visibly re-settle every time the reader came back to it.
  static final Map<String, List<double>> _runs = {};
  static final Set<String> _measured = <String>{};

  ui.Image? _image;
  String? _wantedKey;
  String? _reportedKey;

  static void _evictAll() {
    for (final image in _rasters.values) {
      image.dispose();
    }
    _rasters.clear();
  }

  /// Raster width in device pixels. Capped: past the phone's own pixel
  /// width a bigger raster costs memory and buys nothing.
  double _rasterWidth() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final target = (widget.width * dpr).clamp(600.0, 1080.0);
    // Bucketed so a one-pixel layout change doesn't invalidate the cache.
    return (target / 60).round() * 60.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureRaster();
  }

  @override
  void didUpdateWidget(MushafSpreadArtwork old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey || old.width != widget.width) {
      _ensureRaster();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  /// Hands the measured blank runs to the caller, once, after the frame
  /// that is already building.
  void _report(String key) {
    final runs = _runs[key];
    final report = widget.onMeasured;
    if (runs == null || report == null || _reportedKey == key) return;
    _reportedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) report(runs);
    });
  }

  /// Takes this widget's own handle on the cached raster.
  ///
  /// A CLONE, not the cache's own image: eviction disposes the cached
  /// handle, and a page still on screen must not have the image pulled
  /// out from under it mid-paint. Clones share one buffer, so this costs
  /// nothing but keeps it alive until the last holder lets go.
  void _adopt(ui.Image? master) {
    final next = master?.clone();
    _image?.dispose();
    _image = next;
  }

  void _ensureRaster() {
    final rw = _rasterWidth();
    final key = '${widget.cacheKey}@${rw.toInt()}';
    if (_wantedKey == key && _image != null) return;
    _wantedKey = key;

    final cached = _rasters[key];
    if (cached != null) {
      // Refresh recency: insertion order is the eviction order.
      _rasters
        ..remove(key)
        ..[key] = cached;
      _adopt(cached);
      _report(key);
      return;
    }

    _adopt(null);
    void settle() {
      if (!mounted || _wantedKey != key) return;
      setState(() => _adopt(_rasters[key]));
      _report(key);
    }

    final pending = _inFlight[key];
    if (pending != null) {
      pending.whenComplete(settle);
      return;
    }

    final future = _rasterise(key, rw);
    _inFlight[key] = future;
    future.whenComplete(() {
      _inFlight.remove(key);
      settle();
    });
  }

  Future<void> _rasterise(String key, double rasterWidth) async {
    final aspect = widget.naturalHeight / widget.width;
    final w = rasterWidth.round();
    final h = (rasterWidth * aspect).round();
    if (w <= 0 || h <= 0) return;

    ui.Image? image;
    try {
      final info = await vg.loadPicture(SvgStringLoader(widget.svg), null);
      try {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final s = w / widget.viewBoxWidth;
        canvas.scale(s);
        canvas.translate(-widget.minX, -widget.minY);
        canvas.drawPicture(info.picture);
        final picture = recorder.endRecording();
        try {
          image = await picture.toImage(w, h);
        } finally {
          picture.dispose();
        }
      } finally {
        info.picture.dispose();
      }
    } catch (_) {
      // A page that will not rasterise stays blank here; the caller
      // keeps its own unstretched fallback for that case.
      return;
    }

    // Cached even if THIS widget has gone: the page it rasterised is
    // most likely the one being turned to, and another page's widget may
    // already be waiting on this very future.
    _rasters[key] = image;
    while (_rasters.length > _maxRasters) {
      final oldest = _rasters.keys.first;
      if (oldest == key) break;
      _rasters.remove(oldest)?.dispose();
    }

    if (_measured.add(key)) {
      final runs = await _gapRuns(image, w, h);
      if (runs != null) _runs[key] = runs;
    }
  }

  /// How much ink each row of the page carries.
  ///
  /// The page is drawn on TRANSPARENT ground, so "carries ink" is simply
  /// "is not clear". Every few columns is sampled and the inked ones
  /// COUNTED, rather than stopping at the first: where the lines end and
  /// the space between them begins is a question about how much of a row
  /// is covered, and a row that merely has something on it says nothing
  /// — on this script almost every row does.
  static Future<List<double>?> _gapRuns(ui.Image image, int w, int h) async {
    ByteData? bytes;
    try {
      bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } catch (_) {
      return null;
    }
    if (bytes == null) return null;

    const step = 3; // columns
    const alphaFloor = 40;
    final data = bytes.buffer.asUint8List();
    final ink = List<int>.filled(h, 0);
    for (var y = 0; y < h; y++) {
      final row = y * w * 4;
      var inked = 0;
      for (var x = 0; x < w; x += step) {
        if (data[row + x * 4 + 3] > alphaFloor) inked++;
      }
      ink[y] = inked;
    }
    return MushafPageStretch.gapRunsOf(ink);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return ColoredBox(color: widget.background);
    return CustomPaint(
      painter: _StretchPainter(
        image: image,
        stretch: widget.stretch,
        scale: widget.scale,
        minY: widget.minY,
        pixelsPerUnit: image.width / widget.viewBoxWidth,
      ),
    );
  }
}

/// Redraws the rasterised page under the stretch, one strip per segment.
///
/// Segment edges are shared exactly between neighbours, so the strips
/// tile the page with no seam and no gap — and because the stretched
/// segments are the blank ones, any hairline that did fall on an edge
/// would land on empty paper.
class _StretchPainter extends CustomPainter {
  final ui.Image image;
  final MushafPageStretch? stretch;
  final double scale;
  final double minY;

  /// Raster pixels per viewBox unit — the strips are cut in the image's
  /// own resolution, which is not the on-screen one.
  final double pixelsPerUnit;

  const _StretchPainter({
    required this.image,
    required this.scale,
    required this.minY,
    required this.pixelsPerUnit,
    this.stretch,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    final imageWidth = image.width.toDouble();
    final s = stretch;

    if (s == null) {
      canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, imageWidth, image.height.toDouble()),
          Rect.fromLTWH(0, 0, size.width, size.height),
          paint);
      return;
    }

    for (var i = 0; i < s.segmentCount; i++) {
      final srcTop = (s.src[i] - minY) * pixelsPerUnit;
      final srcBottom = (s.src[i + 1] - minY) * pixelsPerUnit;
      if (srcBottom <= srcTop) continue;
      final dstTop = (s.dst[i] - minY) * scale;
      final dstBottom = (s.dst[i + 1] - minY) * scale;

      canvas.drawImageRect(
          image,
          Rect.fromLTRB(0, srcTop, imageWidth, srcBottom),
          Rect.fromLTRB(0, dstTop, size.width, dstBottom),
          paint);
    }
  }

  @override
  bool shouldRepaint(_StretchPainter old) =>
      !identical(old.image, image) ||
      old.scale != scale ||
      old.minY != minY ||
      old.pixelsPerUnit != pixelsPerUnit ||
      old.stretch?.extraHeight != stretch?.extraHeight ||
      old.stretch?.segmentCount != stretch?.segmentCount;
}
