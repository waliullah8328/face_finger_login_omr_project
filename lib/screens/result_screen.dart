import 'package:flutter/material.dart';

import '../omr/answer_key.dart';
import '../omr/bangla.dart';
import '../omr/omr_layout.dart';
import '../omr/omr_reader.dart';
import '../theme.dart';
import '../widgets/option_tile.dart';
import '../widgets/question_card.dart';
import 'answer_sheet_screen.dart';

/// Opens the scanned photo with the detection overlay, zoomable.
void showScanImage(BuildContext context, OmrScanResult scan) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('স্ক্যান করা ছবি'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          titleTextStyle: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'সবুজ = ভরাট পাওয়া গেছে, লাল = একাধিক দাগ, কমলা = অস্পষ্ট',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(child: Image.memory(scan.annotatedImage)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _Filter { all, correct, wrong, blank }

/// Final marks after the answer sheet was submitted.
class ResultScreen extends StatefulWidget {
  final AnswerKey answerKey;
  final List<int?> answers;
  final String roll;
  final int? setCode;
  final OmrScanResult? scan;

  const ResultScreen({
    super.key,
    required this.answerKey,
    required this.answers,
    required this.roll,
    this.setCode,
    this.scan,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final ScoreReport _report = widget.answerKey.score(widget.answers);
  _Filter _filter = _Filter.all;

  bool _matches(QuestionStatus s) => switch (_filter) {
        _Filter.all => true,
        _Filter.correct => s == QuestionStatus.correct,
        _Filter.wrong =>
          s == QuestionStatus.wrong || s == QuestionStatus.multiple,
        _Filter.blank => s == QuestionStatus.blank,
      };

  void _nextSheet() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => AnswerSheetScreen(answerKey: widget.answerKey),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (var q = 0; q < widget.answerKey.questionCount; q++)
        if (_matches(_report.status[q])) q,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ফলাফল'),
        actions: [
          if (widget.scan != null)
            IconButton(
              tooltip: 'স্ক্যান করা ছবি',
              icon: const Icon(Icons.image_outlined),
              onPressed: () => showScanImage(context, widget.scan!),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _scoreHeader()),
          SliverToBoxAdapter(child: _stats()),
          SliverToBoxAdapter(child: _filters()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: visible.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('এই তালিকায় কোনো প্রশ্ন নেই',
                            style: TextStyle(color: AppColors.muted)),
                      ),
                    ),
                  )
                : SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) => _AnswerCard(
                      answerKey: widget.answerKey,
                      question: visible[i],
                      given: widget.answers[visible[i]],
                      status: _report.status[visible[i]],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('সংশোধন'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _nextSheet,
                    icon: const Icon(Icons.add_task),
                    label: const Text('পরের উত্তরপত্র'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scoreHeader() {
    final r = _report;
    final ratio = r.maxMarks == 0 ? 0.0 : (r.total / r.maxMarks).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.all(20),
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
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: value,
                    strokeWidth: 11,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                  Center(
                    child: Text(
                      '${toBanglaDigits('$percent')}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('প্রাপ্ত নম্বর',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85))),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: formatMarks(r.total),
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: ' / ${formatMarks(r.maxMarks)}',
                      style: TextStyle(
                          fontSize: 18,
                          color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ]),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _GlassPill(widget.roll.isEmpty
                        ? 'রোল: —'
                        : 'রোল: ${toBanglaDigits(widget.roll)}'),
                    if (widget.setCode != null)
                      _GlassPill(
                          'সেট: ${OmrLayout.optionLabels[widget.setCode!]}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final r = _report;
    Widget tile(String label, int count, Color color, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(toBanglaDigits('$count'),
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          tile('সঠিক', r.correct, AppColors.success, Icons.check_circle),
          const SizedBox(width: 8),
          tile('ভুল', r.wrong, AppColors.danger, Icons.cancel),
          const SizedBox(width: 8),
          tile('ফাঁকা', r.blank, AppColors.muted, Icons.remove_circle_outline),
          const SizedBox(width: 8),
          tile('একাধিক', r.multiple, AppColors.warning, Icons.error_outline),
        ],
      ),
    );
  }

  Widget _filters() {
    const labels = {
      _Filter.all: 'সব',
      _Filter.correct: 'সঠিক',
      _Filter.wrong: 'ভুল',
      _Filter.blank: 'ফাঁকা',
    };
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labels[f]!),
                selected: _filter == f,
                showCheckmark: false,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: _filter == f ? Colors.white : AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                      color: _filter == f
                          ? AppColors.primary
                          : AppColors.border),
                ),
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final String text;

  const _GlassPill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final AnswerKey answerKey;
  final int question;
  final int? given;
  final QuestionStatus status;

  const _AnswerCard({
    required this.answerKey,
    required this.question,
    required this.given,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      QuestionStatus.correct => ('সঠিক', AppColors.success),
      QuestionStatus.wrong => ('ভুল', AppColors.danger),
      QuestionStatus.multiple => ('একাধিক দাগ', AppColors.warning),
      QuestionStatus.blank => ('ফাঁকা', AppColors.muted),
      QuestionStatus.noKey => ('উত্তর সেট নেই', AppColors.muted),
    };
    final icon = switch (status) {
      QuestionStatus.correct => Icons.check_rounded,
      QuestionStatus.wrong => Icons.close_rounded,
      QuestionStatus.multiple => Icons.error_outline,
      _ => Icons.radio_button_unchecked,
    };
    final correct = answerKey.answers[question];
    final options = answerKey.optionTexts[question];
    final explanation = answerKey.explanations[question].trim();

    return QuestionCard(
      number: question + 1,
      title: answerKey.questionTexts[question].trim(),
      accent: color,
      tag: StatusTag(label, color, icon: icon),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OptionGrid(
            texts: options,
            builder: (o) => OptionTile(
              label: OmrLayout.optionLabels[o],
              text: options[o].trim(),
              state: o == given
                  ? (o == correct ? OptionState.correct : OptionState.wrong)
                  : o == correct
                      ? OptionState.missedCorrect
                      : OptionState.idle,
            ),
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 14),
            _ExplanationBox(text: explanation, correct: correct),
          ],
        ],
      ),
    );
  }
}

/// The teacher's explanation under a question's options: a soft brand-tinted
/// panel with a lightbulb badge, the correct option, and the text.
class _ExplanationBox extends StatelessWidget {
  final String text;
  final int? correct;

  const _ExplanationBox({required this.text, required this.correct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.07),
            AppColors.primaryDark.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: AppColors.headerGradient,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.lightbulb_rounded,
                    size: 17, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'ব্যাখ্যা',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (correct != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'সঠিক উত্তর: ${OmrLayout.optionLabels[correct!]}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
