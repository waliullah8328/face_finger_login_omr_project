import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'omr_layout.dart';

/// Value stored in [OmrScanResult.answers] when more than one bubble of a
/// question is filled.
const int multipleMarks = -1;

class OmrException implements Exception {
  final String message;

  const OmrException(this.message);

  @override
  String toString() => message;
}

class OmrScanResult {
  /// Per question: selected option index, `null` if blank, or [multipleMarks].
  final List<int?> answers;

  /// Per question, per option: fraction (0-1) of the bubble that is dark.
  final List<List<double>> fills;

  /// Questions whose decision was close to the threshold; worth a manual look.
  final List<bool> uncertain;

  /// Roll number; `?` marks a digit column that was blank or double-filled.
  final String roll;

  /// Set code option index, or `null` if not readable.
  final int? setCode;

  /// Fill fraction above which a bubble counts as filled for this sheet.
  final double threshold;

  /// The (downscaled) photo with detection overlaid, JPEG encoded.
  final Uint8List annotatedImage;

  const OmrScanResult({
    required this.answers,
    required this.fills,
    required this.uncertain,
    required this.roll,
    required this.setCode,
    required this.threshold,
    required this.annotatedImage,
  });
}

// Photos are downscaled to this longest side before processing; plenty for
// bubbles that are ~5mm across, and keeps a scan well under a second.
const int _workingSize = 1600;

// Only the central part of a bubble is sampled so the printed outline and
// small misalignments do not count as ink.
const double _sampleRadiusFactor = 0.6;

/// Reads a photo of a Biddabari OMR sheet (see [OmrLayout]).
///
/// Pure Dart and synchronous: call it through `Isolate.run`/`compute` from UI
/// code. Throws [OmrException] with a user-facing message on failure.
OmrScanResult readOmrSheet(
  Uint8List bytes, {
  int questionCount = OmrLayout.maxQuestions,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const OmrException('ছবিটি খোলা যায়নি। অন্য ছবি দিয়ে চেষ্টা করুন।');
  }
  var image = img.bakeOrientation(decoded);
  if (math.max(image.width, image.height) > _workingSize) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _workingSize)
        : img.copyResize(image, height: _workingSize);
  }
  if (image.hasPalette || image.numChannels < 3) {
    image = image.convert(format: img.Format.uint8, numChannels: 3);
  }

  final w = image.width;
  final h = image.height;
  final gray = Uint8List(w * h);
  for (final p in image) {
    gray[p.y * w + p.x] = (p.luminanceNormalized * 255).round();
  }
  final dark = _adaptiveThreshold(gray, w, h);

  final corners = _findMarkerCorners(dark, w, h);
  final homography = _orientedHomography(corners, dark, w, h);

  double fillOf(Pt center, double radius) =>
      _fillAt(dark, w, h, homography, center, radius);

  questionCount = questionCount.clamp(1, OmrLayout.maxQuestions);
  final fills = [
    for (var q = 0; q < questionCount; q++)
      [
        for (var o = 0; o < OmrLayout.optionCount; o++)
          fillOf(OmrLayout.answerBubble(q, o), OmrLayout.answerRadius),
      ],
  ];
  final rollFills = [
    for (var c = 0; c < OmrLayout.rollDigits; c++)
      [
        for (var d = 0; d < 10; d++)
          fillOf(OmrLayout.rollBubble(c, d), OmrLayout.headerRadius),
      ],
  ];
  final setFills = [
    for (var o = 0; o < OmrLayout.optionCount; o++)
      fillOf(OmrLayout.setBubble(o), OmrLayout.headerRadius),
  ];

  final threshold = _pickThreshold([
    for (final row in fills) ...row,
    for (final row in rollFills) ...row,
    ...setFills,
  ]);

  final answers = <int?>[];
  final uncertain = <bool>[];
  for (final row in fills) {
    answers.add(_decide(row, threshold));
    uncertain.add(_isUncertain(row, threshold));
  }

  final roll = StringBuffer();
  for (final column in rollFills) {
    final digit = _decide(column, threshold);
    roll.write(digit == null || digit == multipleMarks ? '?' : '$digit');
  }
  final set = _decide(setFills, threshold);

  _annotate(image, homography, corners, fills, answers, uncertain, threshold);

  return OmrScanResult(
    answers: answers,
    fills: fills,
    uncertain: uncertain,
    roll: roll.toString(),
    setCode: set == multipleMarks ? null : set,
    threshold: threshold,
    annotatedImage: img.encodeJpg(image, quality: 85),
  );
}

