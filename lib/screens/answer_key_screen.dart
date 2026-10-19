import 'package:flutter/material.dart';

import '../omr/answer_key.dart';
import '../omr/bangla.dart';
import '../omr/omr_layout.dart';

/// Lets the teacher write the question set: number of questions, marking
/// scheme, and for each question its text, options and the correct option.
/// Pops with the saved [AnswerKey].
class AnswerKeyScreen extends StatefulWidget {
  final AnswerKey initial;

  const AnswerKeyScreen({super.key, required this.initial});

  @override
  State<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends State<AnswerKeyScreen> {
  late int _count = widget.initial.questionCount;

  // Kept for all possible questions, so lowering and raising the question
  // count does not lose what was typed.
  late final List<int?> _answers = List<int?>.generate(
    OmrLayout.maxQuestions,
    (i) => i < widget.initial.questionCount ? widget.initial.answers[i] : null,
  );
  late final List<TextEditingController> _questionCtrls = List.generate(
    OmrLayout.maxQuestions,
    (i) => TextEditingController(
        text: i < widget.initial.questionCount
            ? widget.initial.questionTexts[i]
            : ''),
  );
  late final List<List<TextEditingController>> _optionCtrls = List.generate(
    OmrLayout.maxQuestions,
    (i) => List.generate(
      OmrLayout.optionCount,
      (o) => TextEditingController(
          text: i < widget.initial.questionCount
              ? widget.initial.optionTexts[i][o]
              : ''),
    ),
  );
  late final List<TextEditingController> _explanationCtrls = List.generate(
    OmrLayout.maxQuestions,
    (i) => TextEditingController(
        text: i < widget.initial.questionCount
            ? widget.initial.explanations[i]
            : ''),
  );
  late final _countCtrl = TextEditingController(text: '$_count');
  late final _markCtrl =
      TextEditingController(text: _plain(widget.initial.markPerCorrect));
  late final _negativeCtrl =
      TextEditingController(text: _plain(widget.initial.negativeMark));

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void dispose() {
    for (final c in [
      ..._questionCtrls,
      for (final row in _optionCtrls) ...row,
      ..._explanationCtrls,
      _countCtrl,
      _markCtrl,
      _negativeCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final mark = double.tryParse(_markCtrl.text.trim());
    final negative = double.tryParse(_negativeCtrl.text.trim());
    if (mark == null || mark <= 0 || negative == null || negative < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('নম্বর ও নেগেটিভ মার্ক সঠিকভাবে লিখুন।')));
      return;
    }
    final key = AnswerKey(
      questionCount: _count,
      answers: _answers.take(_count).toList(),
      questionTexts: [for (final c in _questionCtrls.take(_count)) c.text],
      optionTexts: [
        for (final row in _optionCtrls.take(_count)) [for (final c in row) c.text],
      ],
      explanations: [for (final c in _explanationCtrls.take(_count)) c.text],
      markPerCorrect: mark,
      negativeMark: negative,
    );
    await key.save();
    if (mounted) Navigator.pop(context, key);
  }

  void _setCount(String text) {
    final n = int.tryParse(text.trim());
    if (n == null) return;
    setState(() => _count = n.clamp(1, OmrLayout.maxQuestions));
  }

  void _clearAll() {
    setState(() {
      _answers.fillRange(0, OmrLayout.maxQuestions, null);
      for (final c in [
        ..._questionCtrls,
        for (final r in _optionCtrls) ...r,
        ..._explanationCtrls,
      ]) {
        c.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final missing = _answers.take(_count).where((a) => a == null).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('প্রশ্ন সেট'),
        actions: [
          IconButton(
            tooltip: 'সব মুছুন',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _count + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _settings(context, missing);
          final q = i - 1;
          return _QuestionEditor(
            number: q + 1,
            correct: _answers[q],
            questionCtrl: _questionCtrls[q],
            optionCtrls: _optionCtrls[q],
            explanationCtrl: _explanationCtrls[q],
            onCorrect: (o) => setState(
                () => _answers[q] = _answers[q] == o ? null : o),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('সংরক্ষণ করুন'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ),
      ),
    );
  }

  Widget _settings(BuildContext context, int missing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _countCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'প্রশ্ন (১-১০০)',
                      border: OutlineInputBorder()),
                  onChanged: _setCount,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _markCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'সঠিকে নম্বর', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _negativeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'ভুলে কাটা', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            missing == 0
                ? 'সব প্রশ্নের সঠিক উত্তর দেওয়া হয়েছে'
                : '${toBanglaDigits('$missing')} টি প্রশ্নের সঠিক উত্তর বাকি '
                    '(অপশনের বাম পাশের বৃত্তে ট্যাপ করুন)',
            style: TextStyle(
                color: missing == 0
                    ? Colors.green
                    : Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  final int number;
  final int? correct;
  final TextEditingController questionCtrl;
  final List<TextEditingController> optionCtrls;
  final TextEditingController explanationCtrl;
  final ValueChanged<int> onCorrect;

  const _QuestionEditor({
    required this.number,
    required this.correct,
    required this.questionCtrl,
    required this.optionCtrls,
    required this.explanationCtrl,
    required this.onCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: questionCtrl,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'প্রশ্ন ${toBanglaDigits('$number')}',
                hintText: 'প্রশ্ন লিখুন (ঐচ্ছিক)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            for (var o = 0; o < OmrLayout.optionCount; o++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onCorrect(o),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: correct == o
                            ? Colors.green
                            : scheme.surfaceContainerHighest,
                        child: Text(
                          OmrLayout.optionLabels[o],
                          style: TextStyle(
                            color: correct == o
                                ? Colors.white
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: optionCtrls[o],
                        decoration: InputDecoration(
                          hintText: 'অপশন ${OmrLayout.optionLabels[o]}',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: explanationCtrl,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'ব্যাখ্যা',
                hintText: 'উত্তরের ব্যাখ্যা লিখুন (ঐচ্ছিক)',
                prefixIcon: Icon(Icons.lightbulb_outline),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
