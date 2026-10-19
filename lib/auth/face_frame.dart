import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// One camera frame, kept so the face found in it by ML Kit can be cut out
/// for the face-recognition model.
///
/// Android frames are NV21 and iOS frames BGRA, each in a single plane (see
/// [imageFormatGroup]).
class FaceFrame {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;

  /// Clockwise degrees that make the frame upright; ML Kit's face boxes are
  /// in upright coordinates.
  final int rotation;

  FaceFrame._(this.bytes, this.width, this.height, this.bytesPerRow,
      this.rotation);

  /// The stream format both [FaceFrame] and ML Kit understand.
  static ImageFormatGroup get imageFormatGroup =>
      Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;

  static FaceFrame? fromCamera(CameraImage image, CameraController camera) {
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return FaceFrame._(plane.bytes, image.width, image.height,
        plane.bytesPerRow, _rotation(camera));
  }

  static const _deviceDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Rotation from sensor to upright, as in the ML Kit camera examples. iOS
  /// ignores it (frames are analysed as delivered).
  static int _rotation(CameraController camera) {
    if (Platform.isIOS) return 0;
    final sensor = camera.description.sensorOrientation;
    final device = _deviceDegrees[camera.value.deviceOrientation] ?? 0;
    return camera.description.lensDirection == CameraLensDirection.front
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
  }

  /// Size of the upright image, the space ML Kit's boxes are in.
  Size get uprightSize => rotation % 180 == 0
      ? Size(width.toDouble(), height.toDouble())
      : Size(height.toDouble(), width.toDouble());

  InputImage toInputImage() => InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(rotation) ??
              InputImageRotation.rotation0deg,
          format: Platform.isAndroid
              ? InputImageFormat.nv21
              : InputImageFormat.bgra8888,
          bytesPerRow: bytesPerRow,
        ),
      );

  /// The [box] region (upright coordinates) scaled to [size]×[size] RGB,
  /// each channel mapped to about -1..1 as MobileFaceNet expects.
  Float32List faceInput(Rect box, int size) {
    final out = Float32List(size * size * 3);
    final rgb = List<int>.filled(3, 0);
    final stepX = box.width / size, stepY = box.height / size;
    var o = 0;
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        // Average 2×2 samples inside the output pixel to soften aliasing.
        var r = 0, g = 0, b = 0;
        for (final (dx, dy) in const [(.25, .25), (.75, .25), (.25, .75), (.75, .75)]) {
          _uprightPixel(box.left + (col + dx) * stepX,
              box.top + (row + dy) * stepY, rgb);
          r += rgb[0];
          g += rgb[1];
          b += rgb[2];
        }
        out[o++] = (r / 4 - 127.5) / 128;
        out[o++] = (g / 4 - 127.5) / 128;
        out[o++] = (b / 4 - 127.5) / 128;
      }
    }
    return out;
  }

  /// Reads the RGB of upright point ([u], [v]) into [rgb].
  void _uprightPixel(double u, double v, List<int> rgb) {
    final ui = u.floor(), vi = v.floor();
    // Undo the clockwise rotation to find the pixel in the raw frame.
    final (int x, int y) = switch (rotation) {
      90 => (vi, height - 1 - ui),
      180 => (width - 1 - ui, height - 1 - vi),
      270 => (width - 1 - vi, ui),
      _ => (ui, vi),
    };
    final cx = x.clamp(0, width - 1), cy = y.clamp(0, height - 1);

    if (Platform.isAndroid) {
      // NV21: full Y plane, then interleaved V/U at half resolution.
      final yv = bytes[cy * width + cx];
      final uvIndex = width * height + (cy >> 1) * width + (cx & ~1);
      final vv = bytes[uvIndex] - 128;
      final uv = bytes[uvIndex + 1] - 128;
      rgb[0] = (yv + 1.402 * vv).round().clamp(0, 255);
      rgb[1] = (yv - 0.344136 * uv - 0.714136 * vv).round().clamp(0, 255);
      rgb[2] = (yv + 1.772 * uv).round().clamp(0, 255);
    } else {
      final i = cy * bytesPerRow + cx * 4;
      rgb[0] = bytes[i + 2];
      rgb[1] = bytes[i + 1];
      rgb[2] = bytes[i];
    }
  }
}
