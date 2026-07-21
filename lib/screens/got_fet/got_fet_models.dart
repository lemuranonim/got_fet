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
  String village;
  String subDistrict;
  String district;
  double? latitude;
  double? longitude;
  double? fieldArea;
  final String statusGot2;
  final String statusGotVeg;
  final String finalStatusGot;
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
    this.village = '-',
    this.subDistrict = '-',
    this.district = '-',
    this.latitude,
    this.longitude,
    this.fieldArea,
    this.statusGot2 = '-',
    this.statusGotVeg = '-',
    this.finalStatusGot = '-',
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
  final String? offTypeDetailId;
  final String? customLabel;

  const _GotEvidenceSlot({
    required this.category,
    required this.rcvNo,
    this.offTypeDetailId,
    this.customLabel,
  });

  String get label =>
      customLabel ??
      (offTypeDetailId == null ? '${category.prefix} $rcvNo' : 'OTD $rcvNo');

  String get evidenceCategoryKey =>
      offTypeDetailId == null ? category.key : 'off_type_detail';

  String get key => offTypeDetailId == null
      ? '${category.key}-$rcvNo'
      : 'off_type_detail-$offTypeDetailId-$rcvNo';
}

class _GotEvidencePhoto {
  final String categoryKey;
  final int rcvNo;
  final String rcvLabel;
  final String photoUrl;
  final String uploadedBy;
  final DateTime? uploadedAt;
  final String? offTypeDetailId;

  const _GotEvidencePhoto({
    required this.categoryKey,
    required this.rcvNo,
    required this.rcvLabel,
    required this.photoUrl,
    required this.uploadedBy,
    required this.uploadedAt,
    this.offTypeDetailId,
  });

  String get slotKey => offTypeDetailId == null
      ? '$categoryKey-$rcvNo'
      : 'off_type_detail-$offTypeDetailId-$rcvNo';
}

class _VillageCoordinate {
  final String region;
  final String district;
  final String subDistrict;
  final String village;
  final double latitude;
  final double longitude;
  final int sourceCount;

  const _VillageCoordinate({
    required this.region,
    required this.district,
    required this.subDistrict,
    required this.village,
    required this.latitude,
    required this.longitude,
    required this.sourceCount,
  });

  String get key => [region, district, subDistrict, village]
      .map((part) => part.trim().toLowerCase())
      .join('|');

  String get locationLabel => [
        village,
        subDistrict,
        district,
      ].where((part) => part.trim().isNotEmpty && part != '-').join(', ');

  String get coordinateLabel =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

enum _GotOffTypeSimilarity {
  similarFiOrHybrid,
  notSimilarFiOrHybrid,
}

extension _GotOffTypeSimilarityX on _GotOffTypeSimilarity {
  String get label => switch (this) {
        _GotOffTypeSimilarity.similarFiOrHybrid =>
          'Mirip dengan FI / hybrid lain',
        _GotOffTypeSimilarity.notSimilarFiOrHybrid =>
          'Tidak mirip dengan FI / hybrid lain',
      };

  String get payload => switch (this) {
        _GotOffTypeSimilarity.similarFiOrHybrid => 'similar_fi_or_hybrid',
        _GotOffTypeSimilarity.notSimilarFiOrHybrid =>
          'not_similar_fi_or_hybrid',
      };

  static _GotOffTypeSimilarity fromPayload(String value) {
    return value == 'not_similar_fi_or_hybrid'
        ? _GotOffTypeSimilarity.notSimilarFiOrHybrid
        : _GotOffTypeSimilarity.similarFiOrHybrid;
  }
}

class _GotOffTypeRule {
  final String id;
  final int categoryNo;
  final String typeCode;
  final String label;

  const _GotOffTypeRule({
    required this.id,
    required this.categoryNo,
    required this.typeCode,
    required this.label,
  });

  String get displayLabel => 'Kategori $categoryNo$typeCode - $label';

  static const defaults = [
    _GotOffTypeRule(
      id: 'category_1_a',
      categoryNo: 1,
      typeCode: 'A',
      label: 'Mirip FI / Adv',
    ),
    _GotOffTypeRule(
      id: 'category_1_b',
      categoryNo: 1,
      typeCode: 'B',
      label: 'Mirip karakter',
    ),
    _GotOffTypeRule(
      id: 'category_2',
      categoryNo: 2,
      typeCode: '',
      label: 'Karakter berbeda - perlu verifikasi',
    ),
    _GotOffTypeRule(
      id: 'category_3',
      categoryNo: 3,
      typeCode: '',
      label: 'Tidak teridentifikasi - investigasi lanjut',
    ),
  ];
}

class _GotOffTypeDetail {
  final String id;
  final String ruleId;
  final int categoryNo;
  final String typeCode;
  final String typeLabel;
  final String characterNote;
  final _GotOffTypeSimilarity similarity;
  final String referenceHybrid;
  final int requiredPhotoCount;

  const _GotOffTypeDetail({
    required this.id,
    required this.ruleId,
    required this.categoryNo,
    required this.typeCode,
    required this.typeLabel,
    required this.characterNote,
    required this.similarity,
    required this.referenceHybrid,
    required this.requiredPhotoCount,
  });

  String get title => typeCode.trim().isEmpty
      ? 'Kategori $categoryNo - $typeLabel'
      : 'Kategori $categoryNo$typeCode - $typeLabel';
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

class _FetAutoDetectionResult {
  final List<_FetPointStatus> pointStatuses;
  final List<double> greenRatios;
  final int sourceWidth;
  final int sourceHeight;
  final DateTime analyzedAt;

  const _FetAutoDetectionResult({
    required this.pointStatuses,
    required this.greenRatios,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.analyzedAt,
  });

  int get grownCount => _count(_FetPointStatus.grown);

  int get notGrownCount => _count(_FetPointStatus.notGrown);

  int get reviewCount => _count(_FetPointStatus.review);

  double get emergencePercent =>
      pointStatuses.isEmpty ? 0 : grownCount / pointStatuses.length * 100;

  double get confidencePercent => pointStatuses.isEmpty
      ? 0
      : (pointStatuses.length - reviewCount) / pointStatuses.length * 100;

  int _count(_FetPointStatus status) {
    return pointStatuses.where((point) => point == status).length;
  }
}
