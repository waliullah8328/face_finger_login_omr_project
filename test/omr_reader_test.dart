import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omr_project/omr/omr_layout.dart';
import 'package:omr_project/omr/omr_reader.dart';

import 'fake_photo.dart';

/// Renders a flat sheet like the printed one (scale px per sheet unit).
img.Image renderSheet({
  required Map<int, List<int>> marks,
  String roll = '',
  int? set,
  double scale = 2,
}) {
  final w = (OmrLayout.width * scale).round();
  final h = (OmrLayout.height * scale).round();
  final sheet = img.Image(width: w, height: h, numChannels: 3)
    ..clear(img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(20, 20, 20);
  final outline = img.ColorRgb8(90, 90, 90);
  final label = img.ColorRgb8(190, 190, 190);
  final ink = img.ColorRgb8(35, 35, 60);

  void square(Pt c, double size) => img.fillRect(sheet,
      x1: ((c.x - size / 2) * scale).round(),
      y1: ((c.y - size / 2) * scale).round(),
      x2: ((c.x + size / 2) * scale).round(),
      y2: ((c.y + size / 2) * scale).round(),
      color: black);

  void bubble(Pt c, double r, bool filled) {
    final x = (c.x * scale).round(), y = (c.y * scale).round();
    final rad = (r * scale).round();
    img.drawCircle(sheet, x: x, y: y, radius: rad, color: outline);
    // Stand-in for the light option letter printed inside each bubble.
    img.fillRect(sheet,
        x1: x - 3, y1: y - 5, x2: x + 3, y2: y + 5, color: label);
    if (filled) {
      img.fillCircle(sheet, x: x, y: y, radius: rad - 1, color: ink);
    }
  }

  for (final m in OmrLayout.markers) {
    square(m, OmrLayout.markerSize);
  }
  square(OmrLayout.orientationSpot, OmrLayout.orientationSpotSize);
  for (var q = 0; q < OmrLayout.maxQuestions; q++) {
    for (var o = 0; o < OmrLayout.optionCount; o++) {
      bubble(OmrLayout.answerBubble(q, o), OmrLayout.answerRadius,
          marks[q]?.contains(o) ?? false);
    }
  }
  for (var c = 0; c < OmrLayout.rollDigits; c++) {
    for (var d = 0; d < 10; d++) {
      final want = c < roll.length && roll[c] == '$d';
      bubble(OmrLayout.rollBubble(c, d), OmrLayout.headerRadius, want);
    }
  }
  for (var o = 0; o < OmrLayout.optionCount; o++) {
    bubble(OmrLayout.setBubble(o), OmrLayout.headerRadius, set == o);
  }
  return sheet;
}

void main() {
  final marks = {
    0: [0],
    1: [1],
    2: [2],
    3: [3],
    10: [1],
    24: [2], // last row of first column
    25: [0], // first row of second column
    50: [3],
    77: [1, 2], // double mark
    99: [0],
  };

  void expectSheet(OmrScanResult r) {
    for (var q = 0; q < OmrLayout.maxQuestions; q++) {
      final want = marks[q];
      final expected = want == null
          ? null
          : want.length > 1
              ? multipleMarks
              : want.single;
      expect(r.answers[q], expected,
          reason: 'question ${q + 1}, fills ${r.fills[q]}');
    }
    expect(r.roll, '420917');
    expect(r.setCode, 2);
  }

  final sheet = renderSheet(marks: marks, roll: '420917', set: 2);

  test('reads a straight photo', () {
    final photo = photograph(sheet, const [
      math.Point(100, 120),
      math.Point(1400, 120),
      math.Point(1400, 1960),
      math.Point(100, 1960),
    ]);
    expectSheet(readOmrSheet(photo));
  });

  test('reads a tilted, perspective-skewed photo', () {
    final photo = photograph(sheet, const [
      math.Point(180, 90),
      math.Point(1380, 210),
      math.Point(1440, 1900),
      math.Point(60, 1950),
    ], seed: 2);
    expectSheet(readOmrSheet(photo));
  });

  test('reads an upside-down photo', () {
    final photo = photograph(sheet, const [
      math.Point(1400, 1950),
      math.Point(110, 1930),
      math.Point(130, 100),
      math.Point(1380, 90),
    ], seed: 3);
    expectSheet(readOmrSheet(photo));
  });

  test('reads a sideways (landscape) photo', () {
    final photo = photograph(sheet, const [
      math.Point(1900, 90),
      math.Point(1920, 1400),
      math.Point(90, 1420),
      math.Point(70, 110),
    ], width: 2000, height: 1500, seed: 4);
    expectSheet(readOmrSheet(photo));
  });

  test('reads only the requested number of questions', () {
    final photo = photograph(sheet, const [
      math.Point(100, 120),
      math.Point(1400, 120),
      math.Point(1400, 1960),
      math.Point(100, 1960),
    ]);
    final r = readOmrSheet(photo, questionCount: 30);
    expect(r.answers.length, 30);
    expect(r.answers[25], 0);
  });

  test('rejects a photo without the sheet', () {
    final blank = img.Image(width: 800, height: 1000, numChannels: 3)
      ..clear(img.ColorRgb8(240, 240, 240));
    expect(() => readOmrSheet(img.encodeJpg(blank)),
        throwsA(isA<OmrException>()));
  });
}
