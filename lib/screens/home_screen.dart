import 'package:flutter/material.dart';

import '../auth/fingerprint.dart';
import '../auth/screens/welcome_screen.dart';
import '../auth/user_store.dart';
import '../auth/widgets/auth_widgets.dart';
import '../omr/answer_key.dart';
import '../omr/bangla.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'answer_key_screen.dart';
import 'answer_sheet_screen.dart';
import 'sheet_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AnswerKey? _key;
  AppUser? _user;

  @override
  void initState() {
    super.initState();
    AnswerKey.load().then((key) {
      if (mounted) setState(() => _key = key);
    });
    UserStore.instance().then((store) {
      if (mounted) setState(() => _user = store.currentUser);
    });
  }

  Future<void> _showProfile() async {
    final user = _user;
    if (user == null) return;
    final store = await UserStore.instance();
    final fingerprintAvailable = await Fingerprint.hasSensor();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => _ProfileSheet(
        user: user,
        fingerprintAvailable: fingerprintAvailable,
        fingerprintOn: store.fingerprintUser?.id == user.id,
        onFingerprint: (on) async {
          if (!on) {
            await store.setFingerprintUser(null);
            return true;
          }
          final error = await Fingerprint.verify(
              'ফিঙ্গারপ্রিন্ট চালু করতে আঙুল রাখুন');
          if (error == null) {
            await store.setFingerprintUser(user);
            return true;
          }
          if (error.isNotEmpty && mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error)));
          }
          return false;
        },
        onLogout: () async {
          Navigator.pop(sheetContext);
          final ok = await showAppDialog(
            context: context,
            icon: Icons.logout_rounded,
            title: 'লগআউট করবেন?',
            message: 'আবার ঢুকতে ফেস বা ফিঙ্গারপ্রিন্ট লাগবে।',
            confirmText: 'লগআউট',
            cancelText: 'না',
          );
          if (ok != true) return;
          await store.logout();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (_) => false,
          );
        },
      ),
    );
  }

  Future<void> _editKey() async {
    final updated = await Navigator.push<AnswerKey>(
      context,
      MaterialPageRoute(builder: (_) => AnswerKeyScreen(initial: _key!)),
    );
    if (updated != null) setState(() => _key = updated);
  }

  void _openAnswerSheet() {
    final key = _key!;
    if (key.answers.every((a) => a == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('আগে প্রশ্ন সেট করে সঠিক উত্তর দিন।'),
      ));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnswerSheetScreen(answerKey: key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    return Scaffold(
      body: key == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _hero(key),
                  const SizedBox(height: 20),
                  const Text('কাজ শুরু করুন',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text)),
                  const SizedBox(height: 12),
                  _ActionCard(
                    icon: Icons.fact_check_outlined,
                    color: AppColors.primary,
                    title: 'উত্তরপত্র খুলুন',
                    subtitle: 'নিজে উত্তর দিন বা OMR স্ক্যান করে পূরণ করুন',
                    onTap: _openAnswerSheet,
                    highlighted: true,
                  ),
                  const SizedBox(height: 12),
                  _ActionCard(
                    icon: Icons.edit_note_rounded,
                    color: AppColors.brandGreen,
                    title: 'প্রশ্ন সেট',
                    subtitle: 'প্রশ্ন, অপশন ও সঠিক উত্তর লিখুন',
                    onTap: _editKey,
                  ),
                  const SizedBox(height: 12),
                  _ActionCard(
                    icon: Icons.print_outlined,
                    color: AppColors.primaryDark,
                    title: 'খালি OMR শিট',
                    subtitle: 'প্রিন্ট করার জন্য A4 শিট শেয়ার করুন',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SheetScreen()),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _tips(),
                ],
              ),
            ),
    );
  }

  Widget _hero(AnswerKey key) {
    final missing = key.answers.where((a) => a == null).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.document_scanner_rounded,
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('বিদ্যাবাড়ি',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('OMR রিডার',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (_user != null)
                Tooltip(
                  message: 'প্রোফাইল',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _showProfile,
                    child: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: UserAvatar(name: _user!.name, size: 40),
                    ),
                  ),
                ),
            ],
          ),
          if (_user != null) ...[
            const SizedBox(height: 14),
            Text(
              'স্বাগতম, ${_user!.name}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              _HeroStat(
                  value: toBanglaDigits('${key.questionCount}'),
                  label: 'প্রশ্ন'),
              _HeroStat(
                  value: formatMarks(key.markPerCorrect), label: 'সঠিকে নম্বর'),
              _HeroStat(
                  value: '-${formatMarks(key.negativeMark)}',
                  label: 'ভুলে কাটা'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                missing == 0 ? Icons.check_circle : Icons.info_outline,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  missing == 0
                      ? 'প্রশ্ন সেট প্রস্তুত'
                      : '${toBanglaDigits('$missing')}টি প্রশ্নের সঠিক উত্তর বাকি',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tips() {
    const tips = [
      'শিটটি সমতল জায়গায় রাখুন, চার কোণার কালো বর্গ যেন ছবির ভেতরে থাকে।',
      'উপর থেকে সোজা করে, ভালো আলোতে ছবি তুলুন; ছায়া এড়িয়ে চলুন।',
      'কমলা রঙে চিহ্নিত প্রশ্নগুলো সাবমিটের আগে মিলিয়ে নিন।',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: AppColors.warning),
              SizedBox(width: 8),
              Text('ভালো স্ক্যানের জন্য',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: 10),
                    child: CircleAvatar(
                        radius: 3, backgroundColor: AppColors.primary),
                  ),
                  Expanded(
                    child: Text(tip,
                        style: const TextStyle(color: AppColors.muted)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;

  const _HeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: highlighted
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: highlighted ? AppColors.primary : AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The logged-in teacher: name, fingerprint login switch and logout.
class _ProfileSheet extends StatefulWidget {
  final AppUser user;
  final bool fingerprintAvailable;
  final bool fingerprintOn;

  /// Turns fingerprint login on/off; resolves to whether it took effect.
  final Future<bool> Function(bool on) onFingerprint;
  final VoidCallback onLogout;

  const _ProfileSheet({
    required this.user,
    required this.fingerprintAvailable,
    required this.fingerprintOn,
    required this.onFingerprint,
    required this.onLogout,
  });

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late bool _fingerprintOn = widget.fingerprintOn;
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    final changed = await widget.onFingerprint(on);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (changed) _fingerprintOn = on;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(name: user.name, size: 72),
            const SizedBox(height: 12),
            Text(user.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text)),
            if (user.institution.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(user.institution,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted)),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_rounded,
                      size: 14, color: AppColors.success),
                  SizedBox(width: 5),
                  Text('ফেস দিয়ে সুরক্ষিত',
                      style: TextStyle(
                          color: AppColors.success,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _fingerprintOn,
                    onChanged: widget.fingerprintAvailable && !_busy
                        ? _toggle
                        : null,
                    activeTrackColor: AppColors.brandGreen,
                    secondary: const Icon(Icons.fingerprint_rounded,
                        color: AppColors.brandGreen),
                    title: const Text('ফিঙ্গারপ্রিন্ট লগইন',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(widget.fingerprintAvailable
                        ? 'এক ছোঁয়ায় লগইন করুন'
                        : 'এই ফোনে ফিঙ্গারপ্রিন্ট সেন্সর নেই'),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  ListTile(
                    onTap: widget.onLogout,
                    leading: const Icon(Icons.logout_rounded,
                        color: AppColors.danger),
                    title: const Text('লগআউট',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
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
