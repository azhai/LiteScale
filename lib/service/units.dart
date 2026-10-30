/// Weight unit conversion. Everything is stored in kilograms; conversion only
/// happens at the display / entry boundary.
class Units {
  static const double kgPerLb = 0.45359237;
  static const double kgPerStone = 6.35029318;
  static const double lbPerKg = 2.20462262185;

  static const List<String> all = <String>['jin', 'kg', 'lb', 'st'];

  static double toDisplay(double kg, String unit) {
    switch (unit) {
      case 'lb':
        return kg * lbPerKg;
      case 'jin':
        return kg * 2;
      case 'st':
        return kg / kgPerStone;
      default:
        return kg;
    }
  }

  static double fromDisplay(double value, String unit) {
    switch (unit) {
      case 'lb':
        return value * kgPerLb;
      case 'jin':
        return value / 2;
      case 'st':
        return value * kgPerStone;
      default:
        return value;
    }
  }

  static String label(String unit, bool isZh) {
    switch (unit) {
      case 'lb':
        return 'lb';
      case 'jin':
        return isZh ? '斤' : 'jin';
      case 'st':
        return 'st';
      default:
        return 'kg';
    }
  }

  /// 1 decimal for kg/lb/jin, 2 for stones.
  static String format(double kg, String unit, {bool isZh = false}) {
    final double v = toDisplay(kg, unit);
    final String digits = unit == 'st' ? '2' : '1';
    return '${v.toStringAsFixed(int.parse(digits))} ${label(unit, isZh)}';
  }

  /// Detailed form for stone/pound, e.g. "10 st 8.0 lb".
  static String formatDetailed(double kg, String unit, {bool isZh = false}) {
    if (unit != 'st') return format(kg, unit, isZh: isZh);
    final double totalLb = kg * lbPerKg;
    final int stones = totalLb ~/ 14;
    final double pounds = totalLb - stones * 14;
    return '$stones st ${pounds.toStringAsFixed(1)} lb';
  }
}
