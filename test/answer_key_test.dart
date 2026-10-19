import 'package:flutter_test/flutter_test.dart';
import 'package:omr_project/omr/answer_key.dart';
import 'package:omr_project/omr/omr_reader.dart';

void main() {
  test('keys saved before question texts existed still load', () {
    final key = AnswerKey.fromJson({
      'questionCount': 3,
      'answers': [0, 1, null],
      'markPerCorrect': 1,
      'negativeMark': 0.25,
    });
    expect(key.questionTexts, ['', '', '']);
    expect(key.questionTitle(0), 'প্রশ্ন');
    expect(key.optionTitle(0, 1), 'খ');
  });

  test('question and option texts round-trip through JSON', () {
    final key = AnswerKey(
      questionCount: 2,
      answers: [2, 0],
      questionTexts: ['বাংলাদেশের রাজধানী?', ''],
      optionTexts: [
        ['চট্টগ্রাম', 'খুলনা', 'ঢাকা', 'সিলেট'],
      ],
    );
    final copy = AnswerKey.fromJson(key.toJson());
    expect(copy.questionTitle(0), 'বাংলাদেশের রাজধানী?');
    expect(copy.optionTitle(0, 2), 'গ. ঢাকা');
    expect(copy.optionTitle(1, 0), 'ক');
  });

  test('scores correct, wrong, blank and multiple marks', () {
    final key = AnswerKey(
      questionCount: 4,
      answers: [0, 1, 2, 3],
      markPerCorrect: 1,
      negativeMark: 0.25,
    );
    final report = key.score([0, 2, null, multipleMarks]);
    expect(report.correct, 1);
    expect(report.wrong, 1);
    expect(report.blank, 1);
    expect(report.multiple, 1);
    expect(report.total, 0.5);
  });
}
