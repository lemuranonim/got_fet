part of 'got_fet_screen.dart';

class _GotFetSample {
  final String lotId;
  final String sampleId;
  final String hybrid;
  final String crop;
  final String season;
  final String testType;
  final String pic;
  final DateTime dueDate;
  final List<_TrackingStep> steps;
  final String gender;
  final String typeSeed;
  final String category;
  final int cropYear;
  final String processStage;
  final String batch;
  final String noteSample;
  final int qtyByDss;
  final num? commercialQtyInventory;
  final String flagging;
  final String reasonTesting;
  final DateTime? deliveryDate1;
  final DateTime? deliveryDate2;
  DateTime? plantingDate;
  int? weekOfPlanting;
  DateTime? resultEstimation;
  int? weekOfResultEstimation;
  String noteTanam;
  String location;
  double? fieldArea;
  final String statusGot2;
  String statusSample;
  final String? vegetativeObservationNo;
  final String? finalObservationNo;
  final String payment;
  String status;

  _GotFetSample({
    required this.lotId,
    required this.sampleId,
    required this.hybrid,
    required this.crop,
    required this.season,
    required this.testType,
    required this.status,
    required this.pic,
    required this.dueDate,
    required this.steps,
    this.gender = '-',
    this.typeSeed = '-',
    this.category = '-',
    this.cropYear = 0,
    this.processStage = '-',
    this.batch = '-',
    this.noteSample = '-',
    this.qtyByDss = 0,
    this.commercialQtyInventory,
    this.flagging = '-',
    this.reasonTesting = '-',
    this.deliveryDate1,
    this.deliveryDate2,
    this.plantingDate,
    this.weekOfPlanting,
    this.resultEstimation,
    this.weekOfResultEstimation,
    this.noteTanam = '-',
    this.location = '-',
    this.fieldArea,
    this.statusGot2 = '-',
    this.statusSample = '-',
    this.vegetativeObservationNo,
    this.finalObservationNo,
    this.payment = '-',
  });

  bool get isOverdue {
    final today = DateTime.now();
    final currentDay = DateTime(today.year, today.month, today.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return dueDay.isBefore(currentDay) &&
        status != 'Approved' &&
        status != 'Completed';
  }
}

class _TrackingStep {
  final String label;
  final DateTime date;
  final bool done;

  const _TrackingStep(this.label, this.date, this.done);
}

class _ReviewTimelineEvent {
  final String label;
  final DateTime date;
  final bool done;
  final String? actor;
  final String? remarks;

  const _ReviewTimelineEvent({
    required this.label,
    required this.date,
    required this.done,
    this.actor,
    this.remarks,
  });
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricData(this.label, this.value, this.icon, this.color);
}

class _WorkflowStepData {
  final String label;
  final String detail;
  final IconData icon;
  final bool done;
  final bool active;

  const _WorkflowStepData({
    required this.label,
    required this.detail,
    required this.icon,
    required this.done,
    this.active = false,
  });
}

class _MenuAction {
  final String title;
  final String subtitle;
  final IconData icon;
  final _GotFetPage page;
  final String? logoAsset;

  const _MenuAction(
    this.title,
    this.subtitle,
    this.icon,
    this.page, {
    this.logoAsset,
  });
}

class _GotFetNavEntry {
  final _GotFetPage page;
  final _InspectionModule module;
  final int reviewSegment;
  final _GotObservationStage gotStage;
  final int selectedSampleIndex;

  const _GotFetNavEntry({
    required this.page,
    required this.module,
    required this.reviewSegment,
    required this.gotStage,
    required this.selectedSampleIndex,
  });
}

enum _GotEvidenceCategory {
  trueType,
  offType,
  selfing,
  male,
}

extension _GotEvidenceCategoryX on _GotEvidenceCategory {
  String get title {
    return switch (this) {
      _GotEvidenceCategory.trueType => 'TrueType',
      _GotEvidenceCategory.offType => 'OffType',
      _GotEvidenceCategory.selfing => 'Selfing',
      _GotEvidenceCategory.male => 'Male',
    };
  }

  String get key {
    return switch (this) {
      _GotEvidenceCategory.trueType => 'true_type',
      _GotEvidenceCategory.offType => 'off_type',
      _GotEvidenceCategory.selfing => 'selfing',
      _GotEvidenceCategory.male => 'male',
    };
  }

  String get prefix {
    return switch (this) {
      _GotEvidenceCategory.trueType => 'TT',
      _GotEvidenceCategory.offType => 'OT',
      _GotEvidenceCategory.selfing => 'SF',
      _GotEvidenceCategory.male => 'ML',
    };
  }

  IconData get icon {
    return switch (this) {
      _GotEvidenceCategory.trueType => Icons.check_circle_rounded,
      _GotEvidenceCategory.offType => Icons.warning_rounded,
      _GotEvidenceCategory.selfing => Icons.spa_rounded,
      _GotEvidenceCategory.male => Icons.male_rounded,
    };
  }
}

class _GotEvidenceSlot {
  final _GotEvidenceCategory category;
  final int rcvNo;

  const _GotEvidenceSlot({
    required this.category,
    required this.rcvNo,
  });

  String get label => '${category.prefix} $rcvNo';

  String get key => '${category.key}-$rcvNo';
}

class _GotEvidencePhoto {
  final String categoryKey;
  final int rcvNo;
  final String rcvLabel;
  final String photoUrl;
  final String uploadedBy;
  final DateTime? uploadedAt;

  const _GotEvidencePhoto({
    required this.categoryKey,
    required this.rcvNo,
    required this.rcvLabel,
    required this.photoUrl,
    required this.uploadedBy,
    required this.uploadedAt,
  });

  String get slotKey => '$categoryKey-$rcvNo';
}

class _FetObservationResult {
  final String lotId;
  final String sampleId;
  final String plotId;
  final int replication;
  final int dap;
  final int totalPoints;
  final int grownCount;
  final int notGrownCount;
  final int reviewCount;
  final int notReadableCount;
  final double emergencePercent;
  final String? plotPhotoUrl;
  final String submittedBy;
  final DateTime? submittedAt;
  final List<_FetPointStatus> pointStatuses;

  const _FetObservationResult({
    required this.lotId,
    required this.sampleId,
    required this.plotId,
    required this.replication,
    required this.dap,
    required this.totalPoints,
    required this.grownCount,
    required this.notGrownCount,
    required this.reviewCount,
    required this.notReadableCount,
    required this.emergencePercent,
    required this.plotPhotoUrl,
    required this.submittedBy,
    required this.submittedAt,
    required this.pointStatuses,
  });
}
