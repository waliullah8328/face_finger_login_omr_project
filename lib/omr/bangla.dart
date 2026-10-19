const _banglaDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// Replaces ASCII digits with Bangla digits: "12.5" -> "১২.৫".
String toBanglaDigits(String input) => input.replaceAllMapped(
      RegExp(r'[0-9]'),
      (m) => _banglaDigits[int.parse(m[0]!)],
    );

/// Formats a mark like 35 or 35.75 without a trailing ".0", in Bangla digits.
String formatMarks(double value) {
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return toBanglaDigits(text);
}
