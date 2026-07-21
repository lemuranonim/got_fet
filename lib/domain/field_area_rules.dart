class FieldAreaRules {
  FieldAreaRules._();

  static double? parseHectares(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  static String inputValue(double? value) {
    if (value == null) return '';
    return value
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String display(double? value) {
    if (value == null) return '-';
    return '${inputValue(value)} ha';
  }
}
