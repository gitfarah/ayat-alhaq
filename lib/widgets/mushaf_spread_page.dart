import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/mushaf_svg_service.dart';

/// Draws a Mushaf page with its printed lines pulled apart so the page
/// fills the screen's height.
///
/// A Mushaf leaf is proportionally much wider than a phone, so fitting
/// its width always leaves vertical slack — dead space under the last
/// line. Rather than waste it, that slack is divided evenly between the
/// lines, which is the one change that makes the small print of a
/// 604-page Mushaf comfortable on a phone.
///
/// The page artwork is a single enormous vector path (every glyph on the
/// page in one `<path>`), so the lines cannot be moved in the SVG and
/// re-drawing the path once per line would be far too slow. Instead the
/// page is rasterised ONCE and then blitted line by line: fifteen
/// `drawImageRect` calls, each moving one horizontal strip down by a
/// little more than the last.

/// Where each printed line sits on a page, and how far it moves.
///
/// The line positions are not guesswork: the ayah tap-regions that ship
/// with every page are written one rectangle per LINE, and they tile the
/// page exactly — so their shared edges ARE the line boundaries.
class MushafLineBands {
  /// Ascending y boundaries in viewBox units, page top first and page
  /// bottom last. Band k is `[boundaries[k], boundaries[k + 1]]`.
  final List<double> boundaries;

  /// Extra space, in viewBox units, inserted before every band but the
  /// first — so band k moves down by `k * gap`.
  final double gap;

  const MushafLineBands(this.boundaries, this.gap);

  int get bandCount => boundaries.length - 1;

  /// Total height the spread adds, in viewBox units.
  double get extraHeight => gap * (bandCount - 1);

  MushafLineBands withGap(double g) => MushafLineBands(boundaries, g);

  /// How far the band containing [y] has moved down.
  double offsetFor(double y) {
    for (var k = bandCount - 1; k >= 0; k--) {
      if (y >= boundaries[k]) return k * gap;
    }
    return 0;
  }

  /// Spread coordinates → original page coordinates, for hit-testing a
  /// tap. A tap landing in the whitespace between two lines is read as
  /// the line below it, which is where the ayah polygons continue.
  double unmap(double spreadY) {
    for (var k = bandCount - 1; k >= 0; k--) {
      if (spreadY >= boundaries[k] + k * gap) return spreadY - k * gap;
    }
    return spreadY;
  }

  /// Measures the line boundaries of [data], or null if the page's
  /// regions don't describe a plausible page of lines — in which case
  /// the caller should draw the page unspread rather than guess.
  static MushafLineBands? measure(MushafPageData data) {
    final edges = <double>[];
    for (final region in data.ayahRegions) {
      if (region.ayahNumber <= 0 || region.surahNumber <= 0) continue;
      for (final ring in region.rings) {
        var top = double.infinity;
        var bottom = double.negativeInfinity;
        for (var i = 1; i < ring.length; i += 2) {
          top = math.min(top, ring[i]);
          bottom = math.max(bottom, ring[i]);
        }
        // A sliver is a rounding artefact, not a line of script.
        if (bottom - top < 4) continue;
        edges
          ..add(top)
          ..add(bottom);
      }
    }
    if (edges.length < 8) return null;
    edges.sort();

    // The same boundary is written with slightly different rounding by
    // each ayah that touches it (117.77 against 117.81), so near-equal
    // edges collapse to one.
    final bounds = <double>[];
    for (final y in edges) {
      if (bounds.isEmpty || y - bounds.last > 2.0) bounds.add(y);
    }

    // Extend to the page edges so the head (a surah band, a basmala) and
    // the foot margin travel with the text instead of being left behind.
    final pageTop = data.viewBoxMinY;
    final pageBottom = data.viewBoxMinY + data.viewBoxHeight;
    if (bounds.first - pageTop > 1) bounds.insert(0, pageTop);
    if (pageBottom - bounds.last > 1) bounds.add(pageBottom);

    // A Mushaf page is fifteen lines; allow for pages that open or close
    // a surah, and bail out on anything that isn't a page of lines.
    final count = bounds.length - 1;
    if (count < 6 || count > 30) return null;
    return MushafLineBands(bounds, 0);
  }
}

