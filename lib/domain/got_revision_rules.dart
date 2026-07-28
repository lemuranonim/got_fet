class GotRevisionRules {
  GotRevisionRules._();

  static const vegetativeRequiredPhotos = 2;
  static const generativeRequiredPhotos = 6;

  static const vegetativePhotoLabels = [
    'Tanaman vegetative / tunas',
    'Keseragaman / hamparan tanaman (landscape)',
  ];

  static const generativePhotoLabels = [
    'Full tanaman',
    'Bunga jantan',
    'Tongkol & Silking',
    'Akar',
    'Daun',
    'Keseragaman / hamparan tanaman (landscape)',
  ];
  static const vegetativeTrueTypePhotoLabels = [
    'Hamparan',
    'Tanaman utuh',
  ];

  static const generativeTrueTypePhotoLabels = [
    'Hamparan',
    'Tanaman utuh',
    'Bunga jantan',
    'Tongkol & Silking',
    'Akar',
    'Daun',
  ];

  static int requiredPhasePhotos(String stage) {
    return offTypePhotoLabels(stage).length;
  }

  static List<String> trueTypePhotoLabels(String stage) {
    final normalized = stage.trim().toLowerCase();
    return normalized.contains('veget')
        ? vegetativeTrueTypePhotoLabels
        : generativeTrueTypePhotoLabels;
  }

  static List<String> offTypePhotoLabels(String stage) {
    final normalized = stage.trim().toLowerCase();
    return normalized.contains('veget')
        ? vegetativePhotoLabels
        : generativePhotoLabels;
  }

  static bool offTypeDocumentationReady({
    required int findingCount,
    required int documentedCharacterCount,
    required bool allPhotoPackagesComplete,
  }) {
    if (findingCount <= 0) return documentedCharacterCount == 0;
    return documentedCharacterCount > 0 && allPhotoPackagesComplete;
  }

  static bool isValidIndonesiaCoordinate(double latitude, double longitude) {
    return latitude >= -11 &&
        latitude <= 6 &&
        longitude >= 95 &&
        longitude <= 141 &&
        !(latitude == 0 && longitude == 0);
  }
}
