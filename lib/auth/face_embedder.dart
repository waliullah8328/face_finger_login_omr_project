import 'dart:ui';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_frame.dart';
import 'face_math.dart';

/// Runs MobileFaceNet: a face crop in, a normalized embedding out. Two crops
/// of the same person give nearby embeddings (see [faceMatchThreshold]).
class FaceEmbedder {
  final Interpreter _interpreter;
  final int _inputSize;
  final List<int> _outputShape;

  FaceEmbedder._(this._interpreter)
      : _inputSize = _interpreter.getInputTensor(0).shape[1],
        _outputShape = _interpreter.getOutputTensor(0).shape;

  static Future<FaceEmbedder> load() async => FaceEmbedder._(
      await Interpreter.fromAsset('assets/models/mobilefacenet.tflite'));

  List<double> embed(FaceFrame frame, Rect faceBox) {
    final input = frame
        .faceInput(faceBox, _inputSize)
        .reshape([1, _inputSize, _inputSize, 3]);
    final output = List.generate(
        _outputShape.first, (_) => List<double>.filled(_outputShape.last, 0));
    _interpreter.run(input, output);
    return normalize(output.first);
  }

  void close() => _interpreter.close();
}
