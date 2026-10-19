import 'package:local_auth/local_auth.dart';

/// The phone's own fingerprint (or Face ID on iPhone) check.
class Fingerprint {
  Fingerprint._();

  static final _auth = LocalAuthentication();

  /// Whether the phone has a fingerprint sensor at all, enrolled or not.
  static Future<bool> hasSensor() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Whether a fingerprint is enrolled and usable right now.
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// `null` when verified; otherwise a message for the user, empty when they
  /// simply cancelled.
  static Future<String?> verify(String reason) async {
    try {
      final ok =
          await _auth.authenticate(localizedReason: reason, biometricOnly: true);
      return ok ? null : 'ফিঙ্গারপ্রিন্ট মেলেনি।';
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          '',
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noCredentialsSet =>
          'ফোনে কোনো ফিঙ্গারপ্রিন্ট সেট করা নেই। ফোনের সেটিংস থেকে যোগ করুন।',
        LocalAuthExceptionCode.noBiometricHardware =>
          'এই ফোনে ফিঙ্গারপ্রিন্ট সেন্সর নেই।',
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          'অনেকবার ভুল হয়েছে। কিছুক্ষণ পর আবার চেষ্টা করুন।',
        _ => 'ফিঙ্গারপ্রিন্ট যাচাই করা যায়নি।',
      };
    } catch (_) {
      return 'ফিঙ্গারপ্রিন্ট যাচাই করা যায়নি।';
    }
  }
}
