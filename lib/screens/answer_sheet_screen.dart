import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../omr/answer_key.dart';
import '../omr/bangla.dart';
import '../omr/omr_layout.dart';
import '../omr/omr_reader.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/option_tile.dart';
import '../widgets/question_card.dart';
import 'result_screen.dart';

/// Image processing is CPU heavy, so it runs on a background isolate.
///
/// Top-level on purpose: a closure created inside a State method can capture
/// the State (and through it the widget tree), which cannot be sent to
/// another isolate.
Future<OmrScanResult> _readInBackground(Uint8List photo, int questionCount) =>
    Isolate.run(() => readOmrSheet(photo, questionCount: questionCount));

enum _PhotoSource { camera, gallery, files }

enum _Filter { all, unanswered, check }

/// Height of the pinned question map (filters + number strip).
const double _mapHeight = 112;

/// One student's answer sheet. Starts with every question unanswered; answers
/// are picked by hand or filled in from a scanned OMR sheet, then submitted.
class AnswerSheetScreen extends StatefulWidget {
  final AnswerKey answerKey;

  const AnswerSheetScreen({super.key, required this.answerKey});

  @override
  State<AnswerSheetScreen> createState() => _AnswerSheetScreenState();
}

class _AnswerSheetScreenState extends State<AnswerSheetScreen> {
  late final int _count = widget.answerKey.questionCount;

  /// Selected option per question (`null` blank, [multipleMarks] double mark).
  late final List<int?> _answers = List<int?>.filled(_count, null);

  /// Whether each current answer came from the OMR sheet (vs. picked by hand).
  late final List<bool> _fromOmr = List<bool>.filled(_count, false);

  /// Questions the reader was unsure about, until the teacher touches them.
  final Set<int> _needsCheck = {};

  late final List<GlobalKey> _cardKeys =
      List.generate(_count, (_) => GlobalKey());
  final _scroll = ScrollController();
  final _rollCtrl = TextEditingController();
  _Filter _filter = _Filter.all;
  OmrScanResult? _scan;
  bool _scanning = false;

  bool _isAnswered(int q) => _answers[q] != null && _answers[q] != multipleMarks;

  int get _answered => [for (var q = 0; q < _count; q++) q].where(_isAnswered).length;

  List<int> get _unanswered =>
      [for (var q = 0; q < _count; q++) if (!_isAnswered(q)) q];

  bool _passesFilter(int q) => switch (_filter) {
        _Filter.all => true,
        _Filter.unanswered => !_isAnswered(q),
        _Filter.check => _needsCheck.contains(q),
      };

  @override
  void dispose() {
    _scroll.dispose();
    _rollCtrl.dispose();
    super.dispose();
  }

  void _select(int q, int option) {
    setState(() {
      _answers[q] = _answers[q] == option ? null : option;
      _fromOmr[q] = false;
      _needsCheck.remove(q);
    });
  }

