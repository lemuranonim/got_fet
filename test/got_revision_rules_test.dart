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

  test('Off-Type documentation follows distinct characters, not finding total',
      () {
    expect(
      GotRevisionRules.offTypeDocumentationReady(
        findingCount: 0,
        documentedCharacterCount: 0,
        allPhotoPackagesComplete: true,
      ),
      isTrue,
    );
    expect(
      GotRevisionRules.offTypeDocumentationReady(
        findingCount: 4,
        documentedCharacterCount: 2,
        allPhotoPackagesComplete: true,
      ),
      isTrue,
    );
    expect(
      GotRevisionRules.offTypeDocumentationReady(
        findingCount: 10,
        documentedCharacterCount: 0,
        allPhotoPackagesComplete: true,
      ),
      isFalse,
    );
    expect(
      GotRevisionRules.offTypeDocumentationReady(
        findingCount: 4,
        documentedCharacterCount: 2,
        allPhotoPackagesComplete: false,
      ),
      isFalse,
    );
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
    expect(GotRevisionRules.vegetativeTrueTypePhotoLabels, [
      'Hamparan',
      'Tanaman utuh',
    ]);
    expect(GotRevisionRules.generativeTrueTypePhotoLabels, [
      'Hamparan',
      'Tanaman utuh',
      'Bunga jantan',
      'Tongkol & Silking',
      'Akar',
      'Daun',
    ]);
    expect(
      GotRevisionRules.trueTypePhotoLabels('Vegetative'),
      GotRevisionRules.vegetativeTrueTypePhotoLabels,
    );
    expect(
      GotRevisionRules.trueTypePhotoLabels('Final Generative'),
      GotRevisionRules.generativeTrueTypePhotoLabels,
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
