import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../omr/bangla.dart';
import '../../screens/home_screen.dart';
import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import '../face_math.dart';
import '../fingerprint.dart';
import '../user_store.dart';
import '../widgets/auth_widgets.dart';
import 'face_scan_screen.dart';
import 'sign_up_screen.dart';


/// Replaces the whole navigation stack with the home screen.
void openHome(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, _, _) => const HomeScreen(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
    (_) => false,
  );
}

/// First screen when nobody is logged in: log in with face or fingerprint,
/// or create an account.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  UserStore? _store;
  bool _hasSensor = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await UserStore.instance();
    final hasSensor = await Fingerprint.hasSensor();
    if (mounted) {
      setState(() {
        _store = store;
        _hasSensor = hasSensor;
      });
    }
  }

  Future<void> _faceLogin() async {
    final store = _store!;
    if (store.users.isEmpty) {
      final create = await showAppDialog(
        context: context,
        icon: Icons.person_add_alt_1_rounded,
        title: 'কোনো অ্যাকাউন্ট নেই',
        message: 'এই ফোনে এখনো কেউ নিবন্ধন করেনি। আগে একটি অ্যাকাউন্ট খুলুন।',
        confirmText: 'অ্যাকাউন্ট খুলুন',
        cancelText: 'পরে',
      );
      if (create == true && mounted) _signUp();
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceScanScreen(
          title: 'ফেস দিয়ে লগইন',
          samples: 2,
          onCaptured: (samples) async {
            final user = store.recognize(averageEmbedding(samples));
            if (user == null) {
              return const FaceScanOutcome.failure(
                'চিনতে পারিনি',
                'আলো ঠিক আছে কিনা দেখে আবার চেষ্টা করুন, '
                    'অথবা নতুন অ্যাকাউন্ট খুলুন।',
              );
            }
            await store.login(user);
            return FaceScanOutcome.success('স্বাগতম, ${user.name}!');
          },
        ),
      ),
    );
    if (ok == true && mounted) openHome(context);
  }

  Future<void> _fingerprintLogin() async {
    final store = _store!;
    final user = store.fingerprintUser;
    if (user == null) {
      // Not set up yet: it is turned on while signing up (or later from the
      // profile), where it is known which account it belongs to.
      final signUp = await showAppDialog(
        context: context,
        icon: Icons.fingerprint_rounded,
        color: AppColors.brandGreen,
        title: 'ফিঙ্গারপ্রিন্ট এখনো চালু হয়নি',
        message: 'নতুন অ্যাকাউন্ট খোলার সময় "ফিঙ্গারপ্রিন্ট দিয়েও লগইন" চালু '
            'রাখুন, তাহলে পরের বার শুধু আঙুল ছোঁয়ালেই লগইন হবে।'
            '${store.users.isEmpty ? '' : '\n\nআগেই অ্যাকাউন্ট থাকলে লগইন করে প্রোফাইল থেকে চালু করুন।'}',
        confirmText: 'অ্যাকাউন্ট খুলুন',
        cancelText: 'ঠিক আছে',
      );
      if (signUp == true && mounted) await _signUp();
      return;
    }
    final error =
        await Fingerprint.verify('${user.name} হিসেবে লগইন করতে আঙুল রাখুন');
    if (!mounted) return;
    if (error == null) {
      HapticFeedback.mediumImpact();
      await store.login(user);
      if (mounted) openHome(context);
    } else if (error.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _signUp() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
    if (ok == true && mounted) {
      openHome(context);
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primaryDark,
        body: Stack(
          children: [
            const Positioned.fill(child: _Backdrop()),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _Brand(),
                  ),
                  const Expanded(child: Center(child: _FaceIdHero())),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        Text(
                          'মুখ দেখালেই লগইন',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'পাসওয়ার্ড মনে রাখার ঝামেলা নেই — আপনার চেহারাই আপনার চাবি',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  _ActionSheet(
                    loading: store == null,
                    userCount: store?.users.length ?? 0,
                    showFingerprint: _hasSensor,
                    fingerprintName: store?.fingerprintUser?.name,
                    onFaceLogin: _faceLogin,
                    onFingerprintLogin: _fingerprintLogin,
                    onSignUp: _signUp,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.document_scanner_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('বিদ্যাবাড়ি',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            Text('OMR রিডার',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }
}

/// Brand gradient with large soft circles for depth.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    Widget blob(double size, double alpha) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: alpha),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D0833), AppColors.primaryDark, AppColors.primary],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -90, right: -70, child: blob(260, 0.07)),
          Positioned(top: 220, left: -110, child: blob(220, 0.05)),
          Positioned(top: 120, right: 40, child: blob(14, 0.25)),
          Positioned(top: 330, right: 70, child: blob(8, 0.3)),
          Positioned(top: 90, left: 60, child: blob(10, 0.2)),
        ],
      ),
    );
  }
}

/// Pulsing rings and Face ID corner brackets around a face badge.
class _FaceIdHero extends StatefulWidget {
  const _FaceIdHero();

  @override
  State<_FaceIdHero> createState() => _FaceIdHeroState();
}

class _FaceIdHeroState extends State<_FaceIdHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = math.min(MediaQuery.sizeOf(context).width * 0.62, 250.0);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => CustomPaint(
        size: Size.square(size),
        painter: _PulsePainter(_pulse.value),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Transform.scale(
              // Gentle breathing.
              scale: 1 + 0.03 * math.sin(_pulse.value * 2 * math.pi),
              child: Container(
                width: size * 0.46,
                height: size * 0.46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ShaderMask(
                  shaderCallback: (rect) =>
                      AppColors.headerGradient.createShader(rect),
                  child: Icon(Icons.face_retouching_natural_rounded,
                      size: size * 0.26, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double t;

  _PulsePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.width * 0.23;

    // Three rings expanding outwards and fading, staggered.
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(
        center,
        base + (size.width * 0.27) * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.35 * (1 - p)),
      );
    }

    // Face ID style corner brackets.
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.9);
    final r = size.width / 2 - 4;
    const arm = 0.2;
    final rect = Rect.fromCircle(center: center, radius: r);
    final corner = r * 0.32;
    for (final (dx, dy) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)]) {
      final cx = center.dx + dx * r, cy = center.dy + dy * r;
      final path = Path()
        ..moveTo(cx, cy - dy * r * 2 * arm)
        ..lineTo(cx, cy - dy * corner)
        ..arcToPoint(Offset(cx - dx * corner, cy),
            radius: Radius.circular(corner), clockwise: dx * dy > 0)
        ..lineTo(cx - dx * r * 2 * arm, cy);
      canvas.drawPath(path, bracket);
    }

    // A scan bar sliding down between the brackets.
    final y = rect.top + rect.height * (0.15 + 0.7 * ((t * 2) % 1));
    canvas.drawLine(
      Offset(rect.left + r * 0.35, y),
      Offset(rect.right - r * 0.35, y),
      Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.brandGreen.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}

/// White bottom sheet with the login and sign up actions.
class _ActionSheet extends StatelessWidget {
  final bool loading;
  final int userCount;

  /// Whether the phone has a fingerprint sensor.
  final bool showFingerprint;

  /// Name of the account the fingerprint unlocks; `null` when not set up.
  final String? fingerprintName;
  final VoidCallback onFaceLogin;
  final VoidCallback onFingerprintLogin;
  final VoidCallback onSignUp;

  const _ActionSheet({
    required this.loading,
    required this.userCount,
    required this.showFingerprint,
    required this.fingerprintName,
    required this.onFaceLogin,
    required this.onFingerprintLogin,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          20, 26, 20, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: 'ফেস দিয়ে লগইন',
                  icon: Icons.face_rounded,
                  onPressed: loading ? null : onFaceLogin,
                ),
              ),
              if (showFingerprint) ...[
                const SizedBox(width: 12),
                _FingerprintButton(
                  name: fingerprintName,
                  onPressed: loading ? null : onFingerprintLogin,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: loading ? null : onSignUp,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('নতুন অ্যাকাউন্ট খুলুন'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border, width: 1.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 14, color: AppColors.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  userCount == 0
                      ? 'ফেস ডেটা শুধু এই ফোনেই থাকে'
                      : 'ফেস ডেটা শুধু এই ফোনেই থাকে · '
                          '${toBanglaDigits('$userCount')} জন নিবন্ধিত',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FingerprintButton extends StatelessWidget {
  /// Account it unlocks; `null` when fingerprint login is not set up yet.
  final String? name;
  final VoidCallback? onPressed;

  const _FingerprintButton({required this.name, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name == null
          ? 'ফিঙ্গারপ্রিন্ট লগইন চালু করুন'
          : 'ফিঙ্গারপ্রিন্ট দিয়ে লগইন ($name)',
      child: Material(
        color: AppColors.brandGreen.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: AppColors.brandGreen.withValues(alpha: 0.4), width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const SizedBox.square(
            dimension: 58,
            child: Icon(Icons.fingerprint_rounded,
                size: 32, color: AppColors.brandGreen),
          ),
        ),
      ),
    );
  }
}
