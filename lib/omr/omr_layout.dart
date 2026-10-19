/// Geometry of the Biddabari OMR sheet.
///
/// Everything is expressed in "sheet units": the sheet is [width] x [height]
/// units (A4 ratio). The printable sheet painter and the reader both use this
/// single source of truth, so a bubble drawn at a position is exactly where
/// the reader looks for it.
class Pt {
  final double x;
  final double y;

  const Pt(this.x, this.y);

  @override
  String toString() => 'Pt(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

class OmrLayout {
  OmrLayout._();

  static const double width = 1000;
  static const double height = 1414;

  // Four solid squares near the corners, used to locate and un-warp the sheet.
  // Order: top-left, top-right, bottom-right, bottom-left (clockwise).
  static const double markerSize = 40;
  static const List<Pt> markers = [
    Pt(50, 50),
    Pt(950, 50),
    Pt(950, 1364),
    Pt(50, 1364),
  ];

  // A small square right of the top-left marker. It tells the reader which
  // corner is "top-left", so upside-down or sideways photos still work.
  static const Pt orientationSpot = Pt(102, 50);
  static const double orientationSpotSize = 20;

  // Answer grid: 100 questions, 4 columns x 25 rows, 4 options each.
  static const int maxQuestions = 100;
  static const int optionCount = 4;
  static const int rowsPerColumn = 25;
  static const int columnCount = maxQuestions ~/ rowsPerColumn;
  static const List<String> optionLabels = ['ক', 'খ', 'গ', 'ঘ'];

  static const double answerRadius = 12;
  static const double answerTop = 528;
  static const double answerRowGap = 31.5;
  static const double columnLeft = 78;
  static const double columnGap = 220;
  static const double firstOptionOffset = 62;
  static const double optionGap = 38;

  static double columnX(int column) => columnLeft + column * columnGap;

  static double rowY(int row) => answerTop + row * answerRowGap;

  static Pt answerBubble(int question, int option) {
    final column = question ~/ rowsPerColumn;
    final row = question % rowsPerColumn;
    return Pt(
      columnX(column) + firstOptionOffset + option * optionGap,
      rowY(row),
    );
  }

  // Header: roll number (6 digit columns, 0-9) and set code (ক-ঘ).
  static const int rollDigits = 6;
  static const double headerRadius = 10;
  static const double headerTop = 212;
  static const double headerRowGap = 25;
  static const double rollLeft = 102;
  static const double rollGap = 34;
  static const double setX = 392;

  static Pt rollBubble(int digitColumn, int digit) =>
      Pt(rollLeft + digitColumn * rollGap, headerTop + digit * headerRowGap);

  static Pt setBubble(int option) =>
      Pt(setX, headerTop + option * headerRowGap);
}