// ---------------------------------------------------------------------------
// Binarisation

/// Bradley-Roth adaptive threshold: a pixel is "ink" when it is clearly darker
/// than its neighbourhood. Handles shadows and uneven lighting in photos.
/// Returns 1 for ink, 0 for paper.
Uint8List _adaptiveThreshold(Uint8List gray, int w, int h) {
  final stride = w + 1;
  final integral = Uint32List(stride * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    for (var x = 0; x < w; x++) {
      rowSum += gray[y * w + x];
      integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + rowSum;
    }
  }

  final half = math.max(8, w ~/ 16);
  const sensitivity = 15; // percent darker than the local mean
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y1 = math.max(0, y - half);
    final y2 = math.min(h - 1, y + half);
    for (var x = 0; x < w; x++) {
      final x1 = math.max(0, x - half);
      final x2 = math.min(w - 1, x + half);
      final count = (x2 - x1 + 1) * (y2 - y1 + 1);
      final sum = integral[(y2 + 1) * stride + x2 + 1] -
          integral[y1 * stride + x2 + 1] -
          integral[(y2 + 1) * stride + x1] +
          integral[y1 * stride + x1];
      if (gray[y * w + x] * count * 100 < sum * (100 - sensitivity)) {
        out[y * w + x] = 1;
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Corner markers

class _Blob {
  int area = 0;
  int minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  double sumX = 0, sumY = 0;
  bool touchesBorder = false;

  int get boxWidth => maxX - minX + 1;
  int get boxHeight => maxY - minY + 1;
  Pt get center => Pt(sumX / area, sumY / area);
}

List<_Blob> _findBlobs(Uint8List dark, int w, int h, int minArea) {
  final visited = Uint8List(w * h);
  final stack = Int32List(w * h);
  final blobs = <_Blob>[];
  for (var start = 0; start < w * h; start++) {
    if (dark[start] == 0 || visited[start] == 1) continue;
    final blob = _Blob();
    var top = 0;
    stack[top++] = start;
    visited[start] = 1;
    while (top > 0) {
      final i = stack[--top];
      final x = i % w;
      final y = i ~/ w;
      blob
        ..area += 1
        ..sumX += x
        ..sumY += y;
      if (x < blob.minX) blob.minX = x;
      if (x > blob.maxX) blob.maxX = x;
      if (y < blob.minY) blob.minY = y;
      if (y > blob.maxY) blob.maxY = y;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) {
        blob.touchesBorder = true;
        continue;
      }
      for (final n in [i - 1, i + 1, i - w, i + w]) {
        if (dark[n] == 1 && visited[n] == 0) {
          visited[n] = 1;
          stack[top++] = n;
        }
      }
    }
    if (blob.area >= minArea) blobs.add(blob);
  }
  return blobs;
}

/// Finds the four corner squares and returns their centres in clockwise
/// image order, starting with the one nearest the image's top-left.
List<Pt> _findMarkerCorners(Uint8List dark, int w, int h) {
  final minSide = math.min(w, h);
  final minMarker = minSide * 0.012;
  final maxMarker = minSide * 0.15;

  final candidates = _findBlobs(dark, w, h, (minMarker * minMarker).round())
      .where((b) {
        if (b.touchesBorder) return false;
        final aspect = b.boxWidth / b.boxHeight;
        if (aspect < 0.5 || aspect > 2) return false;
        // Solid shapes only: a square (even rotated) covers >= 50% of its box.
        if (b.area / (b.boxWidth * b.boxHeight) < 0.5) return false;
        final side = math.sqrt(b.area);
        return side >= minMarker && side <= maxMarker;
      })
      .toList()
    ..sort((a, b) => b.area.compareTo(a.area));

  const notFound = OmrException(
    'শিটের চার কোণার কালো চিহ্ন পাওয়া যায়নি। পুরো শিটটি ফ্রেমের ভেতরে রেখে, '
    'সমতল জায়গায় ভালো আলোতে ছবি তুলুন।',
  );
  if (candidates.length < 4) throw notFound;

  // Among the largest solid blobs, the markers are four of similar size that
  // span the biggest quadrilateral.
  final pool = candidates.take(8).toList();
  List<Pt>? best;
  var bestArea = 0.0;
  for (var a = 0; a < pool.length; a++) {
    for (var b = a + 1; b < pool.length; b++) {
      for (var c = b + 1; c < pool.length; c++) {
        for (var d = c + 1; d < pool.length; d++) {
          final group = [pool[a], pool[b], pool[c], pool[d]];
          final areas = group.map((g) => g.area);
          if (areas.reduce(math.max) > areas.reduce(math.min) * 2.5) continue;
          final quad = _clockwise(group.map((g) => g.center).toList());
          final area = _polygonArea(quad);
          if (area > bestArea) {
            bestArea = area;
            best = quad;
          }
        }
      }
    }
  }
  // The sheet should fill a decent part of the photo.
  if (best == null || bestArea < w * h * 0.12) throw notFound;
  return best;
}

List<Pt> _clockwise(List<Pt> points) {
  final cx = points.fold(0.0, (s, p) => s + p.x) / points.length;
  final cy = points.fold(0.0, (s, p) => s + p.y) / points.length;
  // Image y grows downward, so increasing atan2 is clockwise on screen.
  // Starting from -pi puts the top-left-most point first.
  return [...points]..sort((a, b) => math
      .atan2(a.y - cy, a.x - cx)
      .compareTo(math.atan2(b.y - cy, b.x - cx)));
}

double _polygonArea(List<Pt> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    s += p[i].x * p[j].y - p[j].x * p[i].y;
  }
  return s.abs() / 2;
}

/// Tries the four ways the sheet could be rotated in the photo and keeps the
/// one where the orientation spot is found next to the top-left marker.
_Homography _orientedHomography(List<Pt> corners, Uint8List dark, int w, int h) {
  _Homography? best;
  var bestFill = -1.0;
  for (var r = 0; r < 4; r++) {
    final image = [for (var i = 0; i < 4; i++) corners[(i + r) % 4]];
    final hom = _Homography.solve(OmrLayout.markers, image);
    if (hom == null) continue;
    final fill = _fillAt(dark, w, h, hom, OmrLayout.orientationSpot,
        OmrLayout.orientationSpotSize / 2);
    if (fill > bestFill) {
      bestFill = fill;
      best = hom;
    }
  }
  if (best == null || bestFill < 0.5) {
    throw const OmrException(
      'শিটের দিক (উপর/নিচ) বোঝা যায়নি। এটি কি বিদ্যাবাড়ির OMR শিট? '
      'শিটটি সমান রেখে আবার ছবি তুলুন।',
    );
  }
  return best;
}

// ---------------------------------------------------------------------------
// Perspective mapping

/// Projective transform from sheet units to image pixels.
class _Homography {
  final List<double> m; // 3x3 row-major, m[8] == 1

  _Homography(this.m);

  Pt map(Pt p) {
    final z = m[6] * p.x + m[7] * p.y + m[8];
    return Pt(
      (m[0] * p.x + m[1] * p.y + m[2]) / z,
      (m[3] * p.x + m[4] * p.y + m[5]) / z,
    );
  }

  static _Homography? solve(List<Pt> from, List<Pt> to) {
    // 8 equations, 8 unknowns; augmented matrix solved by Gauss-Jordan.
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = from[i].x, y = from[i].y;
      final u = to[i].x, v = to[i].y;
      a[2 * i].setAll(0, [x, y, 1, 0, 0, 0, -x * u, -y * u, u]);
      a[2 * i + 1].setAll(0, [0, 0, 0, x, y, 1, -x * v, -y * v, v]);
    }
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-9) return null;
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col] / a[col][col];
        for (var c = col; c < 9; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    return _Homography([for (var r = 0; r < 8; r++) a[r][8] / a[r][r], 1]);
  }
}

