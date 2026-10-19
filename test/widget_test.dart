import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omr_project/auth/user_store.dart';
import 'package:omr_project/main.dart';
import 'package:omr_project/omr/answer_key.dart';
import 'package:omr_project/screens/answer_sheet_screen.dart';
import 'package:omr_project/theme.dart';
import 'package:omr_project/widgets/option_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('logged out: shows the face login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OmrApp());
    // The welcome screen animates forever, so pump instead of settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('মুখ দেখালেই লগইন'), findsOneWidget);
    expect(find.text('ফেস দিয়ে লগইন'), findsOneWidget);
    expect(find.text('নতুন অ্যাকাউন্ট খুলুন'), findsOneWidget);
    // No fingerprint account yet, so no fingerprint button.
    expect(find.byIcon(Icons.fingerprint_rounded), findsNothing);
  });

  testWidgets('logged in: home screen shows main actions and the user',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await UserStore.instance();
    final user = await store.register(
      name: 'রহিম',
      institution: '',
      faces: [List<double>.filled(192, 0.07)],
    );
    await store.login(user);

    await tester.pumpWidget(const OmrApp());
    await tester.pumpAndSettle();

    expect(find.text('উত্তরপত্র খুলুন'), findsOneWidget);
    expect(find.text('প্রশ্ন সেট'), findsOneWidget);
    expect(find.text('খালি OMR শিট'), findsOneWidget);
    expect(find.text('স্বাগতম, রহিম'), findsOneWidget);
  });

  testWidgets('answer sheet starts empty, answers by hand, shows result',
      (tester) async {
    final key = AnswerKey(
      questionCount: 3,
      answers: [0, 1, 2],
      questionTexts: ['২ + ২ = ?', '৩ + ৩ = ?', '৪ + ৪ = ?'],
      optionTexts: [
        ['৪', '৫', '৬', '৭'],
        ['৫', '৬', '৭', '৮'],
        ['৬', '৭', '৮', '৯'],
      ],
      explanations: ['২ আর ২ যোগ করলে ৪ হয়।'],
    );
    Finder bubble(String label) => find.descendant(
        of: find.byType(OptionTile), matching: find.text(label));
    // A tall phone screen, so all three questions are built.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: AnswerSheetScreen(answerKey: key),
    ));
    await tester.pumpAndSettle();

    expect(find.text('উত্তর দেওয়া হয়েছে'), findsOneWidget);
    expect(find.text('০/৩'), findsOneWidget);

    // Only the bubble selects; tapping the option text does nothing.
    await tester.tap(find.text('৪').first);
    await tester.pumpAndSettle();
    expect(find.text('০/৩'), findsOneWidget);

    // Q1 correct (ক), Q2 wrong (ক); Q3 left blank.
    await tester.tap(bubble('ক').first);
    await tester.tap(bubble('ক').at(1));
    await tester.pumpAndSettle();
    expect(find.text('২/৩'), findsOneWidget);

    await tester.tap(find.text('সাবমিট করুন'));
    await tester.pumpAndSettle();
    expect(find.text('সাবমিট করবেন?'), findsOneWidget);
    // Q3 is listed as unanswered.
    expect(find.text('যে প্রশ্নগুলোর উত্তর বাকি'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'সাবমিট'));
    await tester.pumpAndSettle();

    expect(find.text('ফলাফল'), findsOneWidget);
    // 1 correct - 1 wrong * 0.25 = 0.75 out of 3.
    expect(find.text('০.৭৫ / ৩', findRichText: true), findsOneWidget);

    // Only Q1 has an explanation.
    await tester.scrollUntilVisible(find.text('২ আর ২ যোগ করলে ৪ হয়।'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('ব্যাখ্যা'), findsOneWidget);
    expect(find.text('সঠিক উত্তর: ক'), findsOneWidget);
  });
}
