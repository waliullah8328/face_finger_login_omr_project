import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'bangla.dart';
import 'omr_layout.dart';

/// Draws the blank OMR sheet in [OmrLayout] coordinates, scaled to the canvas.
class OmrSheetPainter extends CustomPainter {
  /// Font for all text; `null` uses the platform default (which has Bangla
  /// glyphs on Android/iOS).
  final String? fontFamily;

  const OmrSheetPainter({this.fontFamily});

  static const _ink = Color(0xFF111111);
  static const _outline = Color(0xFF555555);
  static const _faint = Color(0xFFB0B0B0);
  static const _band = Color(0xFFF2F5F9);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / OmrLayout.width, size.height / OmrLayout.height);
    _paintSheet(canvas);
    canvas.restore();
  }

  void _paintSheet(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, OmrLayout.width, OmrLayout.height),
      Paint()..color = Colors.white,
    );
    final solid = Paint()..color = _ink;
    final frame = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final m in OmrLayout.markers) {
      canvas.drawRect(_square(m, OmrLayout.markerSize), solid);
    }
    canvas.drawRect(
      _square(OmrLayout.orientationSpot, OmrLayout.orientationSpotSize),
      solid,
    );

    _text(canvas, 'বিদ্যাবাড়ি OMR উত্তরপত্র', const Offset(500, 46),
        size: 30, weight: FontWeight.bold, align: TextAlign.center);
    _text(canvas, 'Biddabari IT', const Offset(500, 82),
        size: 14, color: _outline, align: TextAlign.center);

    _paintHeader(canvas, frame);
    _paintAnswers(canvas, frame);

    _text(
      canvas,
      'চার কোণার কালো বর্গ ও উপরের ছোট বর্গে কোনো দাগ দেবেন না, শিট ভাঁজ করবেন না।',
      const Offset(500, 1340),
      size: 13,
      color: _outline,
      align: TextAlign.center,
    );
  }

  void _paintHeader(Canvas canvas, Paint frame) {
    // Roll number block.
    canvas.drawRect(const Rect.fromLTRB(80, 110, 292, 455), frame);
    _text(canvas, 'রোল নম্বর', const Offset(186, 128),
        size: 16, weight: FontWeight.bold, align: TextAlign.center);
    for (var c = 0; c < OmrLayout.rollDigits; c++) {
      final x = OmrLayout.rollBubble(c, 0).x;
      canvas.drawRect(Rect.fromLTWH(x - 14, 152, 28, 32), frame);
      for (var d = 0; d < 10; d++) {
        _bubble(canvas, OmrLayout.rollBubble(c, d), OmrLayout.headerRadius,
            toBanglaDigits('$d'));
      }
    }

    // Set code block.
    canvas.drawRect(const Rect.fromLTRB(312, 110, 452, 455), frame);
    _text(canvas, 'সেট কোড', const Offset(382, 128),
        size: 16, weight: FontWeight.bold, align: TextAlign.center);
    canvas.drawRect(
        Rect.fromLTWH(OmrLayout.setX - 14, 152, 28, 32), frame);
    for (var o = 0; o < OmrLayout.optionCount; o++) {
      _bubble(canvas, OmrLayout.setBubble(o), OmrLayout.headerRadius,
          OmrLayout.optionLabels[o]);
    }

    // Candidate information and instructions.
    canvas.drawRect(const Rect.fromLTRB(472, 110, 930, 455), frame);
    final line = Paint()
      ..color = _outline
      ..strokeWidth = 1;
    const fields = ['পরীক্ষার্থীর নাম', 'পরীক্ষার নাম', 'তারিখ', 'স্বাক্ষর'];
    for (var i = 0; i < fields.length; i++) {
      final y = 140.0 + i * 38;
      _text(canvas, '${fields[i]}:', Offset(488, y), size: 15);
      canvas.drawLine(Offset(610, y + 10), Offset(915, y + 10), line);
    }

    _text(canvas, 'নির্দেশনা', const Offset(488, 305),
        size: 15, weight: FontWeight.bold);
    _text(canvas, '• কালো/নীল বলপেন দিয়ে বৃত্ত সম্পূর্ণ ভরাট করুন।',
        const Offset(488, 332), size: 13);
    _text(canvas, '• একটি প্রশ্নে একাধিক বৃত্ত ভরাট করলে উত্তর বাতিল।',
        const Offset(488, 356), size: 13);

    _text(canvas, 'সঠিক:', const Offset(488, 395), size: 14);
    final example = Paint()..color = _ink;
    canvas.drawCircle(const Offset(550, 395), 10, example);
    _text(canvas, 'ভুল:', const Offset(600, 395), size: 14);
    final pen = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Tick, cross and half-filled examples.
    _bubble(canvas, const Pt(660, 395), 10, '');
    canvas.drawPath(
        Path()
          ..moveTo(654, 395)
          ..lineTo(659, 401)
          ..lineTo(667, 388),
        pen);
    _bubble(canvas, const Pt(700, 395), 10, '');
    canvas.drawLine(const Offset(694, 389), const Offset(706, 401), pen);
    canvas.drawLine(const Offset(706, 389), const Offset(694, 401), pen);
    _bubble(canvas, const Pt(740, 395), 10, '');
    canvas.drawArc(Rect.fromCircle(center: const Offset(740, 395), radius: 10),
        -1.57, 3.14, true, example);
    _text(canvas, 'প্রশ্ন সংখ্যা: ১-১০০', const Offset(488, 432),
        size: 13, color: _outline);
  }

  void _paintAnswers(Canvas canvas, Paint frame) {
    const top = 498.0, bottom = 1310.0;
    canvas.drawRect(const Rect.fromLTRB(60, top, 940, bottom), frame);

    // Light bands every other group of five rows make lines easier to follow.
    final band = Paint()..color = _band;
    for (var g = 1; g < OmrLayout.rowsPerColumn ~/ 5; g += 2) {
      final y1 = OmrLayout.rowY(g * 5) - OmrLayout.answerRowGap / 2;
      final y2 = OmrLayout.rowY(g * 5 + 4) + OmrLayout.answerRowGap / 2;
      canvas.drawRect(Rect.fromLTRB(61, y1, 939, y2), band);
    }

    final divider = Paint()
      ..color = _outline
      ..strokeWidth = 1;
    for (var c = 1; c < OmrLayout.columnCount; c++) {
      final x = OmrLayout.columnX(c) - 17;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), divider);
    }

    for (var q = 0; q < OmrLayout.maxQuestions; q++) {
      final first = OmrLayout.answerBubble(q, 0);
      _text(canvas, toBanglaDigits('${q + 1}'), Offset(first.x - 22, first.y),
          size: 15, weight: FontWeight.bold, align: TextAlign.right);
      for (var o = 0; o < OmrLayout.optionCount; o++) {
        _bubble(canvas, OmrLayout.answerBubble(q, o), OmrLayout.answerRadius,
            OmrLayout.optionLabels[o]);
      }
    }
  }

  void _bubble(Canvas canvas, Pt c, double r, String label) {
    canvas.drawCircle(
      Offset(c.x, c.y),
      r,
      Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    if (label.isNotEmpty) {
      _text(canvas, label, Offset(c.x, c.y),
          size: r * 0.95, color: _faint, align: TextAlign.center);
    }
  }

  Rect _square(Pt c, double side) =>
      Rect.fromCenter(center: Offset(c.x, c.y), width: side, height: side);

  /// Draws [text] vertically centred on [at]; [align] picks whether [at] is
  /// the left edge, centre or right edge.
  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    double size = 14,
    FontWeight weight = FontWeight.normal,
    Color color = _ink,
    TextAlign align = TextAlign.left,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: fontFamily,
            fontSize: size,
            fontWeight: weight,
            color: color,
            height: 1.1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.center => at.dx - tp.width / 2,
      TextAlign.right => at.dx - tp.width,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant OmrSheetPainter oldDelegate) => false;
}

/// Renders the sheet as a print-ready PNG (A4 at 300 dpi by default).
Future<Uint8List> renderSheetPng({
  int pixelWidth = 2480,
  String? fontFamily,
}) async {
  final pixelHeight =
      (pixelWidth * OmrLayout.height / OmrLayout.width).round();
  final recorder = ui.PictureRecorder();
  OmrSheetPainter(fontFamily: fontFamily).paint(
    Canvas(recorder),
    Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
  );
  final image =
      await recorder.endRecording().toImage(pixelWidth, pixelHeight);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
