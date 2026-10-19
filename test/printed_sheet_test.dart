import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omr_project/omr/omr_layout.dart';
import 'package:omr_project/omr/omr_reader.dart';
import 'package:omr_project/omr/sheet_painter.dart';

import 'fake_photo.dart';

/// End to end: the sheet exactly as the app prints it (real labels, bands,
/// instructions), filled with a pen, photographed, then read back.
void main() {
  // The test font draws every glyph as a solid box, which would look like ink
  // inside the bubbles; use a real Bangla font when the machine has one.
  const bengaliFont = r'C:\Windows\Fonts\Nirmala.ttc';

  testWidgets('reads the printed sheet after it is filled in', (tester) async {
    final png = await tester.runAsync(() async {
      String? family;
      if (File(bengaliFont).existsSync()) {
        final loader = FontLoader('OmrTestBangla')
          ..addFont(File(bengaliFont)
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)));
        await loader.load();
        family = 'OmrTestBangla';
      }
      return renderSheetPng(pixelWidth: 2000, fontFamily: family);
    });
    final sheet = img.decodePng(png!)!;
    Directory('build').createSync();
    File('build/omr_sheet_preview.png').writeAsBytesSync(png);

    final scale = sheet.width / OmrLayout.width;
    final pen = img.ColorRgb8(30, 30, 70);
    final rnd = math.Random(7);
    void fill(Pt c, double r) {
      // Hand filling is never perfect: slightly off-centre and undersized.
      img.fillCircle(sheet,
          x: ((c.x + rnd.nextDouble() * 2 - 1) * scale).round(),
          y: ((c.y + rnd.nextDouble() * 2 - 1) * scale).round(),
          radius: (r * 0.85 * scale).round(),
          color: pen);
    }

    final expected = <int?>[
      for (var q = 0; q < OmrLayout.maxQuestions; q++)
        q % 7 == 3 ? null : (q * 3 + 1) % OmrLayout.optionCount,
    ];
    for (var q = 0; q < expected.length; q++) {
      if (expected[q] != null) {
        fill(OmrLayout.answerBubble(q, expected[q]!), OmrLayout.answerRadius);
      }
    }
    const roll = '305128';
    for (var c = 0; c < roll.length; c++) {
      fill(OmrLayout.rollBubble(c, int.parse(roll[c])), OmrLayout.headerRadius);
    }
    fill(OmrLayout.setBubble(1), OmrLayout.headerRadius);

    final photo = photograph(sheet, const [
      math.Point(150, 110),
      math.Point(1390, 160),
      math.Point(1430, 1930),
      math.Point(90, 1900),
    ], seed: 9);
    // Handy sample for trying the app on an emulator.
    File('build/omr_sample_filled.jpg').writeAsBytesSync(photo);
    final result = readOmrSheet(photo);
    File('build/omr_scan_preview.jpg').writeAsBytesSync(result.annotatedImage);

    for (var q = 0; q < expected.length; q++) {
      expect(result.answers[q], expected[q],
          reason: 'question ${q + 1}, fills ${result.fills[q]}');
    }
    expect(result.roll, roll);
    expect(result.setCode, 1);
  });
}
