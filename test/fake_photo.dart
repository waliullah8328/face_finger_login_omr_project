import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Simulates a phone photo: places the sheet's corners at [corners] (clockwise
/// from the sheet's own top-left) on a grey table, with shading and noise.
Uint8List photograph(img.Image sheet, List<math.Point<double>> corners,
    {int width = 1500, int height = 2000, int seed = 1}) {
  // True perspective, like a camera: photo pixel -> sheet pixel.
  final toSheet = _solveHomography(corners, [
    const math.Point(0, 0),
    math.Point(sheet.width - 1.0, 0),
    math.Point(sheet.width - 1.0, sheet.height - 1.0),
    math.Point(0, sheet.height - 1.0),
  ]);
  final out = img.Image(width: width, height: height, numChannels: 3)
    ..clear(img.ColorRgb8(120, 115, 105));
  final rnd = math.Random(seed);
  for (var py = 0; py < height; py++) {
    for (var px = 0; px < width; px++) {
      final z = toSheet[6] * px + toSheet[7] * py + 1;
      final sx = ((toSheet[0] * px + toSheet[1] * py + toSheet[2]) / z).round();
      final sy = ((toSheet[3] * px + toSheet[4] * py + toSheet[5]) / z).round();
      if (sx < 0 || sy < 0 || sx >= sheet.width || sy >= sheet.height) continue;
      final s = sheet.getPixel(sx, sy);
      // Light falls off towards the bottom-right: uneven lighting.
      final shade = 1.0 - 0.35 * (px / width + py / height) / 2;
      final noise = rnd.nextInt(21) - 10;
      int ch(num c) => (c * shade + noise).round().clamp(0, 255);
      out.setPixelRgb(px, py, ch(s.r), ch(s.g), ch(s.b));
    }
  }
  return img.encodeJpg(out, quality: 80);
}

List<double> _solveHomography(
    List<math.Point<double>> from, List<math.Point<double>> to) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = from[i].x, y = from[i].y, u = to[i].x, v = to[i].y;
    a[2 * i].setAll(0, [x, y, 1, 0, 0, 0, -x * u, -y * u, u]);
    a[2 * i + 1].setAll(0, [0, 0, 0, x, y, 1, -x * v, -y * v, v]);
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
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
  return [for (var r = 0; r < 8; r++) a[r][8] / a[r][r]];
}
