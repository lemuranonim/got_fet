class FetRevisionRules {
  FetRevisionRules._();

  static const observationDays = [7, 11];
  static const remarkOptions = ['Retest', 'Resampling', 'Done'];
  static const resultEstimationOffsetDays = 12;
  static const requiredObservationSlots = 4;

  static DateTime resultEstimation(DateTime plantingDate) {
    return plantingDate.add(const Duration(days: resultEstimationOffsetDays));
  }

  static String lotProgressStatus({
    required int completedSlots,
    required bool hasActionRequired,
  }) {
    final completed = completedSlots.clamp(0, requiredObservationSlots);
    if (hasActionRequired) return 'FET Action Required ($completed/4)';
    if (completed == requiredObservationSlots) {
      return 'FET Observation Complete';
    }
    return 'FET In Progress ($completed/4)';
  }

  static int slotKey({required int day, required int replication}) {
    if (!observationDays.contains(day)) {
      throw ArgumentError.value(
          day, 'day', 'Observasi FET harus Day 7 atau 11.');
    }
    if (replication < 1 || replication > 2) {
      throw ArgumentError.value(
          replication, 'replication', 'Ulangan FET harus 1 atau 2.');
    }
    return day * 10 + replication;
  }

  static List<String> watermarkLines({
    required String lotId,
    required int replication,
  }) {
    return ['Lot: $lotId', 'Ulangan: $replication'];
  }
}
