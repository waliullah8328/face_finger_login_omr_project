import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'omr_layout.dart';
import 'omr_reader.dart';

/// The question set of one exam: question and option texts, correct answers
/// and marking scheme.
class AnswerKey {
  final int questionCount;

  /// Correct option per question; `null` means not set (question is skipped
  /// when scoring).
  final List<int?> answers;

  /// Question text per question; empty when the teacher only set the answer.
  final List<String> questionTexts;

  /// Option texts per question ([OmrLayout.optionCount] each, may be empty).
  final List<List<String>> optionTexts;

  /// Explanation of the answer per question, shown with the result; empty
  /// when none was written.
  final List<String> explanations;

  final double markPerCorrect;
  final double negativeMark;

  AnswerKey({
    required this.questionCount,
    required List<int?> answers,
    List<String> questionTexts = const [],
    List<List<String>> optionTexts = const [],
    List<String> explanations = const [],
    this.markPerCorrect = 1,
    this.negativeMark = 0.25,
  })  : answers = List<int?>.generate(
          questionCount,
          (i) => i < answers.length ? answers[i] : null,
        ),
        questionTexts = List<String>.generate(
          questionCount,
          (i) => i < questionTexts.length ? questionTexts[i] : '',
        ),
        optionTexts = List<List<String>>.generate(
          questionCount,
          (i) => List<String>.generate(
            OmrLayout.optionCount,
            (o) => i < optionTexts.length && o < optionTexts[i].length
                ? optionTexts[i][o]
                : '',
          ),
        ),
        explanations = List<String>.generate(
          questionCount,
          (i) => i < explanations.length ? explanations[i] : '',
        );

  factory AnswerKey.empty([int questionCount = 50]) =>
      AnswerKey(questionCount: questionCount, answers: const []);

  bool get isComplete => answers.every((a) => a != null);

  /// Question text, or a generic title when none was written.
  String questionTitle(int q) =>
      questionTexts[q].trim().isEmpty ? 'প্রশ্ন' : questionTexts[q].trim();

  /// "ক. option text", or just "ক" when the option has no text.
  String optionTitle(int q, int o) {
    final text = optionTexts[q][o].trim();
    final label = OmrLayout.optionLabels[o];
    return text.isEmpty ? label : '$label. $text';
  }

  /// Scores the detected answers ([OmrScanResult.answers], possibly corrected
  /// by hand).
  ScoreReport score(List<int?> given) {
    var correct = 0, wrong = 0, blank = 0, multiple = 0;
    final status = <QuestionStatus>[];
    for (var q = 0; q < questionCount; q++) {
      final mark = q < given.length ? given[q] : null;
      final QuestionStatus s;
      if (answers[q] == null) {
        s = QuestionStatus.noKey;
      } else if (mark == null) {
        s = QuestionStatus.blank;
        blank++;
      } else if (mark == multipleMarks) {
        // Multiple marks count as a wrong answer, as on standard OMR exams.
        s = QuestionStatus.multiple;
        multiple++;
      } else if (mark == answers[q]) {
        s = QuestionStatus.correct;
        correct++;
      } else {
        s = QuestionStatus.wrong;
        wrong++;
      }
      status.add(s);
    }
    final total =
        correct * markPerCorrect - (wrong + multiple) * negativeMark;
    return ScoreReport(
      correct: correct,
      wrong: wrong,
      blank: blank,
      multiple: multiple,
      total: total,
      maxMarks: answers.where((a) => a != null).length * markPerCorrect,
      status: status,
    );
  }

  Map<String, dynamic> toJson() => {
        'questionCount': questionCount,
        'answers': answers,
        'questionTexts': questionTexts,
        'optionTexts': optionTexts,
        'explanations': explanations,
        'markPerCorrect': markPerCorrect,
        'negativeMark': negativeMark,
      };

  factory AnswerKey.fromJson(Map<String, dynamic> json) => AnswerKey(
        questionCount: (json['questionCount'] as int)
            .clamp(1, OmrLayout.maxQuestions),
        answers: (json['answers'] as List).cast<int?>(),
        // Absent in keys saved before question texts existed.
        questionTexts:
            (json['questionTexts'] as List? ?? const []).cast<String>(),
        optionTexts: [
          for (final row in json['optionTexts'] as List? ?? const [])
            (row as List).cast<String>(),
        ],
        // Absent in keys saved before explanations existed.
        explanations:
            (json['explanations'] as List? ?? const []).cast<String>(),
        markPerCorrect: (json['markPerCorrect'] as num).toDouble(),
        negativeMark: (json['negativeMark'] as num).toDouble(),
      );

  static const _prefsKey = 'omr_answer_key';

  static Future<AnswerKey> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return AnswerKey.empty();
    try {
      return AnswerKey.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AnswerKey.empty();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(toJson()));
  }
}

enum QuestionStatus { correct, wrong, blank, multiple, noKey }

class ScoreReport {
  final int correct;
  final int wrong;
  final int blank;
  final int multiple;
  final double total;
  final double maxMarks;
  final List<QuestionStatus> status;

  const ScoreReport({
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.multiple,
    required this.total,
    required this.maxMarks,
    required this.status,
  });
}
