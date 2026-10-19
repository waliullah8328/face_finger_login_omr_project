import 'dart:math' as math;

/// Two faces are the same person when their normalized embeddings are closer
/// than this (Euclidean). On unit vectors it equals cosine similarity ≈ 0.64;
/// raise it if real users are often rejected, lower it if strangers match.
const double faceMatchThreshold = 0.85;

/// Scales [v] to unit length, so distances compare direction only.
List<double> normalize(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final norm = math.sqrt(sum);
  if (norm == 0) return List<double>.of(v);
  return [for (final x in v) x / norm];
}

double distance(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    sum += d * d;
  }
  return math.sqrt(sum);
}

/// Normalized mean of several embeddings of the same face: steadier than any
/// single frame.
List<double> averageEmbedding(List<List<double>> samples) {
  final sum = List<double>.filled(samples.first.length, 0);
  for (final s in samples) {
    for (var i = 0; i < s.length; i++) {
      sum[i] += s[i];
    }
  }
  return normalize(sum);
}

/// Closest registered face to [probe], and its distance.
class FaceMatch<T> {
  final T candidate;
  final double distance;

  const FaceMatch(this.candidate, this.distance);

  bool get isMatch => distance < faceMatchThreshold;
}

/// Finds the candidate whose closest sample is nearest to [probe]; `null`
/// when there are no candidates.
FaceMatch<T>? bestMatch<T>(
  List<double> probe,
  Iterable<T> candidates,
  List<List<double>> Function(T) samplesOf,
) {
  FaceMatch<T>? best;
  for (final c in candidates) {
    for (final s in samplesOf(c)) {
      final d = distance(probe, s);
      if (best == null || d < best.distance) best = FaceMatch(c, d);
    }
  }
  return best;
}
