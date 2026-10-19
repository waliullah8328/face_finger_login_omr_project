import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../omr/omr_layout.dart';
import '../omr/sheet_painter.dart';

/// Shows the blank OMR sheet and shares it as a print-ready A4 PNG.
class SheetScreen extends StatefulWidget {
  const SheetScreen({super.key});

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final png = await renderSheetPng();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/biddabari_omr_sheet.png');
      await file.writeAsBytes(png);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: 'বিদ্যাবাড়ি OMR উত্তরপত্র (A4 সাইজে প্রিন্ট করুন)',
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('খালি OMR শিট')),
      backgroundColor: Colors.grey.shade300,
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AspectRatio(
              aspectRatio: OmrLayout.width / OmrLayout.height,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black26)],
                ),
                child: CustomPaint(painter: OmrSheetPainter()),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _share,
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.share),
        label: const Text('প্রিন্ট / শেয়ার'),
      ),
    );
  }
}
