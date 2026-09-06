class GotRevisionRules {
  GotRevisionRules._();

  static const parentSeedPurityClass = 'PS';
  static const commercialPurityClass = 'Komersil';
  static const purityClasses = [
    parentSeedPurityClass,
    commercialPurityClass,
  ];

  static const parentSeedPurityThreshold = 99.5;
  static const commercialPurityThreshold = 95.0;

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

  static double purityThreshold(String purityClass) {
    return purityClass.trim().toLowerCase() ==
            parentSeedPurityClass.toLowerCase()
        ? parentSeedPurityThreshold
        : commercialPurityThreshold;
  }

  static int classifiedIssueCount({
    required int offTypeCount,
    required int selfingCount,
    required int maleCount,
    required int suspiciousCount,
  }) {
    return offTypeCount + selfingCount + maleCount + suspiciousCount;
  }

  static int trueTypeCount({
    required int totalObserved,
    required int offTypeCount,
    required int selfingCount,
    required int maleCount,
    required int suspiciousCount,
  }) {
    final issues = classifiedIssueCount(
      offTypeCount: offTypeCount,
      selfingCount: selfingCount,
      maleCount: maleCount,
      suspiciousCount: suspiciousCount,
    );
    return (totalObserved - issues).clamp(0, totalObserved);
  }

  static double percentage(int count, int totalObserved) {
    if (totalObserved <= 0) return 0;
    return count / totalObserved * 100;
  }

  static double totalPercentage({
    required int totalObserved,
    required int trueTypeCount,
    required int offTypeCount,
    required int selfingCount,
    required int maleCount,
    required int suspiciousCount,
  }) {
    return percentage(
      trueTypeCount + offTypeCount + selfingCount + maleCount + suspiciousCount,
      totalObserved,
    );
  }

  static const offTypeCharacterizationGroups = [
    GotOffTypeCharacterizationGroup(
      photoLabel: 'Full tanaman',
      fields: [
        GotOffTypeCharacterizationField(
          key: 'stem_anthocyanin_pigmentation',
          label: 'Stem anthocyanin pigmentation',
        ),
        GotOffTypeCharacterizationField(
          key: 'branch_attitude',
          label: 'Branch attitude',
        ),
      ],
    ),
    GotOffTypeCharacterizationGroup(
      photoLabel: 'Bunga jantan',
      fields: [
        GotOffTypeCharacterizationField(
          key: 'tassel_type',
          label: 'Tassel type',
        ),
        GotOffTypeCharacterizationField(
          key: 'anther_color',
          label: 'Anther colour',
        ),
        GotOffTypeCharacterizationField(
          key: 'glume_color',
          label: 'Glume colour',
        ),
      ],
    ),
    GotOffTypeCharacterizationGroup(
      photoLabel: 'Tongkol & Silking',
      fields: [
        GotOffTypeCharacterizationField(
          key: 'ear_at_silk_emergence_color',
          label: 'Ear at silk emergence color',
        ),
      ],
    ),
    GotOffTypeCharacterizationGroup(
      photoLabel: 'Akar',
      fields: [
        GotOffTypeCharacterizationField(
          key: 'brace_root_anthocyanin_pigmentation',
          label: 'Anthocyanin pigmentation at brace/root',
        ),
        GotOffTypeCharacterizationField(
          key: 'brace_root_color',
          label: 'Brace root colour (warna akar udara)',
        ),
      ],
    ),
    GotOffTypeCharacterizationGroup(
      photoLabel: 'Daun',
      fields: [
        GotOffTypeCharacterizationField(
          key: 'leaf_edge_color',
          label: 'Leaf edge colour (warna tepian daun)',
        ),
      ],
    ),
    GotOffTypeCharacterizationGroup(
      photoLabel: 'Keseragaman / hamparan tanaman (landscape)',
      fields: [
        GotOffTypeCharacterizationField(
          key: 'tassel_breaking_time',
          label: 'Tassel breaking time',
        ),
        GotOffTypeCharacterizationField(
          key: 'silking_50_days',
          label: '50% silking (days)',
        ),
        GotOffTypeCharacterizationField(
          key: 'silking_compared_to_true_type',
          label: 'Silking compared to truetype',
        ),
        GotOffTypeCharacterizationField(
          key: 'pollen_50_days',
          label: '50% pollen (days)',
        ),
        GotOffTypeCharacterizationField(
          key: 'pollen_compared_to_true_type',
          label: 'Pollen compared to truetype',
        ),
      ],
    ),
  ];

  static GotOffTypeCharacterizationGroup? characterizationGroupForPhoto(
    String stage,
    String photoLabel,
  ) {
    if (stage.trim().toLowerCase().contains('veget')) return null;
    for (final group in offTypeCharacterizationGroups) {
      if (group.photoLabel == photoLabel) return group;
    }
    return null;
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
    if (normalized.contains('request new sample') ||
        normalized.contains('sample request') ||
        normalized.contains('replacement sample') ||
        normalized.contains('resampling')) {
      return 6;
    }
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

class GotOffTypeCharacterizationGroup {
  final String photoLabel;
  final List<GotOffTypeCharacterizationField> fields;

  const GotOffTypeCharacterizationGroup({
    required this.photoLabel,
    required this.fields,
  });
}

class GotOffTypeCharacterizationField {
  final String key;
  final String label;

  const GotOffTypeCharacterizationField({
    required this.key,
    required this.label,
  });
}
