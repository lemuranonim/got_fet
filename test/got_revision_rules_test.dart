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

  group('multi-feature workflow safety', () {
    test('explicit workflow stages have a stable order', () {
      expect(GotRevisionRules.workflowStageRank('Received'), 0);
      expect(GotRevisionRules.workflowStageRank('Ready to Plant'), 1);
      expect(GotRevisionRules.workflowStageRank('To Obs. Veg'), 2);
      expect(GotRevisionRules.workflowStageRank('To Obs. Gen'), 3);
      expect(GotRevisionRules.workflowStageRank('Waiting Review'), 4);
      expect(GotRevisionRules.workflowStageRank('Confirmed'), 5);
    });

    test('planting correction never regresses an advanced workflow', () {
      expect(
        GotRevisionRules.workflowStatusAfterPlantingSave('Ready to Plant'),
        'To Obs. Veg',
      );
      expect(
        GotRevisionRules.workflowStatusAfterPlantingSave('Waiting Review'),
        'Waiting Review',
      );
      expect(
        GotRevisionRules.workflowStatusAfterPlantingSave('Confirmed'),
        'Confirmed',
      );
    });

    test('earlier observation correction preserves a later workflow', () {
      expect(
        GotRevisionRules.workflowStatusAfterObservationSubmit(
          currentStatus: 'Waiting Review',
          vegetative: true,
        ),
        'Waiting Review',
      );
      expect(
        GotRevisionRules.workflowStatusAfterObservationSubmit(
          currentStatus: 'To Obs. Gen',
          vegetative: false,
        ),
        'Waiting Review',
      );
    });
  });
}
