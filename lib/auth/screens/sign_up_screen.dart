import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../face_math.dart';
import '../fingerprint.dart';
import '../user_store.dart';
import '../widgets/auth_widgets.dart';
import 'face_scan_screen.dart';

/// Asks for the finger and ties the phone's fingerprint to [user].
Future<void> enableFingerprint(BuildContext context, AppUser user) async {
  final store = await UserStore.instance();
  final error = await Fingerprint.verify('ফিঙ্গারপ্রিন্ট চালু করতে আঙুল রাখুন');
  if (!context.mounted) return;
  if (error == null) {
    await store.setFingerprintUser(user);
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ফিঙ্গারপ্রিন্ট লগইন চালু হয়েছে')));
    }
  } else if (error.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}

/// Step 1 of sign up: name (and institution); step 2 is the face scan.
/// Pops with `true` once the account is created and logged in.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _institutionCtrl = TextEditingController();
  bool _showNameError = false;
  bool _hasSensor = false;
  bool _useFingerprint = true;

  /// Who the fingerprint unlocks now; turning it on here moves it over.
  String? _fingerprintOwner;

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final hasSensor = await Fingerprint.hasSensor();
    final owner = (await UserStore.instance()).fingerprintUser?.name;
    if (mounted) {
      setState(() {
        _hasSensor = hasSensor;
        _fingerprintOwner = owner;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _institutionCtrl.dispose();
    super.dispose();
  }

  bool get _nameValid => _nameCtrl.text.trim().length >= 2;

  Future<void> _scan() async {
    if (!_nameValid) {
      setState(() => _showNameError = true);
      return;
    }
    FocusScope.of(context).unfocus();
    final store = await UserStore.instance();
    AppUser? created;
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceScanScreen(
          title: 'ফেস নিবন্ধন',
          samples: 3,
          onCaptured: (samples) async {
            final existing = store.recognize(averageEmbedding(samples));
            if (existing != null) {
              return FaceScanOutcome.failure(
                'এই ফেস আগেই নিবন্ধিত',
                'এটি "${existing.name}" নামে নিবন্ধিত আছে। '
                    'ফিরে গিয়ে "ফেস দিয়ে লগইন" করুন।',
              );
            }
            created = await store.register(
              name: _nameCtrl.text,
              institution: _institutionCtrl.text,
              faces: samples,
            );
            await store.login(created!);
            return const FaceScanOutcome.success(
                'নিবন্ধন সম্পন্ন!', 'আপনার ফেস সফলভাবে সংরক্ষিত হয়েছে');
          },
        ),
      ),
    );
    if (ok != true || created == null || !mounted) return;
    if (_hasSensor && _useFingerprint) {
      await enableFingerprint(context, created!);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(onBack: () => Navigator.pop(context, false)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                const Text('আপনার পরিচয়',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_showNameError) setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'আপনার নাম',
                    hintText: 'যেমন: রহিম উদ্দিন',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    errorText: _showNameError && !_nameValid
                        ? 'নাম লিখুন (কমপক্ষে ২ অক্ষর)'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _institutionCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _scan(),
                  decoration: const InputDecoration(
                    labelText: 'প্রতিষ্ঠান (ঐচ্ছিক)',
                    hintText: 'স্কুল, কলেজ বা কোচিং-এর নাম',
                    prefixIcon: Icon(Icons.school_outlined),
                  ),
                ),
                if (_hasSensor) ...[
                  const SizedBox(height: 18),
                  _FingerprintOption(
                    value: _useFingerprint,
                    previousOwner: _fingerprintOwner,
                    onChanged: (v) => setState(() => _useFingerprint = v),
                  ),
                ],
                const SizedBox(height: 26),
                const _TipsCard(),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: GradientButton(
                label: 'ফেস স্ক্যান শুরু করুন',
                icon: Icons.face_retouching_natural_rounded,
                onPressed: _scan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;

  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'ফিরে যান',
                onPressed: onBack,
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('ধাপ ১ / ২',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 10),
                    const Text('নতুন অ্যাকাউন্ট',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('নাম লিখুন, তারপর ফেস স্ক্যান করুন',
                        style: TextStyle(color: Colors.white70, fontSize: 14.5)),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(child: _bar(Colors.white)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: _bar(Colors.white.withValues(alpha: 0.3))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(Color color) => Container(
        height: 5,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3)),
      );
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  static const _tips = [
    (Icons.wb_sunny_outlined, 'আলোকিত জায়গায় থাকুন', 'মুখে যেন ছায়া না পড়ে'),
    (Icons.face_outlined, 'মুখ খোলা রাখুন', 'চশমা, মাস্ক বা টুপি খুলে ফেলুন'),
    (Icons.smartphone_rounded, 'ফোন চোখ বরাবর ধরুন', 'সোজা ক্যামেরার দিকে তাকান'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tips_and_updates_rounded,
                  color: AppColors.warning, size: 20),
              SizedBox(width: 8),
              Text('ভালো স্ক্যানের জন্য',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.text)),
            ],
          ),
          for (final (icon, title, subtitle) in _tips) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.text)),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Sign-up choice to also log in with the fingerprint; the finger is asked
/// for right after the face scan.
class _FingerprintOption extends StatelessWidget {
  final bool value;
  final String? previousOwner;
  final ValueChanged<bool> onChanged;

  const _FingerprintOption({
    required this.value,
    required this.previousOwner,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: value
            ? AppColors.brandGreen.withValues(alpha: 0.07)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: value
              ? AppColors.brandGreen.withValues(alpha: 0.5)
              : AppColors.border,
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.brandGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.fingerprint_rounded,
                size: 28, color: AppColors.brandGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ফিঙ্গারপ্রিন্ট দিয়েও লগইন',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.text)),
                const SizedBox(height: 2),
                Text(
                  previousOwner == null
                      ? 'ফেস স্ক্যানের পর একবার আঙুল ছোঁয়ালেই চালু হবে'
                      : 'চালু করলে $previousOwner-এর বদলে আপনার অ্যাকাউন্টে যাবে',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.brandGreen,
          ),
        ],
      ),
    );
  }
}
