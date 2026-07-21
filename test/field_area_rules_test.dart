import 'package:flutter_test/flutter_test.dart';
import 'package:kroscek_got_fet/domain/field_area_rules.dart';

void main() {
  group('FieldAreaRules.parseHectares', () {
    test('menerima desimal dengan titik atau koma', () {
      expect(FieldAreaRules.parseHectares('0.009'), 0.009);
      expect(FieldAreaRules.parseHectares('0,0125'), 0.0125);
      expect(FieldAreaRules.parseHectares(' 1,25 '), 1.25);
    });

    test('menolak input kosong, bukan angka, nol, dan negatif', () {
      expect(FieldAreaRules.parseHectares(''), isNull);
      expect(FieldAreaRules.parseHectares('luas'), isNull);
      expect(FieldAreaRules.parseHectares('0'), isNull);
      expect(FieldAreaRules.parseHectares('-0.01'), isNull);
    });
  });

  test('format input mempertahankan presisi dan membuang nol berlebih', () {
    expect(FieldAreaRules.inputValue(0.0125), '0.0125');
    expect(FieldAreaRules.inputValue(1.0), '1');
    expect(FieldAreaRules.display(0.009), '0.009 ha');
    expect(FieldAreaRules.display(null), '-');
  });
}
