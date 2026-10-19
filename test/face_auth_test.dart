import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:omr_project/auth/face_math.dart';
import 'package:omr_project/auth/user_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A random unit vector, standing in for one person's face embedding.
List<double> randomFace(math.Random rng) =>
    normalize([for (var i = 0; i < 192; i++) rng.nextDouble() * 2 - 1]);

/// [face] nudged by [amount] of noise: the same person in another frame.
List<double> jitter(List<double> face, math.Random rng, double amount) =>
    normalize([for (final x in face) x + (rng.nextDouble() * 2 - 1) * amount]);

void main() {
  final rng = math.Random(7);

  group('face math', () {
    test('normalize gives unit length', () {
      final v = normalize([3, 4]);
      expect(v[0], closeTo(0.6, 1e-9));
      expect(v[1], closeTo(0.8, 1e-9));
    });

    test('same face matches, a different face does not', () {
      final alice = randomFace(rng);
      final bob = randomFace(rng);
      final probe = jitter(alice, rng, 0.03);

      final match = bestMatch(probe, ['alice', 'bob'],
          (name) => [name == 'alice' ? alice : bob]);
      expect(match!.candidate, 'alice');
      expect(match.isMatch, isTrue);
      expect(distance(probe, bob), greaterThan(faceMatchThreshold));
    });

    test('no candidates, no match', () {
      expect(bestMatch(randomFace(rng), <String>[], (_) => []), isNull);
    });
  });

  group('user store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('register, recognise, session and fingerprint owner', () async {
      final store = await UserStore.instance();
      final face = randomFace(rng);
      final user = await store.register(
        name: '  করিম ',
        institution: 'বিদ্যাবাড়ি',
        faces: [face, jitter(face, rng, 0.02)],
      );
      expect(user.name, 'করিম');

      // Reloaded from storage.
      final again = await UserStore.instance();
      expect(again.users.single.faces.length, 2);
      expect(again.recognize(jitter(face, rng, 0.03))?.id, user.id);
      expect(again.recognize(randomFace(rng)), isNull);

      expect(again.currentUser, isNull);
      await again.login(user);
      expect((await UserStore.instance()).currentUser?.id, user.id);

      await again.setFingerprintUser(user);
      expect(again.fingerprintUser?.id, user.id);

      await again.delete(user);
      expect(again.users, isEmpty);
      expect(again.currentUser, isNull);
      expect(again.fingerprintUser, isNull);
    });
  });
}