/// The page artwork, rasterised once and blitted strip by strip.
class MushafSpreadArtwork extends StatefulWidget {
  /// The page's SVG, already tinted by the caller.
  final String svg;

  /// Identifies the artwork for the raster cache — "edition:page".
  final String cacheKey;

  final MushafLineBands bands;

  /// Rendered size of the page BEFORE spreading, in logical pixels.
  final double width;
  final double naturalHeight;

  /// Rendered pixels per viewBox unit.
  final double scale;

  /// viewBox origin, subtracted before scaling.
  final double minX;
  final double minY;
  final double viewBoxWidth;

  /// Shown while the page is being rasterised.
  final Color background;

  const MushafSpreadArtwork({
    super.key,
    required this.svg,
    required this.cacheKey,
    required this.bands,
    required this.width,
    required this.naturalHeight,
    required this.scale,
    required this.viewBoxWidth,
    required this.background,
    this.minX = 0,
    this.minY = 0,
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

  ui.Image? _image;
  String? _wantedKey;

  static void _evictAll() {
    for (final image in _rasters.values) {
      image.dispose();
    }
    _rasters.clear();
  }

  /// Raster width in device pixels. Capped: past the phone's own pixel
  /// width a bigger raster costs memory and buys nothing, and a page at
  /// 1080 px already carries more detail than the screen can show.
  double _rasterWidth() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final target = (widget.width * dpr).clamp(600.0, 1080.0);
    // Bucketed so a one-pixel layout change doesn't invalidate the cache.
    return (target / 60).round() * 60.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureRaster(notify: false);
  }

  @override
  void didUpdateWidget(MushafSpreadArtwork old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey || old.width != widget.width) {
      _ensureRaster(notify: false);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
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

  void _ensureRaster({bool notify = true}) {
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
      // Both synchronous callers are followed by a build of their own,
      // so there is nothing to notify — and setState is not allowed
      // from didChangeDependencies.
      if (notify) setState(() {});
      return;
    }

    _adopt(null);
    void settle() {
      if (!mounted || _wantedKey != key) return;
      setState(() => _adopt(_rasters[key]));
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
      // A page that will not rasterise simply stays blank here; the
      // caller keeps its own unspread fallback for that case.
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
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return ColoredBox(color: widget.background);
    return CustomPaint(
      painter: _SpreadPainter(
        image: image,
        bands: widget.bands,
        scale: widget.scale,
        minY: widget.minY,
        pixelsPerUnit: image.width / widget.viewBoxWidth,
      ),
    );
  }
}

/// Blits one horizontal strip of the rasterised page per printed line,
/// each shifted a little further down than the one above it.
class _SpreadPainter extends CustomPainter {
  final ui.Image image;
  final MushafLineBands bands;
  final double scale;
  final double minY;

  /// Raster pixels per viewBox unit — the strips are cut in the image's
  /// own resolution, which is not the on-screen one.
  final double pixelsPerUnit;

  const _SpreadPainter({
    required this.image,
    required this.bands,
    required this.scale,
    required this.minY,
    required this.pixelsPerUnit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    final imageWidth = image.width.toDouble();

    for (var k = 0; k < bands.bandCount; k++) {
      final top = bands.boundaries[k] - minY;
      final bottom = bands.boundaries[k + 1] - minY;
      final shift = k * bands.gap * scale;

      final src = Rect.fromLTRB(
          0, top * pixelsPerUnit, imageWidth, bottom * pixelsPerUnit);
      final dst = Rect.fromLTRB(
          0, top * scale + shift, size.width, bottom * scale + shift);
      canvas.drawImageRect(image, src, dst, paint);
    }
  }

  @override
  bool shouldRepaint(_SpreadPainter old) =>
      !identical(old.image, image) ||
      old.scale != scale ||
      old.minY != minY ||
      old.pixelsPerUnit != pixelsPerUnit ||
      old.bands.gap != bands.gap ||
      old.bands.bandCount != bands.bandCount;
}
