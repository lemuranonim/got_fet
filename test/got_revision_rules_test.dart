import 'package:flutter_test/flutter_test.dart';
import 'package:kroscek_got_fet/domain/got_revision_rules.dart';

void main() {
  group('GOT phase photo rules', () {
    test('Vegetative requires exactly two photos', () {
      expect(GotRevisionRules.requiredPhasePhotos('Vegetative'), 2);
      expect(GotRevisionRules.requiredPhasePhotos('Vegetatif'), 2);
    });

    test('Final Generative requires exactly six photos', () {
      expect(GotRevisionRules.requiredPhasePhotos('Final Generative'), 6);
    });
  });

  test('Off-Type samples are capped at six plants', () {
    expect(GotRevisionRules.requiredOffTypeSamples(0), 0);
    expect(GotRevisionRules.requiredOffTypeSamples(3), 3);
    expect(GotRevisionRules.requiredOffTypeSamples(6), 6);
    expect(GotRevisionRules.requiredOffTypeSamples(10), 6);
  });

  test('photo package labels and totals follow the observation phase', () {
    expect(GotRevisionRules.vegetativePhotoLabels, [
      'Tanaman vegetative / tunas',
      'Keseragaman / hamparan tanaman (landscape)',
    ]);
    expect(GotRevisionRules.generativePhotoLabels, [
      'Full tanaman',
      'Bunga jantan',
      'Tongkol & Silking',
      'Akar',
      'Daun',
      'Keseragaman / hamparan tanaman (landscape)',
    ]);
    expect(
      GotRevisionRules.requiredOffTypeSamples(10) *
          GotRevisionRules.requiredPhasePhotos('Vegetative'),
      12,
    );
    expect(
      GotRevisionRules.requiredOffTypeSamples(10) *
          GotRevisionRules.requiredPhasePhotos('Final Generative'),
      36,
    );
  });

  test('Village Coordinate accepts Indonesia bounds and rejects invalid data',
      () {
    expect(
      GotRevisionRules.isValidIndonesiaCoordinate(-7.637017, 112.8272303),
      isTrue,
    );
    expect(GotRevisionRules.isValidIndonesiaCoordinate(0, 0), isFalse);
    expect(GotRevisionRules.isValidIndonesiaCoordinate(40, 112), isFalse);
  });
}
