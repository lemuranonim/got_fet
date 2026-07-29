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

  static String normalizeWorkflowStatus(String status) {
    return status
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static int workflowStageRank(String status) {
    final normalized = normalizeWorkflowStatus(status);
    if (normalized.contains('confirmed') ||
        normalized.contains('approved') ||
        normalized.contains('completed') ||
        normalized.contains('selesai')) {
      return 5;
    }
    if (normalized.contains('waiting review') ||
        normalized.contains('generative submitted') ||
        normalized.contains('generatif submitted') ||
        normalized.contains('final generative')) {
      return 4;
    }
    if (normalized.contains('to obs gen') ||
        normalized.contains('vegetative submitted') ||
        normalized.contains('vegetatif submitted')) {
      return 3;
    }
    if (normalized.contains('ready to plant') ||
        normalized.contains('siap tanam')) {
      return 1;
    }
    if (normalized.contains('to obs veg') ||
        normalized.contains('planted') ||
        normalized.contains('tanam')) {
      return 2;
    }
    if (normalized.contains('received') || normalized.contains('diterima')) {
      return 0;
    }
    return -1;
  }

  static String workflowStatusAfterPlantingSave(String currentStatus) {
    return workflowStageRank(currentStatus) > 2 ? currentStatus : 'To Obs. Veg';
  }

  static String workflowStatusAfterObservationSubmit({
    required String currentStatus,
    required bool vegetative,
  }) {
    final targetStatus = vegetative ? 'To Obs. Gen' : 'Waiting Review';
    final targetRank = vegetative ? 3 : 4;
    return workflowStageRank(currentStatus) > targetRank
        ? currentStatus
        : targetStatus;
  }
}