  /// Scrolls so question [q] sits just below the pinned question map.
  Future<void> _jumpTo(int q) async {
    if (!_passesFilter(q)) setState(() => _filter = _Filter.all);
    await WidgetsBinding.instance.endOfFrame;
    final box = _cardKeys[q].currentContext?.findRenderObject();
    if (box == null || !_scroll.hasClients) return;
    final reveal = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0);
    final target = (reveal.offset - _mapHeight - 8)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    await _scroll.animateTo(target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic);
  }

  Future<void> _fillFromOmr() async {
    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => const _SourceSheet(),
    );
    if (source == null || !mounted) return;

    final bytes = await _pickPhoto(source);
    if (bytes == null || !mounted) return;

    if (_answers.any((a) => a != null)) {
      final replace = await showAppDialog(
        context: context,
        icon: Icons.sync_alt_rounded,
        color: AppColors.warning,
        title: 'উত্তর বদলে যাবে',
        message: 'আগে দেওয়া উত্তরগুলোর জায়গায় OMR শিটের উত্তর বসবে।',
        cancelText: 'না',
        confirmText: 'হ্যাঁ, বসান',
      );
      if (replace != true || !mounted) return;
    }

    setState(() => _scanning = true);
    try {
      final scan = await _readInBackground(bytes, _count);
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _filter = _Filter.all;
        for (var q = 0; q < _count; q++) {
          _answers[q] = scan.answers[q];
          _fromOmr[q] = scan.answers[q] != null;
        }
        _needsCheck
          ..clear()
          ..addAll([
            for (var q = 0; q < _count; q++)
              if (scan.uncertain[q] || scan.answers[q] == multipleMarks) q,
          ]);
        if (!scan.roll.contains('?')) _rollCtrl.text = scan.roll;
      });
      final filled = _fromOmr.where((f) => f).length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'OMR থেকে ${toBanglaDigits('$filled')}টি উত্তর বসানো হয়েছে'),
      ));
    } on OmrException catch (e) {
      if (mounted) _showScanError(e.message);
    } catch (e, stack) {
      debugPrint('OMR scan failed: $e\n$stack');
      if (mounted) {
        _showScanError(
            'স্ক্যান করা যায়নি। অন্য একটি পরিষ্কার ছবি দিয়ে আবার চেষ্টা করুন।');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<Uint8List?> _pickPhoto(_PhotoSource source) async {
    if (source == _PhotoSource.files) {
      final file = await FilePicker.pickFile(type: FileType.image);
      return file?.readAsBytes();
    }
    final photo = await ImagePicker().pickImage(
      source: source == _PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 92,
    );
    return photo?.readAsBytes();
  }

  void _showScanError(String message) {
    showAppDialog(
      context: context,
      icon: Icons.document_scanner_outlined,
      color: AppColors.danger,
      title: 'OMR পড়া যায়নি',
      message: message,
    );
  }

  Future<void> _submit() async {
    final unanswered = _unanswered;
    final multiple = _answers.where((a) => a == multipleMarks).length;
    final ok = await showAppDialog(
      context: context,
      icon: unanswered.isEmpty
          ? Icons.task_alt_rounded
          : Icons.assignment_late_outlined,
      color: unanswered.isEmpty ? AppColors.success : AppColors.primary,
      title: 'সাবমিট করবেন?',
      message: unanswered.isEmpty
          ? 'সব প্রশ্নের উত্তর দেওয়া হয়েছে।'
          : 'কিছু প্রশ্নের উত্তর এখনো দেওয়া হয়নি।',
      content: _SubmitSummary(
        answered: _answered,
        unanswered: unanswered,
        multiple: multiple,
      ),
      cancelText: unanswered.isEmpty ? 'ফিরে যাই' : 'বাকিগুলো দেখি',
      confirmText: 'সাবমিট',
    );
    if (!mounted) return;
    if (ok == false && unanswered.isNotEmpty) {
      setState(() => _filter = _Filter.unanswered);
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      return;
    }
    if (ok != true) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          answerKey: widget.answerKey,
          answers: [..._answers],
          roll: _rollCtrl.text.trim(),
          setCode: _scan?.setCode,
          scan: _scan,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = [for (var q = 0; q < _count; q++) if (_passesFilter(q)) q];
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('উত্তরপত্র'),
            actions: [
              if (_scan != null)
                IconButton(
                  tooltip: 'স্ক্যান করা ছবি',
                  icon: const Icon(Icons.image_outlined),
                  onPressed: () => showScanImage(context, _scan!),
                ),
            ],
          ),
          body: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _QuestionMapDelegate(
                  count: _count,
                  filter: _filter,
                  answered: _isAnswered,
                  needsCheck: _needsCheck,
                  answers: _answers,
                  unansweredCount: _count - _answered,
                  onFilter: (f) => setState(() => _filter = f),
                  onTapQuestion: _jumpTo,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: visible.isEmpty
                      ? _emptyFilter()
                      // Built eagerly (at most 100 cards) so any question can
                      // be scrolled to from the question map.
                      : Column(
                          children: [
                            for (final q in visible)
                              Padding(
                                key: _cardKeys[q],
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _questionCard(q),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _bottomBar(),
        ),
        if (_scanning) const _ScanningOverlay(),
      ],
    );
  }

  Widget _questionCard(int q) {
    final options = widget.answerKey.optionTexts[q];
    final answer = _answers[q];
    final (Color accent, Widget tag) = answer == multipleMarks
        ? (
            AppColors.danger,
            const StatusTag('একাধিক দাগ', AppColors.danger,
                icon: Icons.error_outline),
          )
        : _needsCheck.contains(q)
            ? (
                AppColors.warning,
                const StatusTag('যাচাই করুন', AppColors.warning,
                    icon: Icons.visibility_outlined),
              )
            : answer == null
                ? (
                    AppColors.muted,
                    const StatusTag('বাকি', AppColors.muted,
                        icon: Icons.radio_button_unchecked),
                  )
                : _fromOmr[q]
                    ? (
                        AppColors.primary,
                        const StatusTag('OMR', AppColors.primary,
                            icon: Icons.document_scanner_outlined),
                      )
                    : (
                        AppColors.primary,
                        const StatusTag('উত্তর দেওয়া', AppColors.success,
                            icon: Icons.check_rounded),
                      );
    return QuestionCard(
      number: q + 1,
      title: widget.answerKey.questionTexts[q].trim(),
      accent: accent,
      tag: tag,
      highlighted: _needsCheck.contains(q),
      child: OptionGrid(
        texts: options,
        builder: (o) => OptionTile(
          label: OmrLayout.optionLabels[o],
          text: options[o].trim(),
          state: answer == o ? OptionState.selected : OptionState.idle,
          onTap: () => _select(q, o),
        ),
      ),
    );
  }

  Widget _emptyFilter() {
    final (icon, text) = _filter == _Filter.unanswered
        ? (Icons.celebration_outlined, 'সব প্রশ্নের উত্তর দেওয়া হয়েছে!')
        : (Icons.verified_outlined, 'যাচাই করার মতো কোনো প্রশ্ন নেই');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 56, color: AppColors.success),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _filter = _Filter.all),
            child: const Text('সব প্রশ্ন দেখুন'),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final progress = _count == 0 ? 0.0 : _answered / _count;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rollCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.15),
                    hintText: 'রোল নম্বর',
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    prefixIcon: const Icon(Icons.badge_outlined,
                        color: Colors.white, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (_scan?.setCode != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'সেট ${OmrLayout.optionLabels[_scan!.setCode!]}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${toBanglaDigits('$_answered')}/${toBanglaDigits('$_count')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('উত্তর দেওয়া হয়েছে',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 400),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _scanning ? null : _fillFromOmr,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(_scan == null
                  ? 'OMR শিট থেকে পূরণ করুন'
                  : 'আরেকটি OMR ছবি দিয়ে পূরণ করুন'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'নিচে নিজে উত্তর বেছে নিন, অথবা OMR শিট স্ক্যান করে সব উত্তর একসাথে বসান।',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final left = _count - _answered;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: left == 0
                    ? null
                    : () {
                        setState(() => _filter = _Filter.unanswered);
                        _scroll.animateTo(0,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOut);
                      },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: (left == 0 ? AppColors.success : AppColors.warning)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        toBanglaDigits('$left'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: left == 0
                              ? AppColors.success
                              : const Color(0xFFB45309),
                        ),
                      ),
                      Text(
                        left == 0 ? 'সব শেষ' : 'বাকি',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('সাবমিট করুন'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned bar with filter pills and a strip of question numbers, coloured by
/// status, that jump to their question.
class _QuestionMapDelegate extends SliverPersistentHeaderDelegate {
  final int count;
  final _Filter filter;
  final bool Function(int) answered;
  final Set<int> needsCheck;
  final List<int?> answers;
  final int unansweredCount;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<int> onTapQuestion;

  _QuestionMapDelegate({
    required this.count,
    required this.filter,
    required this.answered,
    required this.needsCheck,
    required this.answers,
    required this.unansweredCount,
    required this.onFilter,
    required this.onTapQuestion,
  });

  @override
  double get minExtent => _mapHeight;

  @override
  double get maxExtent => _mapHeight;

  @override
  bool shouldRebuild(covariant _QuestionMapDelegate oldDelegate) => true;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 6, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterPill(
                  label: 'সব ${toBanglaDigits('$count')}',
                  selected: filter == _Filter.all,
                  color: AppColors.primary,
                  onTap: () => onFilter(_Filter.all),
                ),
                _FilterPill(
                  label: 'বাকি ${toBanglaDigits('$unansweredCount')}',
                  selected: filter == _Filter.unanswered,
                  color: const Color(0xFFB45309),
                  onTap: () => onFilter(_Filter.unanswered),
                ),
                if (needsCheck.isNotEmpty)
                  _FilterPill(
                    label: 'যাচাই ${toBanglaDigits('${needsCheck.length}')}',
                    selected: filter == _Filter.check,
                    color: AppColors.warning,
                    onTap: () => onFilter(_Filter.check),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, q) {
                final done = answered(q);
                final doubleMark = answers[q] == multipleMarks;
                final check = needsCheck.contains(q);
                final Color border = doubleMark
                    ? AppColors.danger
                    : check
                        ? AppColors.warning
                        : done
                            ? Colors.transparent
                            : AppColors.border;
                return InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onTapQuestion(q),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: done && !check ? AppColors.headerGradient : null,
                      color: done && !check
                          ? null
                          : check
                              ? AppColors.warning.withValues(alpha: 0.12)
                              : Colors.white,
                      border: Border.all(color: border, width: 1.6),
                    ),
                    child: Text(
                      toBanglaDigits('${q + 1}'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: done && !check
                            ? Colors.white
                            : doubleMark
                                ? AppColors.danger
                                : AppColors.muted,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Content of the submit dialog: counts and the unanswered question numbers.
class _SubmitSummary extends StatelessWidget {
  final int answered;
  final List<int> unanswered;
  final int multiple;

  const _SubmitSummary({
    required this.answered,
    required this.unanswered,
    required this.multiple,
  });

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
        );

    const shown = 30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            stat(toBanglaDigits('$answered'), 'উত্তর দেওয়া', AppColors.success),
            const SizedBox(width: 8),
            stat(toBanglaDigits('${unanswered.length}'), 'বাকি',
                const Color(0xFFB45309)),
            if (multiple > 0) ...[
              const SizedBox(width: 8),
              stat(toBanglaDigits('$multiple'), 'একাধিক দাগ', AppColors.danger),
            ],
          ],
        ),
        if (unanswered.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('যে প্রশ্নগুলোর উত্তর বাকি',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in unanswered.take(shown))
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF2C46D)),
                    color: AppColors.warning.withValues(alpha: 0.08),
                  ),
                  child: Text(toBanglaDigits('${q + 1}'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309))),
                ),
              if (unanswered.length > shown)
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  child: Text(
                      '+${toBanglaDigits('${unanswered.length - shown}')}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    Widget tile(_PhotoSource source, IconData icon, Color color, String title,
        String sub) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.pop(context, source),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15.5)),
                        Text(sub,
                            style: const TextStyle(
                                color: AppColors.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.muted),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OMR শিটের ছবি নিন',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('চার কোণার কালো বর্গসহ পুরো শিট যেন ছবিতে থাকে',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            tile(_PhotoSource.camera, Icons.camera_alt_outlined,
                AppColors.primary, 'ক্যামেরা', 'এখনই শিটের ছবি তুলুন'),
            tile(_PhotoSource.gallery, Icons.photo_library_outlined,
                AppColors.brandGreen, 'গ্যালারি', 'ফোনে থাকা ছবি থেকে'),
            tile(_PhotoSource.files, Icons.folder_open_outlined,
                AppColors.primaryDark, 'ফাইল / ডাউনলোড',
                'Downloads, WhatsApp, Drive ইত্যাদি'),
          ],
        ),
      ),
    );
  }
}

class _ScanningOverlay extends StatelessWidget {
  const _ScanningOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          // Sits above the Scaffold, so it brings its own Material for text
          // styling.
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 18),
                  const Text('OMR শিট পড়া হচ্ছে...',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('একটু অপেক্ষা করুন',
                      style: TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