// ---------------------------------------------------------------------------
// Bubble sampling and decisions

double _fillAt(
  Uint8List dark,
  int w,
  int h,
  _Homography hom,
  Pt center,
  double radius,
) {
  final c = hom.map(center);
  final rx = hom.map(Pt(center.x + radius, center.y));
  final ry = hom.map(Pt(center.x, center.y + radius));
  final r = (_dist(c, rx) + _dist(c, ry)) / 2 * _sampleRadiusFactor;
  final r2 = r * r;

  var total = 0;
  var ink = 0;
  for (var y = (c.y - r).floor(); y <= (c.y + r).ceil(); y++) {
    if (y < 0 || y >= h) continue;
    for (var x = (c.x - r).floor(); x <= (c.x + r).ceil(); x++) {
      if (x < 0 || x >= w) continue;
      final dx = x - c.x, dy = y - c.y;
      if (dx * dx + dy * dy > r2) continue;
      total++;
      ink += dark[y * w + x];
    }
  }
  return total == 0 ? 0 : ink / total;
}

double _dist(Pt a, Pt b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Otsu's method over all bubble fills of this sheet: separates "empty" from
/// "filled" bubbles, adapting to pen darkness and lighting. Clamped so a sheet
/// with no marks (or all marks) still gets a sensible cut-off.
double _pickThreshold(List<double> fills) {
  const bins = 50;
  final hist = List<int>.filled(bins, 0);
  for (final f in fills) {
    hist[(f * (bins - 1)).round().clamp(0, bins - 1)]++;
  }
  final total = fills.length;
  var sumAll = 0.0;
  for (var i = 0; i < bins; i++) {
    sumAll += i * hist[i];
  }
  var sumBack = 0.0;
  var weightBack = 0;
  var bestVariance = -1.0;
  var bestBin = bins ~/ 2;
  for (var i = 0; i < bins; i++) {
    weightBack += hist[i];
    if (weightBack == 0) continue;
    final weightFore = total - weightBack;
    if (weightFore == 0) break;
    sumBack += i * hist[i];
    final meanBack = sumBack / weightBack;
    final meanFore = (sumAll - sumBack) / weightFore;
    final variance =
        weightBack * weightFore * (meanBack - meanFore) * (meanBack - meanFore);
    if (variance > bestVariance) {
      bestVariance = variance;
      bestBin = i;
    }
  }
  return ((bestBin + 0.5) / (bins - 1)).clamp(0.35, 0.65);
}

int? _decide(List<double> fills, double threshold) {
  int? chosen;
  for (var i = 0; i < fills.length; i++) {
    if (fills[i] < threshold) continue;
    if (chosen != null) return multipleMarks;
    chosen = i;
  }
  return chosen;
}

bool _isUncertain(List<double> fills, double threshold) =>
    fills.any((f) => (f - threshold).abs() < 0.12);

// ---------------------------------------------------------------------------
// Debug overlay

void _annotate(
  img.Image image,
  _Homography hom,
  List<Pt> corners,
  List<List<double>> fills,
  List<int?> answers,
  List<bool> uncertain,
  double threshold,
) {
  final red = img.ColorRgb8(229, 57, 53);
  final green = img.ColorRgb8(46, 160, 67);
  final orange = img.ColorRgb8(245, 124, 0);
  final blue = img.ColorRgb8(100, 140, 230);

  for (final c in corners) {
    img.drawCircle(image,
        x: c.x.round(), y: c.y.round(), radius: 14, color: red);
  }
  for (var q = 0; q < fills.length; q++) {
    for (var o = 0; o < fills[q].length; o++) {
      final center = OmrLayout.answerBubble(q, o);
      final c = hom.map(center);
      final edge =
          hom.map(Pt(center.x + OmrLayout.answerRadius, center.y));
      final r = math.max(3, _dist(c, edge).round());
      final filled = fills[q][o] >= threshold;
      final color = answers[q] == multipleMarks && filled
          ? red
          : filled
              ? green
              : uncertain[q] && (fills[q][o] - threshold).abs() < 0.12
                  ? orange
                  : blue;
      img.drawCircle(image,
          x: c.x.round(), y: c.y.round(), radius: r, color: color);
      if (filled || color == orange) {
        img.drawCircle(image,
            x: c.x.round(), y: c.y.round(), radius: r + 1, color: color);
        img.drawCircle(image,
            x: c.x.round(), y: c.y.round(), radius: r + 2, color: color);
      }
    }
  }
}
