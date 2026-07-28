import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart' as camera;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/fet_revision_rules.dart';
import '../../domain/field_area_rules.dart';
import '../../domain/got_revision_rules.dart';
import '../../services/got_fet_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/got_fet_loading.dart';

part 'got_fet_batch_actions.dart';
part 'got_fet_batch_list.dart';
part 'got_fet_camera.dart';
part 'got_fet_models.dart';
part 'got_fet_photo_pipeline.dart';

class _GotFetUi {
  static const navy = AdvantaColors.navy;
  static const green = AdvantaColors.green;
  static const greenDark = AdvantaColors.greenDark;
  static const line = AdvantaColors.lineLight;
}

class _GotFetAssets {
  static const appLogo = 'assets/logo_got_fet_unbox.png';
  static const gotLogo = 'assets/logo_got_unbox.png';
  static const fetLogo = 'assets/logo_fet_unbox.png';
}

bool _gotFetIsDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _gotFetScreenColor(BuildContext context) => _gotFetIsDark(context)
    ? AdvantaColors.navyDark
    : AdvantaColors.lightBackground;

Color _gotFetCardColor(BuildContext context) => _gotFetIsDark(context)
    ? AdvantaColors.darkSurface.withAlpha(236)
    : Colors.white;

Color _gotFetBorderColor(BuildContext context) => _gotFetIsDark(context)
    ? AdvantaColors.lineDark.withAlpha(220)
    : AdvantaColors.lineLight;

Color _gotFetTextColor(BuildContext context) =>
    _gotFetIsDark(context) ? Colors.white : AdvantaColors.textDark;

Color _gotFetMutedColor(BuildContext context) => _gotFetIsDark(context)
    ? AdvantaColors.textMutedDark
    : AdvantaColors.textMuted;

List<BoxShadow>? _gotFetShadow(BuildContext context) => _gotFetIsDark(context)
    ? [
        BoxShadow(
          color: Colors.black.withAlpha(64),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ]
    : [
        BoxShadow(
          color: AdvantaColors.navy.withAlpha(14),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

enum _GotFetPage {
  home,
  lotTracking,
  gotPlantingData,
  gotPhoto,
  gotInput,
  fetPhoto,
  fetAnalysis,
  fetInput,
  review,
  gotReview,
  fetReview,
}

enum _FetPointStatus { grown, notGrown, review, notReadable }

enum _GotObservationStage { vegetative, finalGenerative }

enum _GotSampleQueue {
  all,
  beforePlanting,
  plantingData,
  vegetative,
  generative,
  generativeInput,
  requestSample,
  completed,
}

enum _InspectionModule { got, fet }

const _fetGridColumns = 10;
const _fetGridRows = 10;
const _fetGridPointCount = _fetGridColumns * _fetGridRows;
const _fetGreenHighThreshold = 0.035;
const _fetGreenLowThreshold = 0.012;

class GotFetScreen extends StatefulWidget {
  const GotFetScreen({super.key});

  @override
  State<GotFetScreen> createState() => _GotFetScreenState();
}

class _GotFetScreenState extends State<GotFetScreen> {
  static const _batchListPageSize = 20;
  static const _gotPlotId = 'G1 - U1';
  static const _gotMaxEvidenceSlotsPerCategory = 6;
  static const _gotFieldAreaOptions = [0.009, 0.010, 0.012, 0.015, 0.020];
  static const _gotNoteTanamOptions = ['On Process', 'Done', 'Resampling'];
  static const _gotStatusSampleOptions = [
    'Fresh',
    'Resample 1',
    'Resample 2',
    'Request New Sample',
  ];

  final _gotFetService = GotFetService();
  final _imagePicker = ImagePicker();
  final _photoPipeline = _SmartPhotoPipeline();
  final _dateFormat = DateFormat('dd MMM yyyy');
  final _dateTimeFormat = DateFormat('dd MMM yyyy HH:mm');
  final _gotNoteController = TextEditingController();
  final _fetNoteController = TextEditingController();
  final _gotTotalObservedController = TextEditingController(text: '0');
  final _gotOffTypeController = TextEditingController(text: '0');
  final _gotSelfingController = TextEditingController(text: '0');
  final _gotMaleController = TextEditingController(text: '0');
  final _gotSuspiciousController = TextEditingController(text: '0');
  final _selectedSampleIndexNotifier = ValueNotifier<int>(0);

  List<_GotFetSample> _samples = [];
  final Map<int, List<_FetPointStatus>> _fetPointsBySlot = {};
  final List<_GotFetNavEntry> _pageHistory = [];
  StreamSubscription<List<Map<String, dynamic>>>? _sampleSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _gotObservationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _gotEvidenceSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _gotOffTypeSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _fetObservationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _reviewTimelineSubscription;

  ActiveSession? _session;
  _GotFetPage _page = _GotFetPage.home;
  _InspectionModule _activeModule = _InspectionModule.got;
  int _selectedSampleIndex = 0;
  int _selectedReplication = 1;
  int _selectedFetDay = FetRevisionRules.observationDays.first;
  String _selectedFetRemark = 'Done';
  int _reviewSegment = 0;
  int _batchListVisibleCount = _batchListPageSize;
  bool _isSyncing = false;
  bool _selectionRebuildQueued = false;
  _GotObservationStage _gotObservationStage = _GotObservationStage.vegetative;
  _GotSampleQueue _activeSampleQueue = _GotSampleQueue.all;

  int _gotTotalObserved = 0;
  int _gotOffType = 0;
  int _gotSelfing = 0;
  int _gotMale = 0;
  int _gotSuspicious = 0;
  bool _isLoadingSamples = true;
  bool _isLoadingGotObservation = false;
  bool _isLoadingGotEvidence = false;
  bool _hasPersistedGotObservation = false;
  bool _gotObservationSyncQueued = false;
  bool _gotEvidenceSyncQueued = false;
  bool _gotOffTypeSyncQueued = false;
  bool _fetObservationSyncQueued = false;
  bool _reviewTimelineSyncQueued = false;
  bool _isRetryingPhotoQueue = false;
  String? _sampleLoadError;
  String? _gotObservationLoadError;
  String? _gotEvidenceLoadError;
  String? _gotObservationWatchKey;
  String? _gotEvidenceWatchKey;
  String? _gotOffTypeWatchKey;
  String? _fetObservationWatchKey;
  String? _reviewTimelineWatchKey;
  String? _syncingGotEvidenceSlotKey;
  String? _reviewTimelineLoadError;
  Map<String, _GotEvidencePhoto> _gotEvidenceBySlot = {};
  List<_GotOffTypeDetail> _gotOffTypeDetails = [];
  List<_GotOffTypeRule> _gotOffTypeRules = _GotOffTypeRule.defaults;
  List<_VillageCoordinate> _villageCoordinates = [];
  bool _isLoadingGotOffTypes = false;
  bool _isLoadingVillageCoordinates = false;
  String? _gotOffTypeLoadError;
  String? _villageCoordinateLoadError;
  List<_ReviewTimelineEvent> _reviewTimelineEvents = [];
  final Map<int, File> _fetPlotPhotosBySlot = {};
  final Map<int, File> _fetAnalysisPhotosBySlot = {};
  final Map<int, _SmartPhotoMetadata> _fetPlotMetadataBySlot = {};
  final Map<int, _FetAutoDetectionResult> _fetAutoDetectionBySlot = {};
  int? _analyzingFetSlot;
  _FetObservationResult? _latestFetObservation;
  _SmartPhotoStatus _smartPhotoStatus = const _SmartPhotoStatus();

  @override
  void initState() {
    super.initState();
    _loadSession();
    _loadSamplesFromDatabase();
    unawaited(_loadOffTypeRules());
    unawaited(_initializeSmartPhotoPipeline());
    for (final day in FetRevisionRules.observationDays) {
      for (final replication in const [1, 2]) {
        _fetPointsBySlot[FetRevisionRules.slotKey(
          day: day,
          replication: replication,
        )] = _initialFetPoints();
      }
    }
  }

  @override
  void dispose() {
    _sampleSubscription?.cancel();
    _gotObservationSubscription?.cancel();
    _gotEvidenceSubscription?.cancel();
    _gotOffTypeSubscription?.cancel();
    _fetObservationSubscription?.cancel();
    _reviewTimelineSubscription?.cancel();
    _gotNoteController.dispose();
    _fetNoteController.dispose();
    _gotTotalObservedController.dispose();
    _gotOffTypeController.dispose();
    _gotSelfingController.dispose();
    _gotMaleController.dispose();
    _gotSuspiciousController.dispose();
    _selectedSampleIndexNotifier.dispose();
    super.dispose();
  }

  Future<void> _initializeSmartPhotoPipeline() async {
    try {
      await _photoPipeline.initialize();
      await _refreshSmartPhotoStatus();
      await _drainSmartPhotoQueue();
    } catch (_) {
      await _refreshSmartPhotoStatus();
    }
  }

  Future<void> _refreshSmartPhotoStatus() async {
    final status = await _photoPipeline.status();
    if (!mounted) return;
    setState(() => _smartPhotoStatus = status);
  }

  Future<void> _drainSmartPhotoQueue({bool showResult = false}) async {
    if (_isRetryingPhotoQueue) return;
    setState(() => _isRetryingPhotoQueue = true);
    try {
      final synced = await _photoPipeline.syncPendingGotEvidence(
        _gotFetService,
      );
      await _refreshSmartPhotoStatus();
      if (!mounted || !showResult) return;
      _showSnack(
        synced == 0
            ? 'Belum ada foto offline yang berhasil disync.'
            : '$synced foto offline berhasil disync.',
      );
    } catch (error) {
      await _refreshSmartPhotoStatus();
      if (!mounted || !showResult) return;
      _showSnack('Sync foto offline belum berhasil: ${_friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _isRetryingPhotoQueue = false);
    }
  }

  bool get _hasSamples => _samples.isNotEmpty;

  _GotFetSample get _selectedSample => _samples[_selectedSampleIndex];

  String get _activeModuleCode =>
      _activeModule == _InspectionModule.got ? 'GOT' : 'FET';

  String get _activeModuleTitle => _activeModule == _InspectionModule.got
      ? 'Grow Out Test'
      : 'Field Emergence Test';

  String get _activeModuleSubtitle => _activeModule == _InspectionModule.got
      ? 'Fitur tanam, foto evidence, vegetatif, generative, dan review GOT'
      : 'Fitur data tanam, Observasi Day 7/11, kamera wide, analisa, dan review FET';

  String get _activeModuleLogo => _activeModule == _InspectionModule.got
      ? _GotFetAssets.gotLogo
      : _GotFetAssets.fetLogo;

  ({int overdue, int pending, int review, int approved}) get _sampleSummary {
    var overdue = 0;
    var pending = 0;
    var review = 0;
    var approved = 0;

    for (final sample in _samples) {
      if (!_sampleSupportsModule(sample, _activeModuleCode)) continue;
      final status = sample.status.toLowerCase();
      if (sample.isOverdue) overdue++;
      if (!_sampleObservationDone(sample)) pending++;
      if (status.contains('review') || status.contains('revision')) review++;
      if (_sampleFinalConfirmed(sample)) approved++;
    }

    return (
      overdue: overdue,
      pending: pending,
      review: review,
      approved: approved,
    );
  }

  ({
    int beforePlanting,
    int plantingReady,
    int vegetative,
    int generative,
    int requestSample,
    int completed,
  }) get _gotStageSummary {
    var beforePlanting = 0;
    var plantingReady = 0;
    var vegetative = 0;
    var generative = 0;
    var requestSample = 0;
    var completed = 0;

    for (final sample in _samples) {
      if (!_sampleSupportsModule(sample, 'GOT')) continue;
      switch (_gotQueueForSample(sample)) {
        case _GotSampleQueue.beforePlanting:
          beforePlanting++;
        case _GotSampleQueue.plantingData:
          plantingReady++;
        case _GotSampleQueue.vegetative:
          vegetative++;
        case _GotSampleQueue.generative:
          generative++;
        case _GotSampleQueue.requestSample:
          requestSample++;
        case _GotSampleQueue.generativeInput:
          break;
        case _GotSampleQueue.completed:
          completed++;
        case _GotSampleQueue.all:
          break;
      }
    }

    return (
      beforePlanting: beforePlanting,
      plantingReady: plantingReady,
      vegetative: vegetative,
      generative: generative,
      requestSample: requestSample,
      completed: completed,
    );
  }

  int get _currentFetSlotKey => FetRevisionRules.slotKey(
        day: _selectedFetDay,
        replication: _selectedReplication,
      );

  int _fetSlotKeyFor(int replication, {int? day}) {
    return FetRevisionRules.slotKey(
      day: day ?? _selectedFetDay,
      replication: replication,
    );
  }

  List<_FetPointStatus> get _currentReplication =>
      _fetPointsBySlot.putIfAbsent(_currentFetSlotKey, _initialFetPoints);

  String get _fetPlotId => 'F1 - U$_selectedReplication';

  File? get _currentFetPlotPhoto => _fetPlotPhotosBySlot[_currentFetSlotKey];

  File? get _currentFetAnalysisPhoto =>
      _fetAnalysisPhotosBySlot[_currentFetSlotKey] ?? _currentFetPlotPhoto;

  _SmartPhotoMetadata? get _currentFetPlotPhotoMetadata =>
      _fetPlotMetadataBySlot[_currentFetSlotKey];

  double _currentFetPhotoAspectRatio() {
    final result = _fetAutoDetectionBySlot[_currentFetSlotKey];
    if (result != null && result.sourceWidth > 0 && result.sourceHeight > 0) {
      return result.sourceWidth / result.sourceHeight;
    }
    final metadata = _currentFetPlotPhotoMetadata;
    if (metadata != null && metadata.width > 0 && metadata.height > 0) {
      return metadata.width / metadata.height;
    }
    return 1;
  }

  int get _gotConfirmedIssueCount => _gotOffType + _gotSelfing + _gotMale;

  bool get _gotCountsValid => _gotConfirmedIssueCount <= _gotTotalObserved;

  int get _gotTrueType =>
      math.max(0, _gotTotalObserved - _gotConfirmedIssueCount);

  double get _gotPurity =>
      _gotTotalObserved == 0 ? 0 : (_gotTrueType / _gotTotalObserved) * 100;

  ({String label, double threshold})? get _gotPassFailRule {
    final sample = _selectedSample;
    final productSource = _normalizeRuleText(
      '${sample.category} ${sample.processStage} ${sample.reasonTesting} ${sample.testType}',
    );
    final typeSource = _normalizeRuleText(
      '${sample.typeSeed} ${sample.category} ${sample.reasonTesting}',
    );
    final genderSource = _normalizeRuleText(
      '${sample.gender} ${sample.typeSeed} ${sample.category}',
    );
    final allSource = _normalizeRuleText(
      '$productSource $typeSource $genderSource',
    );

    final isParentSeed = _containsRuleTerm(allSource, const [
      'ps',
      'parent seed',
      'parent stock',
      'parental',
      'inbred',
    ]);
    final isCommercial = _containsRuleTerm(allSource, const [
      'commercial',
      'komersial',
      'komersil',
      'cs',
      'f1',
      'hybrid commercial',
    ]);
    final isManis = _containsRuleTerm(typeSource, const [
      'manis',
      'sweet',
      'sweet corn',
    ]);
    final isAtos = _containsRuleTerm(typeSource, const [
      'atos',
      'field corn',
      'fieldcorn',
      'grain',
      'dent',
    ]);

    final productLabel = isManis
        ? 'Sweet Corn'
        : isAtos
            ? 'Field Corn'
            : null;
    final genderLabel = _gotRuleGenderLabel(genderSource);

    if (isParentSeed) {
      if (genderLabel == 'Male') {
        return (
          label: '${productLabel ?? 'Corn'} PS (Male)',
          threshold: 100,
        );
      }
      if (genderLabel == 'Female') {
        return (
          label: '${productLabel ?? 'Corn'} PS (Female)',
          threshold: 99.95,
        );
      }
      return (
        label: '${productLabel ?? 'Corn'} PS (Male/Female)',
        threshold: 99.95,
      );
    }

    if (isCommercial || isManis || isAtos) {
      if (isManis) return (label: 'Sweet Corn F1', threshold: 97);
      if (isAtos) return (label: 'Field Corn F1', threshold: 95);
      return (label: 'Corn F1', threshold: 95);
    }

    return null;
  }

  String? _gotRuleGenderLabel(String genderSource) {
    if (_containsRuleTerm(genderSource, const ['male', 'jantan'])) {
      return 'Male';
    }
    if (_containsRuleTerm(genderSource, const ['female', 'betina'])) {
      return 'Female';
    }
    return null;
  }

  String get _gotCalculationReference {
    final rule = _gotPassFailRule;
    if (rule == null) return 'Master PS/Komersil belum terdeteksi';
    final classLabel =
        rule.label.contains('PS') ? 'Parent Seed (PS)' : 'Komersil';
    return '$classLabel • purity = TrueType ÷ total × 100 • '
        'batas ${_formatPercent(rule.threshold)}%';
  }

  String get _gotPassFailReference {
    final rule = _gotPassFailRule;
    if (rule == null) return 'Acuan belum terdeteksi dari Master Data';
    return '${rule.label} >= ${_formatPercent(rule.threshold)}%';
  }

  String get _gotResultLabel {
    if (_gotTotalObserved <= 0) return 'PENDING';
    if (!_gotCountsValid) return 'FAIL';
    final rule = _gotPassFailRule;
    if (rule == null) return 'PENDING';
    return _gotPurity >= rule.threshold ? 'PASS' : 'FAIL';
  }

  Color get _gotResultColor {
    return switch (_gotResultLabel) {
      'PASS' => AdvantaColors.success,
      'FAIL' => AdvantaColors.error,
      _ => AdvantaColors.gold,
    };
  }

  String get _gotEvidenceProgressText {
    final slots = _gotEvidenceSlots;
    if (slots.isEmpty) return 'Belum ada slot evidence';
    final filledCount = [
      for (final slot in slots)
        if (_gotEvidenceBySlot.containsKey(slot.key)) slot,
    ].length;
    return '$filledCount/${slots.length} slot terisi';
  }

  double get _gotOffTypePercent => _gotPercent(_gotOffType);

  double get _gotSelfingPercent => _gotPercent(_gotSelfing);

  double get _gotMalePercent => _gotPercent(_gotMale);

  String get _gotObservationStageLabel {
    return switch (_gotObservationStage) {
      _GotObservationStage.vegetative => 'Vegetatif',
      _GotObservationStage.finalGenerative => 'Generative',
    };
  }

  String get _gotObservationStagePayload {
    return switch (_gotObservationStage) {
      _GotObservationStage.vegetative => 'Vegetative',
      _GotObservationStage.finalGenerative => 'Final Generative',
    };
  }

  String get _gotObservationNumber {
    return switch (_gotObservationStage) {
      _GotObservationStage.vegetative =>
        _selectedSample.vegetativeObservationNo ?? '-',
      _GotObservationStage.finalGenerative =>
        _selectedSample.finalObservationNo ?? '-',
    };
  }

  String get _gotStatusColumnLabel {
    return switch (_gotObservationStage) {
      _GotObservationStage.vegetative => 'Status GOT Veg',
      _GotObservationStage.finalGenerative => 'Status GOT Generative',
    };
  }

  Color get _gotStageAccentColor => _gotStageColor(_gotObservationStage);

  IconData get _gotStageIcon {
    return switch (_gotObservationStage) {
      _GotObservationStage.vegetative => Icons.grass_rounded,
      _GotObservationStage.finalGenerative => Icons.local_florist_rounded,
    };
  }

  Color _gotStageColor(_GotObservationStage stage) {
    return switch (stage) {
      _GotObservationStage.vegetative => AdvantaColors.primaryGreen,
      _GotObservationStage.finalGenerative => const Color(0xFF4361EE),
    };
  }

  int get _currentReplicationGrown =>
      _countStatus(_currentReplication, _FetPointStatus.grown);

  int get _currentReplicationNotGrown =>
      _countStatus(_currentReplication, _FetPointStatus.notGrown);

  int get _currentReplicationReview =>
      _countStatus(_currentReplication, _FetPointStatus.review);

  int get _currentReplicationNotReadable =>
      _countStatus(_currentReplication, _FetPointStatus.notReadable);

  double get _currentReplicationEmergence =>
      (_currentReplicationGrown / _currentReplication.length) * 100;

  bool get _currentReplicationHasOpenItems =>
      _currentReplicationReview + _currentReplicationNotReadable > 0;

  String get _fetResultLabel =>
      _currentReplicationHasOpenItems ? 'FAIL' : 'PASS';

  Color get _fetResultColor =>
      _fetResultLabel == 'PASS' ? AdvantaColors.success : AdvantaColors.error;

  List<_FetPointStatus> _fetPointsForReplication(int replication) {
    return _fetPointsBySlot.putIfAbsent(
      _fetSlotKeyFor(replication),
      _initialFetPoints,
    );
  }

  int _fetOpenItemsForReplication(int replication) {
    final points = _fetPointsForReplication(replication);
    return _countStatus(points, _FetPointStatus.review) +
        _countStatus(points, _FetPointStatus.notReadable);
  }

  double _fetEmergenceForReplication(int replication) {
    final points = _fetPointsForReplication(replication);
    if (points.isEmpty) return 0;
    return (_countStatus(points, _FetPointStatus.grown) / points.length) * 100;
  }

  bool _fetPhotoReadyForReplication(int replication) {
    return _fetPlotPhotosBySlot[_fetSlotKeyFor(replication)] != null ||
        (_selectedReplication == replication &&
            _latestFetObservation?.dap == _selectedFetDay &&
            _latestFetObservation?.plotPhotoUrl != null);
  }

  bool _fetSubmittedForReplication(int replication) {
    return _selectedReplication == replication &&
        _latestFetObservation?.dap == _selectedFetDay;
  }

  bool get _gotPlanningReady => _samplePlantingReady(_selectedSample);

  bool _samplePlantingReady(_GotFetSample sample) {
    return sample.plantingDate != null &&
        sample.village != '-' &&
        sample.latitude != null &&
        sample.longitude != null &&
        sample.fieldArea != null;
  }

  bool _sampleRequestsNewSample(_GotFetSample sample) {
    final workflowStatus = sample.status.toLowerCase();
    final sampleCondition = sample.statusSample.toLowerCase();
    final plantingNote = sample.noteTanam.toLowerCase();
    return workflowStatus.contains('request new sample') ||
        workflowStatus.contains('resampling') ||
        sampleCondition == 'request new sample' ||
        plantingNote.contains('resampling');
  }

  bool _sampleVegetativeSubmitted(_GotFetSample sample) {
    final status = _combinedSampleStatus(sample);
    return _statusValuePresent(sample.statusGotVeg) ||
        status.contains('vegetative submitted') ||
        status.contains('vegetatif submitted') ||
        _sampleGenerativeSubmitted(sample) ||
        _sampleFinalConfirmed(sample);
  }

  bool _sampleGenerativeSubmitted(_GotFetSample sample) {
    final status = _combinedSampleStatus(sample);
    return _statusValuePresent(sample.finalStatusGot) ||
        status.contains('generative submitted') ||
        status.contains('final generative') ||
        status.contains('generatif submitted');
  }

  bool _statusValuePresent(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != '-' &&
        normalized != 'open' &&
        normalized != 'fresh' &&
        normalized != 'null';
  }

  String _combinedSampleStatus(_GotFetSample sample) {
    return [
      sample.status,
      sample.statusSample,
      sample.statusGot2,
      sample.statusGotVeg,
      sample.finalStatusGot,
      sample.noteTanam,
    ].join(' ').toLowerCase();
  }

  _GotSampleQueue _gotQueueForSample(_GotFetSample sample) {
    final status = _combinedSampleStatus(sample);
    if (_sampleRequestsNewSample(sample)) {
      return _GotSampleQueue.requestSample;
    }
    if (_sampleFinalConfirmed(sample)) return _GotSampleQueue.completed;
    if (_sampleGenerativeSubmitted(sample) ||
        status.contains('waiting review')) {
      return _GotSampleQueue.generative;
    }
    if (_sampleVegetativeSubmitted(sample) || status.contains('to obs gen')) {
      return _GotSampleQueue.generative;
    }
    if (status.contains('ready to plant') || status.contains('siap tanam')) {
      return _GotSampleQueue.plantingData;
    }
    if (_samplePlantingReady(sample) ||
        status.contains('to obs veg') ||
        status.contains('planted')) {
      return _GotSampleQueue.vegetative;
    }
    return _GotSampleQueue.beforePlanting;
  }

  bool _sampleMatchesQueue(_GotFetSample sample, _GotSampleQueue queue) {
    if (queue == _GotSampleQueue.all) return true;
    final sampleQueue = _gotQueueForSample(sample);
    if (queue == _GotSampleQueue.generativeInput) {
      return sampleQueue == _GotSampleQueue.generative &&
          !_sampleGenerativeSubmitted(sample);
    }
    return sampleQueue == queue;
  }

  String _gotQueueLabel(_GotSampleQueue queue) {
    return switch (queue) {
      _GotSampleQueue.all => 'Semua Status',
      _GotSampleQueue.beforePlanting => 'Belum Planting',
      _GotSampleQueue.plantingData => 'Ready to Plant / Data Tanam',
      _GotSampleQueue.vegetative => 'Siap Observasi Vegetatif',
      _GotSampleQueue.generative => 'Siap Observasi / Review Generatif',
      _GotSampleQueue.requestSample => 'Request New Sample',
      _GotSampleQueue.completed => 'Selesai',
      _GotSampleQueue.generativeInput => 'Siap Input Generatif',
    };
  }

  void _selectFirstSampleForActiveQueue(String module) {
    if (!_hasSamples || module != 'GOT') return;
    final indexes = _sampleIndexesForModule(
      module,
      queue: _activeSampleQueue,
    );
    if (indexes.isEmpty || indexes.contains(_selectedSampleIndex)) return;
    _selectedSampleIndex = indexes.first;
    _selectedSampleIndexNotifier.value = _selectedSampleIndex;
  }

  bool get _gotInputReady =>
      _hasPersistedGotObservation || _gotTotalObserved > 0;

  List<String> get _gotOffTypePhotoLabels =>
      GotRevisionRules.offTypePhotoLabels(_gotObservationStagePayload);

  int get _gotRequiredOffTypePhotosPerSample => _gotOffTypePhotoLabels.length;

  int get _gotRequiredOffTypePhotoTotal =>
      _gotOffTypeDetails.length * _gotRequiredOffTypePhotosPerSample;

  List<_GotEvidenceSlot> _gotOffTypeSlotsForDetail(
    _GotOffTypeDetail detail,
  ) {
    return [
      for (var index = 0; index < _gotOffTypePhotoLabels.length; index++)
        _GotEvidenceSlot(
          category: _GotEvidenceCategory.offType,
          rcvNo: index + 1,
          offTypeDetailId: detail.id,
          customLabel: _gotOffTypePhotoLabels[index],
        ),
    ];
  }

  int get _gotEvidenceFilledCount {
    return [
      for (final slot in _gotEvidenceSlots)
        if (_gotEvidenceBySlot.containsKey(slot.key)) slot,
    ].length;
  }

  bool _gotOffTypeDetailPhotosReady(_GotOffTypeDetail detail) {
    return _gotOffTypeSlotsForDetail(detail)
        .every((slot) => _gotEvidenceBySlot.containsKey(slot.key));
  }

  bool get _gotOffTypeDetailsReady {
    return GotRevisionRules.offTypeDocumentationReady(
      findingCount: _gotOffType,
      documentedCharacterCount: _gotOffTypeDetails.length,
      allPhotoPackagesComplete:
          _gotOffTypeDetails.every(_gotOffTypeDetailPhotosReady),
    );
  }

  bool get _gotEvidenceReady => _gotOffTypeDetailsReady;

  bool get _selectedSampleSubmittedOrReviewed {
    return _sampleObservationDone(_selectedSample);
  }

  bool get _fetPhotoReady {
    return _currentFetPlotPhoto != null ||
        _latestFetObservation?.plotPhotoUrl != null;
  }

  bool get _fetCheckReady => !_currentReplicationHasOpenItems;

  bool get _fetSubmittedReady => _latestFetObservation != null;

  bool _sampleObservationDone(_GotFetSample sample) {
    final status = [
      sample.status,
      sample.statusGotVeg,
      sample.finalStatusGot,
    ].join(' ').toLowerCase();
    return status.contains('submit') ||
        status.contains('approved') ||
        status.contains('confirmed') ||
        status.contains('complete') ||
        status.contains('done') ||
        status.contains('reject') ||
        status.contains('revision');
  }

  bool _sampleFinalConfirmed(_GotFetSample sample) {
    final status = [
      sample.status,
      sample.finalStatusGot,
    ].join(' ').toLowerCase();
    return status.contains('approved') ||
        status.contains('confirmed') ||
        status.contains('complete') ||
        status.contains('done');
  }

  String _sampleObservationLabel(_GotFetSample sample) =>
      _sampleObservationDone(sample) ? 'Done' : 'Pending';

  Color _sampleObservationColor(_GotFetSample sample) =>
      _sampleObservationDone(sample)
          ? AdvantaColors.success
          : AdvantaColors.gold;

  Future<void> _loadSession() async {
    final session = await SessionManager.instance.getActiveSession();
    if (!mounted) return;
    setState(() => _session = session);
    unawaited(_loadVillageCoordinates());
  }

  Future<void> _loadOffTypeRules() async {
    try {
      final rows = await _gotFetService.fetchOffTypeRuleRows();
      if (!mounted || rows.isEmpty) return;
      setState(() {
        _gotOffTypeRules = [
          for (final row in rows)
            _GotOffTypeRule(
              id: _readText(row, const ['id']),
              categoryNo: _readInt(row, const ['category_no']),
              typeCode: _readText(row, const ['type_code'], fallback: ''),
              label: _readText(row, const ['label']),
            ),
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _gotOffTypeRules = _GotOffTypeRule.defaults);
    }
  }

  Future<void> _loadVillageCoordinates() async {
    setState(() {
      _isLoadingVillageCoordinates = true;
      _villageCoordinateLoadError = null;
    });
    try {
      final rows = await _gotFetService.fetchVillageCoordinateRows();
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final village = row['village_desa']?.toString().trim() ?? '';
        if (village.isEmpty) continue;
        final coordinate = _parseVillageCoordinate(
              row['correction_tagging']?.toString(),
            ) ??
            _parseVillageCoordinate(row['coordinate']?.toString());
        if (coordinate == null) continue;
        final region = row['region']?.toString().trim() ?? '';
        final district = row['district_kab']?.toString().trim() ?? '';
        final subDistrict = row['sub_district_kec']?.toString().trim() ?? '';
        final sessionRegion = _session?.region?.trim() ?? '';
        final sessionDistrict = _session?.district?.trim() ?? '';
        if (sessionRegion.isNotEmpty &&
            region.toLowerCase() != sessionRegion.toLowerCase()) {
          continue;
        }
        if (sessionDistrict.isNotEmpty &&
            district.toLowerCase() != sessionDistrict.toLowerCase()) {
          continue;
        }
        final key = [region, district, subDistrict, village]
            .map((value) => value.toLowerCase())
            .join('|');
        grouped.putIfAbsent(key, () => []).add({
          'region': region,
          'district': district,
          'subDistrict': subDistrict,
          'village': village,
          'latitude': coordinate.lat,
          'longitude': coordinate.lng,
        });
      }

      final villages = <_VillageCoordinate>[];
      for (final entries in grouped.values) {
        var latitudeTotal = 0.0;
        var longitudeTotal = 0.0;
        for (final entry in entries) {
          latitudeTotal += entry['latitude'] as double;
          longitudeTotal += entry['longitude'] as double;
        }
        final first = entries.first;
        villages.add(
          _VillageCoordinate(
            region: first['region'] as String,
            district: first['district'] as String,
            subDistrict: first['subDistrict'] as String,
            village: first['village'] as String,
            latitude: latitudeTotal / entries.length,
            longitude: longitudeTotal / entries.length,
            sourceCount: entries.length,
          ),
        );
      }
      villages.sort((a, b) {
        final districtCompare = a.district.compareTo(b.district);
        if (districtCompare != 0) return districtCompare;
        final subCompare = a.subDistrict.compareTo(b.subDistrict);
        if (subCompare != 0) return subCompare;
        return a.village.compareTo(b.village);
      });
      if (!mounted) return;
      setState(() {
        _villageCoordinates = villages;
        _isLoadingVillageCoordinates = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingVillageCoordinates = false;
        _villageCoordinateLoadError = _friendlyError(error);
      });
    }
  }

  ({double lat, double lng})? _parseVillageCoordinate(String? raw) {
    if (raw == null || !raw.contains(',')) return null;
    final parts = raw.split(',');
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    if (!GotRevisionRules.isValidIndonesiaCoordinate(lat, lng)) return null;
    return (lat: lat, lng: lng);
  }

  Future<void> _loadSamplesFromDatabase() async {
    setState(() {
      _isLoadingSamples = true;
      _sampleLoadError = null;
    });

    try {
      await _sampleSubscription?.cancel();
      _sampleSubscription = _gotFetService.watchSampleRows().listen(
        _applySampleRows,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _sampleLoadError = _friendlyError(error);
            _isLoadingSamples = false;
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _samples = [];
        _selectedSampleIndex = 0;
        _isLoadingSamples = false;
        _sampleLoadError = _friendlyError(error);
      });
    }
  }

  void _applySampleRows(List<Map<String, dynamic>> rows) {
    final samples = [
      for (final row in rows) _sampleFromRow(row),
    ];
    if (!mounted) return;
    setState(() {
      _samples = samples;
      if (_samples.isEmpty) {
        _selectedSampleIndex = 0;
      } else if (_selectedSampleIndex >= _samples.length) {
        _selectedSampleIndex = 0;
      }
      if (_samples.isNotEmpty) {
        _selectFirstSampleForModule(_activeModuleCode);
      }
      _selectedSampleIndexNotifier.value = _selectedSampleIndex;
      _isLoadingSamples = false;
      _sampleLoadError = null;
    });
    _queueSelectedGotObservationSync();
  }

  void _queueSelectedGotObservationSync() {
    if (_gotObservationSyncQueued) return;
    _gotObservationSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gotObservationSyncQueued = false;
      unawaited(_watchSelectedGotObservation());
    });
    _queueSelectedGotEvidenceSync();
    _queueSelectedGotOffTypeSync();
    _queueSelectedFetObservationSync();
    _queueSelectedReviewTimelineSync();
  }

  void _queueSelectedGotEvidenceSync() {
    if (_gotEvidenceSyncQueued) return;
    _gotEvidenceSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gotEvidenceSyncQueued = false;
      unawaited(_watchSelectedGotEvidence());
    });
  }

  void _queueSelectedGotOffTypeSync() {
    if (_gotOffTypeSyncQueued) return;
    _gotOffTypeSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gotOffTypeSyncQueued = false;
      unawaited(_watchSelectedGotOffTypes());
    });
  }

  void _queueSelectedFetObservationSync() {
    if (_fetObservationSyncQueued) return;
    _fetObservationSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetObservationSyncQueued = false;
      unawaited(_watchSelectedFetObservation());
    });
  }

  void _queueSelectedReviewTimelineSync() {
    if (_reviewTimelineSyncQueued) return;
    _reviewTimelineSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reviewTimelineSyncQueued = false;
      unawaited(_watchSelectedReviewTimeline());
    });
  }

  Future<void> _watchSelectedGotObservation() async {
    if (!_hasSamples || !_sampleSupportsModule(_selectedSample, 'GOT')) {
      _gotObservationWatchKey = null;
      await _gotObservationSubscription?.cancel();
      _gotObservationSubscription = null;
      if (!mounted) return;
      setState(() {
        _isLoadingGotObservation = false;
        _hasPersistedGotObservation = false;
        _gotObservationLoadError = null;
        _resetGotObservationCounters();
      });
      return;
    }

    final sample = _selectedSample;
    final stage = _gotObservationStagePayload;
    final watchKey = [
      sample.lotId,
      sample.sampleId,
      _gotPlotId,
      stage,
    ].join('|');
    if (_gotObservationWatchKey == watchKey) return;

    _gotObservationWatchKey = watchKey;
    await _gotObservationSubscription?.cancel();
    _gotObservationSubscription = null;
    if (!mounted) return;

    setState(() {
      _isLoadingGotObservation = true;
      _hasPersistedGotObservation = false;
      _gotObservationLoadError = null;
      _resetGotObservationCounters();
    });

    _gotObservationSubscription = _gotFetService
        .watchGotObservationRows(
      lotId: sample.lotId,
      sampleId: sample.sampleId,
      plotId: _gotPlotId,
      stage: stage,
    )
        .listen(
      (rows) {
        if (!mounted || _gotObservationWatchKey != watchKey) return;
        final latestRow = rows.isEmpty ? null : rows.first;
        _applyGotObservationRow(latestRow);
      },
      onError: (Object error) {
        if (!mounted || _gotObservationWatchKey != watchKey) return;
        setState(() {
          _isLoadingGotObservation = false;
          _gotObservationLoadError = _friendlyError(error);
        });
        unawaited(_fetchSelectedGotObservationFallback(watchKey));
      },
    );
  }

  Future<void> _fetchSelectedGotObservationFallback(String watchKey) async {
    if (!_hasSamples) return;
    final sample = _selectedSample;
    final stage = _gotObservationStagePayload;
    try {
      final latestRow = await _gotFetService.fetchLatestGotObservation(
        lotId: sample.lotId,
        sampleId: sample.sampleId,
        plotId: _gotPlotId,
        stage: stage,
      );
      if (!mounted || _gotObservationWatchKey != watchKey) return;
      _applyGotObservationRow(latestRow);
    } catch (error) {
      if (!mounted || _gotObservationWatchKey != watchKey) return;
      setState(() {
        _isLoadingGotObservation = false;
        _gotObservationLoadError = _friendlyError(error);
      });
    }
  }

  void _applyGotObservationRow(Map<String, dynamic>? row) {
    if (!mounted) return;
    setState(() {
      _isLoadingGotObservation = false;
      _gotObservationLoadError = null;
      _hasPersistedGotObservation = row != null;

      if (row == null) {
        _resetGotObservationCounters();
        _gotNoteController.clear();
        return;
      }

      _gotTotalObserved = _readInt(row, const ['total_observed']);
      _gotOffType = _readInt(row, const ['off_type_count', 'offtype_count']);
      _gotSelfing = _readInt(row, const ['selfing_count']);
      _gotMale = _readInt(row, const ['male_count']);
      _gotSuspicious = _readInt(row, const ['suspicious_count']);
      _syncGotCountControllers();

      final remarks = _readNullableText(row, const ['remarks']);
      _setControllerText(_gotNoteController, remarks ?? '');
    });
  }

  void _resetGotObservationCounters() {
    _gotTotalObserved = 0;
    _gotOffType = 0;
    _gotSelfing = 0;
    _gotMale = 0;
    _gotSuspicious = 0;
    _syncGotCountControllers();
  }

  void _setControllerText(TextEditingController controller, String text) {
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _watchSelectedGotEvidence() async {
    if (!_hasSamples || !_sampleSupportsModule(_selectedSample, 'GOT')) {
      _gotEvidenceWatchKey = null;
      await _gotEvidenceSubscription?.cancel();
      _gotEvidenceSubscription = null;
      if (!mounted) return;
      setState(() {
        _isLoadingGotEvidence = false;
        _gotEvidenceLoadError = null;
        _gotEvidenceBySlot = {};
      });
      return;
    }

    final sample = _selectedSample;
    final stage = _gotObservationStagePayload;
    final watchKey = [
      sample.lotId,
      sample.sampleId,
      _gotPlotId,
      stage,
    ].join('|');
    if (_gotEvidenceWatchKey == watchKey) return;

    _gotEvidenceWatchKey = watchKey;
    await _gotEvidenceSubscription?.cancel();
    _gotEvidenceSubscription = null;
    if (!mounted) return;

    setState(() {
      _isLoadingGotEvidence = true;
      _gotEvidenceLoadError = null;
      _gotEvidenceBySlot = {};
    });

    _gotEvidenceSubscription = _gotFetService
        .watchGotEvidenceRows(
      lotId: sample.lotId,
      sampleId: sample.sampleId,
      plotId: _gotPlotId,
      stage: stage,
    )
        .listen(
      (rows) {
        if (!mounted || _gotEvidenceWatchKey != watchKey) return;
        _applyGotEvidenceRows(rows);
      },
      onError: (Object error) {
        if (!mounted || _gotEvidenceWatchKey != watchKey) return;
        setState(() {
          _isLoadingGotEvidence = false;
          _gotEvidenceLoadError = _friendlyError(error);
        });
      },
    );
  }

  void _applyGotEvidenceRows(List<Map<String, dynamic>> rows) {
    final photos = <String, _GotEvidencePhoto>{};
    for (final row in rows) {
      final photo = _gotEvidencePhotoFromRow(row);
      if (photo == null) continue;
      photos.putIfAbsent(photo.slotKey, () => photo);
    }

    setState(() {
      _isLoadingGotEvidence = false;
      _gotEvidenceLoadError = null;
      _gotEvidenceBySlot = photos;
    });
  }

  _GotEvidencePhoto? _gotEvidencePhotoFromRow(Map<String, dynamic> row) {
    final categoryKey = _readText(row, const ['evidence_category']);
    final rcvNo = _readInt(row, const ['rcv_no']);
    final photoUrl = _readText(row, const ['photo_url']);
    if (categoryKey == '-' || rcvNo <= 0 || photoUrl == '-') return null;

    return _GotEvidencePhoto(
      categoryKey: categoryKey,
      rcvNo: rcvNo,
      rcvLabel: _readText(
        row,
        const ['rcv_label', 'replication'],
        fallback: '$categoryKey $rcvNo',
      ),
      photoUrl: photoUrl,
      uploadedBy: _readText(row, const ['uploaded_by']),
      uploadedAt: _readDate(row, const ['uploaded_datetime']),
      offTypeDetailId: _readNullableText(row, const ['off_type_detail_id']),
    );
  }

  Future<void> _watchSelectedGotOffTypes() async {
    if (!_hasSamples || !_sampleSupportsModule(_selectedSample, 'GOT')) {
      _gotOffTypeWatchKey = null;
      await _gotOffTypeSubscription?.cancel();
      _gotOffTypeSubscription = null;
      if (!mounted) return;
      setState(() {
        _isLoadingGotOffTypes = false;
        _gotOffTypeLoadError = null;
        _gotOffTypeDetails = [];
      });
      return;
    }

    final sample = _selectedSample;
    final stage = _gotObservationStagePayload;
    final watchKey = [
      sample.lotId,
      sample.sampleId,
      _gotPlotId,
      stage,
    ].join('|');
    if (_gotOffTypeWatchKey == watchKey) return;

    _gotOffTypeWatchKey = watchKey;
    await _gotOffTypeSubscription?.cancel();
    _gotOffTypeSubscription = null;
    if (!mounted) return;
    setState(() {
      _isLoadingGotOffTypes = true;
      _gotOffTypeLoadError = null;
      _gotOffTypeDetails = [];
    });

    _gotOffTypeSubscription = _gotFetService
        .watchGotOffTypeDetailRows(
      lotId: sample.lotId,
      sampleId: sample.sampleId,
      plotId: _gotPlotId,
      stage: stage,
    )
        .listen(
      (rows) {
        if (!mounted || _gotOffTypeWatchKey != watchKey) return;
        setState(() {
          _isLoadingGotOffTypes = false;
          _gotOffTypeLoadError = null;
          _gotOffTypeDetails = [
            for (final row in rows) _gotOffTypeDetailFromRow(row),
          ];
        });
      },
      onError: (Object error) {
        if (!mounted || _gotOffTypeWatchKey != watchKey) return;
        setState(() {
          _isLoadingGotOffTypes = false;
          _gotOffTypeLoadError = _friendlyError(error);
        });
      },
    );
  }

  _GotOffTypeDetail _gotOffTypeDetailFromRow(Map<String, dynamic> row) {
    return _GotOffTypeDetail(
      id: _readText(row, const ['id']),
      ruleId: _readText(row, const ['rule_id']),
      categoryNo: _readInt(row, const ['category_no']),
      typeCode: _readText(row, const ['type_code'], fallback: ''),
      typeLabel: _readText(row, const ['type_label']),
      characterNote: _readText(row, const ['character_note']),
      similarity: _GotOffTypeSimilarityX.fromPayload(
        _readText(row, const ['similarity_assessment']),
      ),
      referenceHybrid: _readText(row, const ['reference_hybrid'], fallback: ''),
      requiredPhotoCount:
          math.max(1, _readInt(row, const ['required_photo_count'])),
      sortOrder: _readInt(row, const ['sort_order']),
    );
  }

  Future<void> _watchSelectedFetObservation() async {
    if (!_hasSamples || !_sampleSupportsModule(_selectedSample, 'FET')) {
      _fetObservationWatchKey = null;
      await _fetObservationSubscription?.cancel();
      _fetObservationSubscription = null;
      if (!mounted) return;
      setState(() => _latestFetObservation = null);
      return;
    }

    final sample = _selectedSample;
    final watchKey = [
      sample.lotId,
      sample.sampleId,
      _fetPlotId,
      _selectedFetDay,
      _selectedReplication,
    ].join('|');
    if (_fetObservationWatchKey == watchKey) return;

    _fetObservationWatchKey = watchKey;
    await _fetObservationSubscription?.cancel();
    _fetObservationSubscription = null;
    if (!mounted) return;
    setState(() => _latestFetObservation = null);

    _fetObservationSubscription = _gotFetService
        .watchFetObservationRows(
      lotId: sample.lotId,
      sampleId: sample.sampleId,
      plotId: _fetPlotId,
      dap: _selectedFetDay,
      replication: _selectedReplication,
    )
        .listen(
      (rows) {
        if (!mounted || _fetObservationWatchKey != watchKey) return;
        _applyFetObservationRow(rows.isEmpty ? null : rows.first);
      },
      onError: (Object error) {
        if (!mounted || _fetObservationWatchKey != watchKey) return;
        unawaited(_fetchSelectedFetObservationFallback(watchKey));
      },
    );
  }

  Future<void> _fetchSelectedFetObservationFallback(String watchKey) async {
    if (!_hasSamples) return;
    final sample = _selectedSample;
    try {
      final row = await _gotFetService.fetchLatestFetObservation(
        lotId: sample.lotId,
        sampleId: sample.sampleId,
        plotId: _fetPlotId,
        dap: _selectedFetDay,
        replication: _selectedReplication,
      );
      if (!mounted || _fetObservationWatchKey != watchKey) return;
      _applyFetObservationRow(row);
    } catch (_) {
      if (!mounted || _fetObservationWatchKey != watchKey) return;
      setState(() => _latestFetObservation = null);
    }
  }

  void _applyFetObservationRow(Map<String, dynamic>? row) {
    final result = row == null ? null : _fetObservationFromRow(row);
    _setControllerText(_fetNoteController, result?.remarks ?? '');
    setState(() {
      _latestFetObservation = result;
      _selectedFetRemark = result?.remarkStatus ?? 'Done';
      if (result != null && result.pointStatuses.length == _fetGridPointCount) {
        _replaceFetPoints(
          result.replication,
          result.pointStatuses,
          day: result.dap,
        );
      }
    });
  }

  _FetObservationResult _fetObservationFromRow(Map<String, dynamic> row) {
    return _FetObservationResult(
      lotId: _readText(row, const ['lot_id']),
      sampleId: _readText(row, const ['sample_id']),
      plotId: _readText(row, const ['plot_id']),
      replication: _readInt(row, const ['replication']),
      dap: _readInt(row, const ['dap']),
      totalPoints: _readInt(row, const ['total_points']),
      grownCount: _readInt(row, const ['grown_count']),
      notGrownCount: _readInt(row, const ['not_grown_count']),
      reviewCount: _readInt(row, const ['review_count']),
      notReadableCount: _readInt(row, const ['not_readable_count']),
      emergencePercent: _readDouble(row, const ['emergence_percent']) ?? 0,
      plotPhotoUrl: _readNullableText(row, const ['plot_photo_url']),
      submittedBy: _readText(row, const ['submitted_by']),
      submittedAt: _readDate(row, const ['submitted_datetime']),
      remarkStatus: _readText(
        row,
        const ['remark_status'],
        fallback: 'Done',
      ),
      remarks: _readNullableText(row, const ['remarks']),
      pointStatuses: _readFetPointStatuses(row),
    );
  }

  Future<void> _watchSelectedReviewTimeline() async {
    if (!_hasSamples) {
      _reviewTimelineWatchKey = null;
      await _reviewTimelineSubscription?.cancel();
      _reviewTimelineSubscription = null;
      if (!mounted) return;
      setState(() {
        _reviewTimelineEvents = [];
        _reviewTimelineLoadError = null;
      });
      return;
    }

    final sample = _selectedSample;
    final module = _activeModuleCode;
    if (!_sampleSupportsModule(sample, module)) {
      _reviewTimelineWatchKey = null;
      await _reviewTimelineSubscription?.cancel();
      _reviewTimelineSubscription = null;
      if (!mounted) return;
      setState(() {
        _reviewTimelineEvents = [];
        _reviewTimelineLoadError = null;
      });
      return;
    }

    final watchKey = [sample.lotId, sample.sampleId, module].join('|');
    if (_reviewTimelineWatchKey == watchKey) return;

    _reviewTimelineWatchKey = watchKey;
    await _reviewTimelineSubscription?.cancel();
    _reviewTimelineSubscription = null;
    if (!mounted) return;
    setState(() {
      _reviewTimelineEvents = [];
      _reviewTimelineLoadError = null;
    });

    _reviewTimelineSubscription = _gotFetService
        .watchReviewTimelineRows(
      lotId: sample.lotId,
      sampleId: sample.sampleId,
      module: module,
    )
        .listen(
      (rows) {
        if (!mounted || _reviewTimelineWatchKey != watchKey) return;
        setState(() {
          _reviewTimelineEvents = [
            for (final row in rows) _reviewTimelineEventFromRow(row),
          ];
          _reviewTimelineLoadError = null;
        });
      },
      onError: (Object error) {
        if (!mounted || _reviewTimelineWatchKey != watchKey) return;
        setState(() => _reviewTimelineLoadError = _friendlyError(error));
      },
    );
  }

  _ReviewTimelineEvent _reviewTimelineEventFromRow(Map<String, dynamic> row) {
    final source = row['_source']?.toString();
    final isReview = source == 'review';
    final label = isReview
        ? _readText(row, const ['new_status', 'review_action'])
        : _readText(row, const ['status']);
    final date = _readDate(
          row,
          isReview
              ? const ['review_datetime']
              : const ['event_datetime', 'created_at'],
        ) ??
        DateTime.now();
    return _ReviewTimelineEvent(
      label: label,
      date: date,
      done: true,
      actor: _readNullableText(
        row,
        isReview ? const ['reviewer'] : const ['actor'],
      ),
      remarks: _readNullableText(row, const ['remarks']),
    );
  }

  _GotFetNavEntry _navSnapshot() {
    return _GotFetNavEntry(
      page: _page,
      module: _activeModule,
      reviewSegment: _reviewSegment,
      gotStage: _gotObservationStage,
      selectedSampleIndex: _selectedSampleIndex,
      sampleQueue: _activeSampleQueue,
    );
  }

  void _rememberCurrentPage(_GotFetPage nextPage) {
    if (nextPage == _page) return;
    final snapshot = _navSnapshot();
    if (_pageHistory.isNotEmpty) {
      final last = _pageHistory.last;
      final duplicate = last.page == snapshot.page &&
          last.module == snapshot.module &&
          last.reviewSegment == snapshot.reviewSegment &&
          last.gotStage == snapshot.gotStage &&
          last.sampleQueue == snapshot.sampleQueue &&
          last.selectedSampleIndex == snapshot.selectedSampleIndex;
      if (duplicate) return;
    }
    _pageHistory.add(snapshot);
    if (_pageHistory.length > 24) {
      _pageHistory.removeAt(0);
    }
  }

  void _applyPageContext(_GotFetPage page) {
    final module = _moduleForPage(page);
    if (module != null) {
      _activeModule =
          module == 'GOT' ? _InspectionModule.got : _InspectionModule.fet;
      _reviewSegment = module == 'GOT' ? 0 : 1;
      _selectFirstSampleForModule(module);
    }
  }

  void _openPage(
    _GotFetPage page, {
    bool remember = true,
    _GotSampleQueue sampleQueue = _GotSampleQueue.all,
  }) {
    setState(() {
      if (remember) _rememberCurrentPage(page);
      _applyPageContext(page);
      _activeSampleQueue = sampleQueue;
      _page = page;
      _selectFirstSampleForActiveQueue(_activeModuleCode);
    });
    _queueSelectedGotObservationSync();
  }

  void _openReviewModule(int segment, {bool remember = true}) {
    final page = segment == 0 ? _GotFetPage.gotReview : _GotFetPage.fetReview;
    setState(() {
      if (remember) _rememberCurrentPage(page);
      _reviewSegment = segment;
      _activeModule =
          segment == 0 ? _InspectionModule.got : _InspectionModule.fet;
      _selectFirstSampleForModule(_activeModuleCode);
      _page = page;
    });
    _queueSelectedGotObservationSync();
  }

  void _setActiveModule(_InspectionModule module) {
    setState(() {
      _activeModule = module;
      _reviewSegment = module == _InspectionModule.got ? 0 : 1;
      _batchListVisibleCount = _batchListPageSize;
      _selectFirstSampleForModule(_activeModuleCode);

      final currentPageModule = _moduleForPage(_page);
      if (currentPageModule != null && currentPageModule != _activeModuleCode) {
        final targetPage = _GotFetPage.home;
        _rememberCurrentPage(targetPage);
        _page = targetPage;
      }
    });
    _queueSelectedGotObservationSync();
  }

  bool _goBack() {
    if (_pageHistory.isNotEmpty) {
      final previous = _pageHistory.removeLast();
      setState(() {
        _page = previous.page;
        _activeModule = previous.module;
        _reviewSegment = previous.reviewSegment;
        _gotObservationStage = previous.gotStage;
        if (_hasSamples) {
          _activeSampleQueue = previous.sampleQueue;
          _selectedSampleIndex = previous.selectedSampleIndex
              .clamp(
                0,
                _samples.length - 1,
              )
              .toInt();
          _selectedSampleIndexNotifier.value = _selectedSampleIndex;
        }
        _selectFirstSampleForModule(_activeModuleCode);
      });
      _queueSelectedGotObservationSync();
      return true;
    }

    if (_page != _GotFetPage.home) {
      _openPage(_GotFetPage.home, remember: false);
      return true;
    }

    return false;
  }

  void _selectBatchIndex(int index) {
    if (_selectedSampleIndex == index) return;

    _selectedSampleIndex = index;
    _selectedSampleIndexNotifier.value = index;
    _queueSelectedGotObservationSync();

    if (_selectionRebuildQueued) return;
    _selectionRebuildQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectionRebuildQueued = false);
    });
  }

  void _setGotObservationStage(_GotObservationStage stage) {
    if (_gotObservationStage == stage) return;
    setState(() => _gotObservationStage = stage);
    _queueSelectedGotObservationSync();
  }

  void _openBatchQuickActions(int index, String module) {
    _selectBatchIndex(index);
    HapticFeedback.selectionClick();

    final normalizedModule = module.toUpperCase() == 'FET' ? 'FET' : 'GOT';
    final sample = _samples[index];
    final actions = _quickActionsForModule(normalizedModule);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _gotFetCardColor(context),
      builder: (sheetContext) {
        return _BatchQuickActionSheet(
          sample: sample,
          module: normalizedModule,
          actions: actions,
          onAction: (action) {
            Navigator.of(sheetContext).pop();
            _runBatchQuickAction(action);
          },
        );
      },
    );
  }

  List<_BatchQuickAction> _quickActionsForModule(String module) {
    if (module == 'FET') {
      return const [
        _BatchQuickAction(
          label: 'Data Tanam',
          subtitle: 'Input tanggal dan detail tanam FET',
          icon: Icons.edit_calendar_rounded,
          page: _GotFetPage.gotPlantingData,
        ),
        _BatchQuickAction(
          label: 'Foto Plot',
          subtitle: 'Buka scanner/foto plot FET',
          icon: Icons.grid_on_rounded,
          page: _GotFetPage.fetPhoto,
        ),
        _BatchQuickAction(
          label: 'Analisa Plot',
          subtitle: 'Review titik tanam 10 x 10',
          icon: Icons.analytics_rounded,
          page: _GotFetPage.fetAnalysis,
        ),
        _BatchQuickAction(
          label: 'Input FET',
          subtitle: 'Isi hasil emergence',
          icon: Icons.edit_note_rounded,
          page: _GotFetPage.fetInput,
        ),
        _BatchQuickAction(
          label: 'Review FET',
          subtitle: 'Lihat status dan keputusan',
          icon: Icons.verified_rounded,
          page: _GotFetPage.fetReview,
          reviewSegment: 1,
        ),
      ];
    }

    return const [
      _BatchQuickAction(
        label: 'Data Tanam',
        subtitle: 'Update tanggal, lokasi, field area',
        icon: Icons.edit_calendar_rounded,
        page: _GotFetPage.gotPlantingData,
      ),
      _BatchQuickAction(
        label: 'Input Vegetatif',
        subtitle: 'Isi hasil dan foto evidence vegetatif',
        icon: Icons.grass_rounded,
        page: _GotFetPage.gotInput,
        stage: _GotObservationStage.vegetative,
      ),
      _BatchQuickAction(
        label: 'Input Generative',
        subtitle: 'Isi hasil dan foto evidence generative',
        icon: Icons.local_florist_rounded,
        page: _GotFetPage.gotInput,
        stage: _GotObservationStage.finalGenerative,
      ),
      _BatchQuickAction(
        label: 'Review GOT',
        subtitle: 'Lihat status dan keputusan',
        icon: Icons.verified_rounded,
        page: _GotFetPage.gotReview,
        reviewSegment: 0,
      ),
    ];
  }

  void _runBatchQuickAction(_BatchQuickAction action) {
    if (action.stage != null) {
      _setGotObservationStage(action.stage!);
    }
    if (action.reviewSegment != null) {
      _openReviewModule(action.reviewSegment!);
      return;
    }
    _openPage(action.page);
  }

  void _toggleTheme() {
    final next = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeController.setMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _page == _GotFetPage.home && _pageHistory.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: _gotFetScreenColor(context),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 66,
          backgroundColor:
              isDark ? AdvantaColors.navyDark : AdvantaColors.lightSurface,
          foregroundColor: _gotFetTextColor(context),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: _page == _GotFetPage.home && _pageHistory.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Kembali',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _goBack,
                ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _pageTitle,
                style: AdvantaText.brandTitle.copyWith(
                  color: _gotFetTextColor(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _pageSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AdvantaText.caption.copyWith(
                  color: _gotFetMutedColor(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: isDark ? 'Gunakan light mode' : 'Gunakan dark mode',
              icon: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              ),
              onPressed: _toggleTheme,
            ),
            IconButton(
              tooltip: 'User Settings',
              icon: const Icon(Icons.account_circle_rounded),
              onPressed: () => context.push('/got-fet/settings'),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _buildModuleToggle(),
            ),
          ),
        ),
        body: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_page),
                child: _buildCurrentPage(),
              ),
            ),
            if (_isSyncing)
              const Positioned.fill(
                child: _LoadingOverlay(),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor:
              isDark ? AdvantaColors.navyDeep : AdvantaColors.lightSurface,
          indicatorColor: isDark
              ? AdvantaColors.green.withAlpha(44)
              : AdvantaColors.greenSoft,
          surfaceTintColor: Colors.transparent,
          selectedIndex: _bottomIndex,
          onDestinationSelected: _openBottomDestination,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'Lot',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleToggle() {
    final isDark = _gotFetIsDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AdvantaColors.navyDeep : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gotFetBorderColor(context)),
      ),
      child: SegmentedButton<_InspectionModule>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? Colors.white : AdvantaColors.navy;
            }
            return isDark ? AdvantaColors.textMutedDark : AdvantaColors.navy;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? Colors.white : AdvantaColors.greenDark;
            }
            return isDark ? AdvantaColors.textMutedDark : AdvantaColors.navy;
          }),
          textStyle: const WidgetStatePropertyAll(AdvantaText.bodyBold),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark
                  ? AdvantaColors.green.withAlpha(54)
                  : AdvantaColors.greenSoft;
            }
            return Colors.transparent;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: Colors.transparent),
          ),
        ),
        segments: [
          ButtonSegment<_InspectionModule>(
            value: _InspectionModule.got,
            label: const Text('GOT'),
            icon: _SegmentLogo(asset: _GotFetAssets.gotLogo),
          ),
          ButtonSegment<_InspectionModule>(
            value: _InspectionModule.fet,
            label: const Text('FET'),
            icon: _SegmentLogo(asset: _GotFetAssets.fetLogo),
          ),
        ],
        selected: {_activeModule},
        onSelectionChanged: (selection) => _setActiveModule(selection.first),
      ),
    );
  }

  String get _pageTitle {
    return switch (_page) {
      _GotFetPage.home => 'Digital $_activeModuleCode',
      _GotFetPage.lotTracking => 'Lot Tracking',
      _GotFetPage.gotPlantingData => '$_activeModuleCode - Data Tanam',
      _GotFetPage.gotPhoto => 'GOT Photo',
      _GotFetPage.gotInput => 'GOT - $_gotObservationStageLabel',
      _GotFetPage.fetPhoto => 'FET Plot Scanner',
      _GotFetPage.fetAnalysis => 'Hasil Analisa Plot',
      _GotFetPage.fetInput => 'FET - Input Hasil',
      _GotFetPage.review => 'Review & Status',
      _GotFetPage.gotReview => 'Review GOT',
      _GotFetPage.fetReview => 'Review FET',
    };
  }

  String get _pageSubtitle {
    if (_page == _GotFetPage.home) {
      return _session?.name.trim().isNotEmpty == true
          ? _session!.name
          : _activeModuleTitle;
    }

    if (!_hasSamples) {
      return 'Menunggu data Batch dari Supabase';
    }

    return '${_selectedSample.lotId} | ${_selectedSample.hybrid}';
  }

  int get _bottomIndex {
    return switch (_page) {
      _GotFetPage.home => 0,
      _GotFetPage.lotTracking => 1,
      _ => 0,
    };
  }

  String? _moduleForPage(_GotFetPage page) {
    return switch (page) {
      _GotFetPage.gotPlantingData => _activeModuleCode,
      _GotFetPage.gotPhoto ||
      _GotFetPage.gotInput ||
      _GotFetPage.gotReview =>
        'GOT',
      _GotFetPage.fetPhoto ||
      _GotFetPage.fetAnalysis ||
      _GotFetPage.fetInput ||
      _GotFetPage.fetReview =>
        'FET',
      _ => null,
    };
  }

  bool _sampleSupportsModule(_GotFetSample sample, String module) {
    final testType = sample.testType.toUpperCase();
    return testType.contains(module) || testType.contains('GOT + FET');
  }

  List<int> _sampleIndexesForModule(
    String? module, {
    _GotSampleQueue queue = _GotSampleQueue.all,
  }) {
    return [
      for (var i = 0; i < _samples.length; i++)
        if ((module == null || _sampleSupportsModule(_samples[i], module)) &&
            (module?.toUpperCase() != 'GOT' ||
                _sampleMatchesQueue(_samples[i], queue)))
          i,
    ];
  }

  bool _hasSamplesForModule(String? module) =>
      _sampleIndexesForModule(module).isNotEmpty;

  void _selectFirstSampleForModule(String module) {
    if (!_hasSamples) return;
    if (_sampleSupportsModule(_selectedSample, module)) return;
    final indexes = _sampleIndexesForModule(module);
    if (indexes.isNotEmpty) {
      _selectedSampleIndex = indexes.first;
      _selectedSampleIndexNotifier.value = _selectedSampleIndex;
      _queueSelectedGotObservationSync();
    }
  }

  void _openBottomDestination(int index) {
    switch (index) {
      case 0:
        _openPage(_GotFetPage.home);
      case 1:
        _openPage(_GotFetPage.lotTracking);
    }
  }

  Widget _buildCurrentPage() {
    final canRenderWithoutSamples =
        _page == _GotFetPage.home || _page == _GotFetPage.lotTracking;
    final requiredModule =
        _page == _GotFetPage.review ? _activeModuleCode : _moduleForPage(_page);
    final hasRequiredSamples = requiredModule == null
        ? _hasSamples
        : _sampleIndexesForModule(
            requiredModule,
            queue: requiredModule == 'GOT'
                ? _activeSampleQueue
                : _GotSampleQueue.all,
          ).isNotEmpty;

    if (_isLoadingSamples && !canRenderWithoutSamples) {
      return const _SampleStatePage(
        icon: Icons.cloud_sync_rounded,
        title: 'Memuat Batch',
        message: 'Mengambil data master GOT & FET dari Supabase.',
      );
    }

    if (!hasRequiredSamples && !canRenderWithoutSamples) {
      return _buildSampleRequiredPage();
    }

    return switch (_page) {
      _GotFetPage.home => _buildHomeDashboard(),
      _GotFetPage.lotTracking => _buildLotTrackingPage(),
      _GotFetPage.gotPlantingData => _buildGotPlantingDataPage(),
      _GotFetPage.gotPhoto => _buildGotPhotoPage(),
      _GotFetPage.gotInput => _buildGotInputPage(),
      _GotFetPage.fetPhoto => _buildFetPhotoPage(),
      _GotFetPage.fetAnalysis => _buildFetAnalysisPage(),
      _GotFetPage.fetInput => _buildFetInputPage(),
      _GotFetPage.review => _buildReviewPage(),
      _GotFetPage.gotReview => _buildGotReviewPage(),
      _GotFetPage.fetReview => _buildFetReviewPage(),
    };
  }

  Widget _buildSampleRequiredPage() {
    final filteredQueueEmpty = _hasSamples &&
        _activeModule == _InspectionModule.got &&
        _activeSampleQueue != _GotSampleQueue.all;
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (filteredQueueEmpty)
            _GuidanceBanner(
              text:
                  'Belum ada lot pada antrean ${_gotQueueLabel(_activeSampleQueue)}.',
              color: AdvantaColors.warning,
            )
          else
            _buildSampleStatePanel(),
          if (filteredQueueEmpty)
            OutlinedButton.icon(
              onPressed: () => _openPage(_GotFetPage.lotTracking),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Lihat Semua Lot'),
            ),
          const SizedBox(height: 14),
          _ModuleStrip(
            logoAsset: _activeModuleLogo,
            title: _activeModuleTitle,
            subtitle: _activeModuleSubtitle,
          ),
          const SizedBox(height: 14),
          Text('Fitur $_activeModuleCode', style: _sectionTitle(context)),
          const SizedBox(height: 10),
          _buildMainMenuGrid(),
        ],
      ),
    );
  }

  Widget _buildSampleStatePanel() {
    final loading = _isLoadingSamples;
    final title = loading ? 'Memuat Batch' : 'Data Batch Belum Ada';
    final message = loading
        ? 'Mengambil data master GOT & FET dari Supabase.'
        : _sampleLoadError == null
            ? 'Tabel got_fet_samples belum berisi data Batch untuk inspeksi real-time.'
            : 'Gagal memuat got_fet_samples: $_sampleLoadError';

    return _PanelCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AdvantaColors.green.withAlpha(
                _gotFetIsDark(context) ? 52 : 24,
              ),
              shape: BoxShape.circle,
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(
                    Icons.dataset_outlined,
                    color: _gotFetIsDark(context)
                        ? Colors.white
                        : AdvantaColors.greenDark,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AdvantaText.heading3.copyWith(
                    color: _strongTextColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: AdvantaText.body2.copyWith(
                    color: _gotFetMutedColor(context),
                  ),
                ),
                if (!loading) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Muat Ulang'),
                    onPressed: _loadSamplesFromDatabase,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeDashboard() {
    final summary = _sampleSummary;
    final gotStageSummary = _gotStageSummary;
    final activeSampleIndexes = _sampleIndexesForModule(_activeModuleCode);
    final headerSample = activeSampleIndexes.contains(_selectedSampleIndex)
        ? _selectedSample
        : activeSampleIndexes.isNotEmpty
            ? _samples[activeSampleIndexes.first]
            : null;

    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrandHeader(
            userName: _session?.name,
            selectedSample: headerSample,
          ),
          if (!_hasSamples) ...[
            const SizedBox(height: 12),
            _buildSampleStatePanel(),
          ],
          const SizedBox(height: 16),
          _ModuleStrip(
            logoAsset: _activeModuleLogo,
            title: _activeModuleTitle,
            subtitle: _activeModuleSubtitle,
          ),
          const SizedBox(height: 16),
          Text('Ringkasan Hari Ini', style: _sectionTitle(context)),
          const SizedBox(height: 10),
          _MetricGrid(
            cards: _activeModule == _InspectionModule.got
                ? [
                    _MetricData(
                      'Belum Planting',
                      gotStageSummary.beforePlanting.toString(),
                      Icons.pending_actions_rounded,
                      AdvantaColors.gold,
                      onTap: () => _openPage(
                        _GotFetPage.lotTracking,
                        sampleQueue: _GotSampleQueue.beforePlanting,
                      ),
                    ),
                    _MetricData(
                      'Data Tanam',
                      gotStageSummary.plantingReady.toString(),
                      Icons.edit_calendar_rounded,
                      AdvantaColors.primaryGreen,
                      onTap: () => _openPage(
                        _GotFetPage.lotTracking,
                        sampleQueue: _GotSampleQueue.plantingData,
                      ),
                    ),
                    _MetricData(
                      'Observasi Veg',
                      gotStageSummary.vegetative.toString(),
                      Icons.grass_rounded,
                      AdvantaColors.greenDark,
                      onTap: () => _openPage(
                        _GotFetPage.lotTracking,
                        sampleQueue: _GotSampleQueue.vegetative,
                      ),
                    ),
                    _MetricData(
                      'Observasi Gen',
                      gotStageSummary.generative.toString(),
                      Icons.local_florist_rounded,
                      const Color(0xFF4361EE),
                      onTap: () => _openPage(
                        _GotFetPage.lotTracking,
                        sampleQueue: _GotSampleQueue.generative,
                      ),
                    ),
                    _MetricData(
                      'Request Sample',
                      gotStageSummary.requestSample.toString(),
                      Icons.change_circle_rounded,
                      AdvantaColors.error,
                      onTap: () => _openPage(
                        _GotFetPage.lotTracking,
                        sampleQueue: _GotSampleQueue.requestSample,
                      ),
                    ),
                    _MetricData(
                      'Selesai',
                      gotStageSummary.completed.toString(),
                      Icons.verified_rounded,
                      AdvantaColors.success,
                      onTap: () => _openPage(
                        _GotFetPage.lotTracking,
                        sampleQueue: _GotSampleQueue.completed,
                      ),
                    ),
                  ]
                : [
                    _MetricData(
                      'Data Tanam',
                      activeSampleIndexes
                          .where(
                              (index) => _samplePlantingReady(_samples[index]))
                          .length
                          .toString(),
                      Icons.edit_calendar_rounded,
                      AdvantaColors.primaryGreen,
                    ),
                    _MetricData(
                      'Observasi Due',
                      summary.overdue.toString(),
                      Icons.event_busy_rounded,
                      AdvantaColors.error,
                    ),
                    _MetricData(
                      'Belum Dikirim',
                      summary.pending.toString(),
                      Icons.outbox_rounded,
                      AdvantaColors.gold,
                    ),
                    _MetricData(
                      'Menunggu Review',
                      summary.review.toString(),
                      Icons.rate_review_rounded,
                      AdvantaColors.gold,
                    ),
                    _MetricData(
                      'Selesai',
                      summary.approved.toString(),
                      Icons.verified_rounded,
                      AdvantaColors.success,
                    ),
                  ],
          ),
          const SizedBox(height: 18),
          Text('Menu $_activeModuleCode', style: _sectionTitle(context)),
          const SizedBox(height: 10),
          _buildMainMenuGrid(),
          const SizedBox(height: 18),
          _WorkflowSummary(
            steps: _activeModule == _InspectionModule.got
                ? const [
                    ('Sample', Icons.description_rounded),
                    ('Data Tanam', Icons.edit_calendar_rounded),
                    ('Vegetatif', Icons.grass_rounded),
                    ('Generative', Icons.local_florist_rounded),
                    ('Review', Icons.assignment_turned_in_rounded),
                    ('Selesai', Icons.verified_rounded),
                  ]
                : const [
                    ('Sample', Icons.description_rounded),
                    ('Data Tanam', Icons.edit_calendar_rounded),
                    ('Day 7', Icons.filter_7_rounded),
                    ('Day 11', Icons.calendar_view_week_rounded),
                    ('Remarks', Icons.notes_rounded),
                    ('Selesai', Icons.verified_rounded),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainMenuGrid() {
    final moduleActions = _activeModule == _InspectionModule.got
        ? [
            _MenuAction(
              'Data Tanam',
              'Input proses tanam',
              Icons.edit_calendar_rounded,
              _GotFetPage.gotPlantingData,
              logoAsset: _GotFetAssets.gotLogo,
            ),
            _MenuAction(
              'Vegetatif',
              'Input + evidence',
              Icons.grass_rounded,
              _GotFetPage.gotInput,
              logoAsset: _GotFetAssets.gotLogo,
            ),
            _MenuAction(
              'Generative',
              'Input + evidence',
              Icons.local_florist_rounded,
              _GotFetPage.gotInput,
              logoAsset: _GotFetAssets.gotLogo,
            ),
          ]
        : [
            _MenuAction(
              'Data Tanam',
              'Input proses tanam',
              Icons.edit_calendar_rounded,
              _GotFetPage.gotPlantingData,
              logoAsset: _GotFetAssets.fetLogo,
            ),
            _MenuAction(
              'Plot Scanner',
              'Foto plot 10x10',
              Icons.grid_on_rounded,
              _GotFetPage.fetPhoto,
              logoAsset: _GotFetAssets.fetLogo,
            ),
            _MenuAction(
              'Analisa Plot',
              'Kroscek 10x10',
              Icons.analytics_rounded,
              _GotFetPage.fetAnalysis,
              logoAsset: _GotFetAssets.fetLogo,
            ),
            _MenuAction(
              'Input FET',
              'Emergence',
              Icons.edit_note_rounded,
              _GotFetPage.fetInput,
              logoAsset: _GotFetAssets.fetLogo,
            ),
          ];

    final actions = [
      _MenuAction(
        'Lot Tracking',
        'Status sample',
        Icons.inventory_2_rounded,
        _GotFetPage.lotTracking,
      ),
      ...moduleActions,
      _MenuAction(
        'Sinkronisasi',
        'Submit real-time',
        Icons.cloud_sync_rounded,
        _GotFetPage.home,
      ),
    ];

    return _buildActionGrid(
      actions,
      onAction: (action) {
        if (action.page == _GotFetPage.home && action.title == 'Sinkronisasi') {
          _showSnack('Data tersimpan ke Supabase saat Submit.');
          return;
        }
        if (action.title == 'Vegetatif') {
          _setGotObservationStage(_GotObservationStage.vegetative);
        }
        if (action.title == 'Generative') {
          _setGotObservationStage(_GotObservationStage.finalGenerative);
        }
        final queue = switch (action.title) {
          'Data Tanam' when _activeModule == _InspectionModule.got =>
            _GotSampleQueue.plantingData,
          'Vegetatif' => _GotSampleQueue.vegetative,
          'Generative' => _GotSampleQueue.generativeInput,
          _ => _GotSampleQueue.all,
        };
        _openPage(action.page, sampleQueue: queue);
      },
    );
  }

  Widget _buildActionGrid(
    List<_MenuAction> actions, {
    void Function(_MenuAction action)? onAction,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 360
                ? 3
                : 2;
        final childRatio = switch (columns) {
          4 => 1.24,
          3 => .82,
          _ => 1.12,
        };
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: childRatio,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            return _MenuActionCard(
              action: action,
              onTap: () {
                if (onAction != null) {
                  onAction(action);
                  return;
                }
                if (action.page == _GotFetPage.home &&
                    action.title == 'Sinkronisasi') {
                  _showSnack('Data tersimpan ke backend saat Submit.');
                  return;
                }
                _openPage(action.page);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBatchListView({
    String? module,
    void Function(int sampleIndex, String module)? onBatchTap,
  }) {
    final indexes = _sampleIndexesForModule(
      module,
      queue: module?.toUpperCase() == 'GOT'
          ? _activeSampleQueue
          : _GotSampleQueue.all,
    );
    var visibleCount = math.min(_batchListVisibleCount, indexes.length);
    final selectedPosition = indexes.indexOf(_selectedSampleIndex);
    if (selectedPosition >= visibleCount) {
      visibleCount = selectedPosition + 1;
    }
    final visibleIndexes = indexes.take(visibleCount).toList();

    if (indexes.isEmpty) {
      return _PanelCard(
        child: Row(
          children: [
            Icon(
              Icons.view_list_rounded,
              color: _gotFetMutedColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'List Batch akan muncul setelah got_fet_samples berisi data dari database.',
                style: AdvantaText.body2.copyWith(
                  color: _gotFetMutedColor(context),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _PanelCard(
          child: Row(
            children: [
              Icon(Icons.view_list_rounded, color: _GotFetUi.greenDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Menampilkan $visibleCount dari ${indexes.length} Batch $_activeModuleCode | tap batch untuk detail',
                  style: AdvantaText.body2.copyWith(
                    color: _gotFetMutedColor(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (var row = 0; row < visibleIndexes.length; row++) ...[
          RepaintBoundary(
            child: ValueListenableBuilder<int>(
              valueListenable: _selectedSampleIndexNotifier,
              builder: (context, selectedIndex, _) {
                final sampleIndex = visibleIndexes[row];
                final sample = _samples[sampleIndex];
                return _BatchListItem(
                  key: ValueKey('batch-${sample.batch}'),
                  sample: sample,
                  selected: sampleIndex == selectedIndex,
                  statusColor: _statusColor(sample.status),
                  observationLabel: _sampleObservationLabel(sample),
                  observationColor: _sampleObservationColor(sample),
                  plantingDate: _formatDate(sample.plantingDate),
                  resultEstimation: _formatDate(sample.resultEstimation),
                  fieldArea: _formatArea(sample.fieldArea),
                  onTap: () {
                    final resolvedModule = module ?? _activeModuleCode;
                    if (onBatchTap != null) {
                      onBatchTap(sampleIndex, resolvedModule);
                      return;
                    }
                    _openBatchQuickActions(sampleIndex, resolvedModule);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (visibleCount < indexes.length)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                'Tampilkan ${math.min(_batchListPageSize, indexes.length - visibleCount)} lagi',
              ),
              onPressed: () {
                setState(() {
                  _batchListVisibleCount = math.min(
                    _batchListVisibleCount + _batchListPageSize,
                    indexes.length,
                  );
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _buildLotTrackingPage() {
    if (!_hasSamplesForModule(_activeModuleCode)) {
      return _PageScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSampleStatePanel(),
            const SizedBox(height: 16),
            Text('Daftar Batch', style: _sectionTitle(context)),
            const SizedBox(height: 10),
            _buildBatchListView(
              module: _activeModuleCode,
              onBatchTap: (index, _) => _selectBatchIndex(index),
            ),
            const SizedBox(height: 16),
            Text('Menu $_activeModuleCode', style: _sectionTitle(context)),
            const SizedBox(height: 10),
            _buildMainMenuGrid(),
          ],
        ),
      );
    }

    final queueIndexes = _sampleIndexesForModule(
      _activeModuleCode,
      queue: _activeModule == _InspectionModule.got
          ? _activeSampleQueue
          : _GotSampleQueue.all,
    );
    if (queueIndexes.isEmpty) {
      return _PageScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ModuleStrip(
              logoAsset: _GotFetAssets.appLogo,
              title: 'Lot Tracking',
              subtitle: 'Filter: ${_gotQueueLabel(_activeSampleQueue)}',
            ),
            const SizedBox(height: 16),
            _GuidanceBanner(
              text:
                  'Belum ada lot pada status ${_gotQueueLabel(_activeSampleQueue)}.',
              color: AdvantaColors.warning,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openPage(
                _GotFetPage.lotTracking,
                sampleQueue: _GotSampleQueue.all,
              ),
              icon: const Icon(Icons.clear_all_rounded),
              label: const Text('Tampilkan Semua Lot'),
            ),
          ],
        ),
      );
    }

    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSamplePicker(module: _activeModuleCode),
          const SizedBox(height: 12),
          _ModuleStrip(
            logoAsset: _GotFetAssets.appLogo,
            title: 'Lot Tracking',
            subtitle:
                'Filter: ${_gotQueueLabel(_activeSampleQueue)} • cari lokasi, koordinat, atau status',
          ),
          const SizedBox(height: 16),
          Text('Daftar Batch • ${_gotQueueLabel(_activeSampleQueue)}',
              style: _sectionTitle(context)),
          const SizedBox(height: 10),
          _buildBatchListView(
            module: _activeModuleCode,
            onBatchTap: (index, _) {
              HapticFeedback.selectionClick();
              _selectBatchIndex(index);
              _openLotTrackingDetailSheet(index);
            },
          ),
          const SizedBox(height: 16),
          _buildLotSummaryCard(),
          const SizedBox(height: 16),
          _buildShipmentInfoCard(),
          const SizedBox(height: 16),
          _buildTrackingActionCard(),
          const SizedBox(height: 16),
          _buildTimelineCard(_selectedSample),
          const SizedBox(height: 16),
          _buildLotReviewActionCard(),
        ],
      ),
    );
  }

  void _openLotTrackingDetailSheet(int index) {
    _selectBatchIndex(index);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _gotFetCardColor(context),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.88,
              minChildSize: 0.55,
              maxChildSize: 0.96,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Detail Tracking Batch',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AdvantaText.heading3.copyWith(
                              color: _gotFetTextColor(context),
                            ),
                          ),
                        ),
                        _StatusPill(
                          label: _selectedSample.status,
                          color: _statusColor(_selectedSample.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildLotSummaryCard(),
                    const SizedBox(height: 12),
                    _buildShipmentInfoCard(),
                    const SizedBox(height: 12),
                    _buildTrackingActionCard(
                      onConfirmed: () {
                        setSheetState(() {});
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildTimelineCard(_selectedSample),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildLotReviewActionCard(
                      onSubmitted: () {
                        setSheetState(() {});
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGotWorkflowCard() {
    return _WorkflowProgressCard(
      title: 'Alur GOT',
      subtitle: _gotEvidenceReady
          ? 'Evidence lengkap, hasil siap disubmit/review'
          : _gotInputReady
              ? 'Lengkapi evidence sesuai slot hasil pengamatan'
              : 'Mulai dari data tanam, lalu isi fase dan evidence di menu Vegetatif atau Generative',
      steps: [
        _WorkflowStepData(
          label: 'Tanam',
          detail: _gotPlanningReady ? 'Lengkap' : 'Belum lengkap',
          icon: Icons.edit_calendar_rounded,
          done: _gotPlanningReady,
          active: _page == _GotFetPage.gotPlantingData,
        ),
        _WorkflowStepData(
          label: _gotObservationStageLabel,
          detail: _gotInputReady ? 'Ada hasil' : 'Belum ada',
          icon: _gotStageIcon,
          done: _gotInputReady,
          active: _page == _GotFetPage.gotInput,
        ),
        _WorkflowStepData(
          label: 'Evidence',
          detail: _gotEvidenceSlots.isEmpty
              ? 'Belum terbentuk'
              : '$_gotEvidenceFilledCount/${_gotEvidenceSlots.length}',
          icon: Icons.photo_library_rounded,
          done: _gotEvidenceReady,
          active: _page == _GotFetPage.gotInput,
        ),
        _WorkflowStepData(
          label: 'Review',
          detail: _selectedSample.status,
          icon: Icons.verified_rounded,
          done: _selectedSampleSubmittedOrReviewed,
          active: _page == _GotFetPage.gotReview,
        ),
      ],
    );
  }

  Widget _buildFetWorkflowCard() {
    return _WorkflowProgressCard(
      title: 'Alur FET Day $_selectedFetDay • U$_selectedReplication',
      subtitle: !_gotPlanningReady
          ? 'Lengkapi Data Tanam sebelum memulai observasi FET'
          : _fetSubmittedReady
              ? 'Hasil Day $_selectedFetDay ulangan ini sudah tersimpan'
              : _fetCheckReady
                  ? 'Kroscek selesai, lanjut submit hasil'
                  : 'Ambil foto plot lalu kroscek 100 titik',
      steps: [
        _WorkflowStepData(
          label: 'Tanam',
          detail: _gotPlanningReady ? 'Lengkap' : 'Belum lengkap',
          icon: Icons.edit_calendar_rounded,
          done: _gotPlanningReady,
          active: _page == _GotFetPage.gotPlantingData,
        ),
        _WorkflowStepData(
          label: 'Foto D$_selectedFetDay',
          detail: _fetPhotoReady ? 'Siap' : 'Belum ada',
          icon: Icons.camera_alt_rounded,
          done: _fetPhotoReady,
          active: _page == _GotFetPage.fetPhoto,
        ),
        _WorkflowStepData(
          label: 'Kroscek',
          detail: _fetCheckReady
              ? '100 titik'
              : '${_currentReplicationReview + _currentReplicationNotReadable} terbuka',
          icon: Icons.grid_on_rounded,
          done: _fetCheckReady,
          active: _page == _GotFetPage.fetAnalysis,
        ),
        _WorkflowStepData(
          label: 'Submit',
          detail: _fetSubmittedReady ? _selectedFetRemark : 'Belum submit',
          icon: Icons.send_rounded,
          done: _fetSubmittedReady,
          active: _page == _GotFetPage.fetInput,
        ),
        _WorkflowStepData(
          label: 'Review',
          detail: _selectedSample.status,
          icon: Icons.verified_rounded,
          done: _selectedSampleSubmittedOrReviewed,
          active: _page == _GotFetPage.fetReview,
        ),
      ],
    );
  }

  Widget _buildGotPlantingDataPage() {
    final module = _activeModuleCode;
    if (!_hasSamplesForModule(module)) {
      return _buildSampleRequiredPage();
    }

    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSamplePicker(module: module),
          const SizedBox(height: 12),
          _ModuleStrip(
            logoAsset:
                module == 'FET' ? _GotFetAssets.fetLogo : _GotFetAssets.gotLogo,
            title: 'Data Tanam $module',
            subtitle:
                'Input, tampilkan, dan hubungkan data tanam ke observasi $module',
          ),
          const SizedBox(height: 12),
          module == 'FET' ? _buildFetWorkflowCard() : _buildGotWorkflowCard(),
          const SizedBox(height: 12),
          _buildLotIdentityCard(
            extraRows: [
              ('Batch', _selectedSample.batch),
              ('Delivery Date 1', _formatDate(_selectedSample.deliveryDate1)),
              ('Delivery Date 2', _formatDate(_selectedSample.deliveryDate2)),
              ('Status Sample', _selectedSample.statusSample),
            ],
          ),
          const SizedBox(height: 16),
          _buildPlantingScheduleCard(),
          const SizedBox(height: 16),
          _buildManualDatabaseCard(),
          const SizedBox(height: 16),
          _buildPlantingBoundaryCard(),
        ],
      ),
    );
  }

  Widget _buildGotPhotoPage() {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSamplePicker(module: 'GOT'),
          const SizedBox(height: 12),
          const _ModuleStrip(
            logoAsset: _GotFetAssets.gotLogo,
            title: 'GOT Photo Evidence',
            subtitle: 'Foto tersimpan per lot, stage, kategori, dan RCVR',
          ),
          const SizedBox(height: 12),
          _buildGotWorkflowCard(),
          const SizedBox(height: 12),
          _buildLotIdentityCard(
            extraRows: [
              ('Batch', _selectedSample.batch),
              ('Plot', _gotPlotId),
              ('Stage Observasi', _gotObservationStageLabel),
              ('No. Obs Target', _gotObservationNumber),
            ],
          ),
          const SizedBox(height: 12),
          _buildGotStageSelector(),
          const SizedBox(height: 12),
          _buildGotObservationSyncStatus(),
          const SizedBox(height: 12),
          _GuidanceBanner(
            text: _gotOffType == 0
                ? 'Belum ada temuan Off-Type; tidak ada paket foto sampel yang wajib.'
                : 'Dokumentasikan setiap jenis karakter berbeda dari $_gotOffType temuan. Saat ini ${_gotOffTypeDetails.length} jenis × $_gotRequiredOffTypePhotosPerSample foto = $_gotRequiredOffTypePhotoTotal foto.',
            color: AdvantaColors.success,
          ),
          const SizedBox(height: 12),
          _buildSmartCameraStatusCard(module: 'GOT'),
          const SizedBox(height: 12),
          _buildGotEvidenceFolders(),
        ],
      ),
    );
  }

  Widget _buildGotInputPage() {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSamplePicker(module: 'GOT'),
          const SizedBox(height: 12),
          _ModuleStrip(
            logoAsset: _GotFetAssets.gotLogo,
            title: 'Input GOT $_gotObservationStageLabel',
            subtitle: _gotObservationStage == _GotObservationStage.vegetative
                ? 'Fase vegetatif: input hasil dan evidence khusus vegetatif'
                : 'Fase generative: input hasil dan evidence khusus generative',
          ),
          const SizedBox(height: 12),
          _buildGotWorkflowCard(),
          const SizedBox(height: 12),
          _buildLotIdentityCard(
            extraRows: [
              ('Batch', _selectedSample.batch),
              ('Plot', _gotPlotId),
              ('Stage Observasi', _gotObservationStageLabel),
              ('No. Obs Target', _gotObservationNumber),
            ],
          ),
          const SizedBox(height: 14),
          _buildGotStageLockBanner(),
          const SizedBox(height: 12),
          _buildGotCountForm(),
          const SizedBox(height: 12),
          _buildGotOffTypeDetailsCard(),
          const SizedBox(height: 12),
          _buildGotEvidenceSummaryCard(),
          const SizedBox(height: 12),
          _buildSmartCameraStatusCard(module: 'GOT'),
          const SizedBox(height: 12),
          _buildGotEvidenceFolders(),
          const SizedBox(height: 12),
          _buildNoteBox(controller: _gotNoteController),
          const SizedBox(height: 16),
          _DualActionBar(
            leftLabel: 'Simpan Draft',
            rightLabel: 'Submit $_gotObservationStageLabel',
            leftIcon: Icons.save_outlined,
            rightIcon: _gotStageIcon,
            rightEnabled: _gotPlanningReady &&
                _gotCountsValid &&
                _gotEvidenceReady &&
                !_isSyncing,
            rightColor: _gotStageAccentColor,
            onLeft: () => _showSnack(
              'Draft GOT $_gotObservationStageLabel disimpan lokal.',
            ),
            onRight: _submitGotResult,
          ),
        ],
      ),
    );
  }

  Widget _buildFetPhotoPage() {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSamplePicker(module: 'FET'),
          const SizedBox(height: 12),
          const _ModuleStrip(
            logoAsset: _GotFetAssets.fetLogo,
            title: 'Field Emergence Test',
            subtitle: 'Plot scanner for 10 x 10 emergence count',
          ),
          const SizedBox(height: 12),
          _buildFetWorkflowCard(),
          const SizedBox(height: 12),
          _buildFetObservationDaySelector(),
          const SizedBox(height: 12),
          _GuidanceBanner(
            text:
                'Gunakan mode wide dan grid 3 x 3 agar seluruh plot 10 x 10 masuk frame tanpa mengambil foto dari posisi terlalu tinggi.',
            color: AdvantaColors.success,
          ),
          const SizedBox(height: 10),
          _buildSmartCameraStatusCard(module: 'FET'),
          const SizedBox(height: 10),
          _buildReplicationSelector(),
          const SizedBox(height: 10),
          _CameraMockup(
            mode: _CameraMockupMode.fet,
            title: 'Sejajarkan plot dengan bingkai',
            footer: '100 titik tanam siap dikroscek dari foto',
          ),
          const SizedBox(height: 12),
          _buildFetPhotoActionBar(),
          if (_currentFetPlotPhoto != null) ...[
            const SizedBox(height: 12),
            _buildPlotEvidenceCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildFetPhotoActionBar() {
    final hasPhoto = _currentFetPlotPhoto != null;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _GotFetUi.green,
              foregroundColor: Colors.white,
            ),
            icon: Icon(
              hasPhoto ? Icons.analytics_rounded : Icons.camera_alt_rounded,
            ),
            label: Text(hasPhoto ? 'Kroscek Foto' : 'Ambil Foto'),
            onPressed: hasPhoto
                ? () => _openPage(_GotFetPage.fetAnalysis)
                : () => _pickFetPlotPhoto(
                      ImageSource.camera,
                      openAnalysisAfterPick: true,
                    ),
          ),
        ),
        const SizedBox(width: 10),
        if (hasPhoto) ...[
          IconButton.filledTonal(
            tooltip: 'Ganti dari kamera',
            onPressed: () => _pickFetPlotPhoto(
              ImageSource.camera,
              openAnalysisAfterPick: true,
            ),
            icon: const Icon(Icons.camera_alt_rounded),
          ),
          const SizedBox(width: 8),
        ],
        IconButton.filledTonal(
          tooltip: hasPhoto ? 'Ganti dari gallery' : 'Upload dari gallery',
          onPressed: () => _pickFetPlotPhoto(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_rounded),
        ),
      ],
    );
  }

  Widget _buildFetAnalysisPage() {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ModuleStrip(
            logoAsset: _GotFetAssets.fetLogo,
            title: 'Field Emergence Test',
            subtitle: 'Review hasil analisa plot per ulangan',
          ),
          const SizedBox(height: 12),
          _buildFetWorkflowCard(),
          const SizedBox(height: 12),
          _buildFetObservationDaySelector(),
          const SizedBox(height: 12),
          _buildReplicationSelector(),
          const SizedBox(height: 14),
          _buildFetAutoDetectionCard(),
          const SizedBox(height: 14),
          _MetricGrid(
            cards: [
              _MetricData('Tumbuh', _currentReplicationGrown.toString(),
                  Icons.check_circle_rounded, AdvantaColors.success),
              _MetricData(
                  'Tidak Tumbuh',
                  _currentReplicationNotGrown.toString(),
                  Icons.cancel_rounded,
                  AdvantaColors.error),
              _MetricData(
                  'Emergence',
                  '${_currentReplicationEmergence.toStringAsFixed(1)}%',
                  Icons.percent_rounded,
                  AdvantaColors.primaryGreen),
              _MetricData('Perlu Review', _currentReplicationReview.toString(),
                  Icons.help_rounded, AdvantaColors.gold),
            ],
          ),
          const SizedBox(height: 16),
          _buildFetPhotoReviewCard(),
          const SizedBox(height: 12),
          _buildFetLegend(),
          const SizedBox(height: 16),
          _DualActionBar(
            leftLabel: 'Koreksi Manual',
            rightLabel: 'Simpan Hasil',
            leftIcon: Icons.tune_rounded,
            rightIcon: Icons.save_rounded,
            rightEnabled: !_currentReplicationHasOpenItems,
            onLeft: () => _showSnack('Tap titik di grid untuk koreksi manual.'),
            onRight: () => _openPage(_GotFetPage.fetInput),
          ),
        ],
      ),
    );
  }

  Widget _buildFetInputPage() {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSamplePicker(module: 'FET'),
          const SizedBox(height: 12),
          const _ModuleStrip(
            logoAsset: _GotFetAssets.fetLogo,
            title: 'Field Emergence Test',
            subtitle: 'Final emergence result and submission',
          ),
          const SizedBox(height: 12),
          _buildFetWorkflowCard(),
          const SizedBox(height: 12),
          _buildFetObservationDaySelector(),
          const SizedBox(height: 12),
          _buildReplicationSelector(),
          const SizedBox(height: 12),
          _buildLotIdentityCard(
            extraRows: [
              ('Planting Date', _formatDate(_selectedSample.plantingDate)),
              ('Plot', _fetPlotId),
              ('DAP', '$_selectedFetDay'),
              ('Ulangan', '$_selectedReplication'),
            ],
          ),
          const SizedBox(height: 14),
          _buildFetInputForm(),
          const SizedBox(height: 12),
          _buildPlotEvidenceCard(),
          const SizedBox(height: 12),
          _buildFetRemarksCard(),
          const SizedBox(height: 16),
          _DualActionBar(
            leftLabel: 'Simpan Draft',
            rightLabel: 'Submit',
            leftIcon: Icons.save_outlined,
            rightIcon: Icons.send_rounded,
            rightEnabled: _gotPlanningReady &&
                _fetPhotoReady &&
                !_currentReplicationHasOpenItems &&
                !_isSyncing,
            onLeft: () => _showSnack('Draft FET disimpan lokal.'),
            onRight: _submitFetResult,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewPage() {
    return _reviewSegment == 0 ? _buildGotReviewPage() : _buildFetReviewPage();
  }

  Widget _buildGotReviewPage() {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSamplePicker(module: 'GOT'),
          const SizedBox(height: 12),
          const _ModuleStrip(
            logoAsset: _GotFetAssets.gotLogo,
            title: 'Review GOT',
            subtitle: 'Review purity, offtype, selfing, male, dan evidence',
          ),
          const SizedBox(height: 12),
          _buildGotWorkflowCard(),
          const SizedBox(height: 12),
          _buildLotIdentityCard(
            extraRows: [
              ('Batch', _selectedSample.batch),
              ('Plot', _gotPlotId),
              ('Stage Observasi', _gotObservationStageLabel),
              ('No. Obs Target', _gotObservationNumber),
            ],
          ),
          const SizedBox(height: 12),
          _buildGotStageSelector(),
          const SizedBox(height: 14),
          _buildGotReviewResult(),
          const SizedBox(height: 14),
          _buildGotOffTypeDetailsCard(readOnly: true),
          const SizedBox(height: 14),
          _buildReviewTimeline(),
          const SizedBox(height: 16),
          _buildReviewDecisionActions(),
        ],
      ),
    );
  }

  Widget _buildFetReviewPage() {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSamplePicker(module: 'FET'),
          const SizedBox(height: 12),
          const _ModuleStrip(
            logoAsset: _GotFetAssets.fetLogo,
            title: 'Review FET',
            subtitle: 'Review emergence, titik tanam, dan evidence plot',
          ),
          const SizedBox(height: 12),
          _buildFetWorkflowCard(),
          const SizedBox(height: 12),
          _buildFetObservationDaySelector(),
          const SizedBox(height: 12),
          _buildReplicationSelector(),
          const SizedBox(height: 12),
          _buildLotIdentityCard(
            extraRows: [
              ('Batch', _selectedSample.batch),
              ('Planting Date', _formatDate(_selectedSample.plantingDate)),
              ('Plot', _fetPlotId),
              ('DAP', '$_selectedFetDay'),
              ('Ulangan', '$_selectedReplication'),
            ],
          ),
          const SizedBox(height: 14),
          _buildFetReviewResult(),
          const SizedBox(height: 14),
          _buildFetReviewVisualCard(),
          const SizedBox(height: 14),
          _buildReviewTimeline(),
          const SizedBox(height: 16),
          _buildReviewDecisionActions(),
        ],
      ),
    );
  }

  Widget _buildReviewDecisionActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSyncing
                ? null
                : () => _submitReviewDecision(
                      'Revision Required',
                      displayStatus: 'Need Review',
                    ),
            icon: const Icon(Icons.rate_review_rounded),
            label: const Text('Need Review'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSyncing
                ? null
                : () => _submitReviewDecision(
                      'Approved',
                      displayStatus: 'Confirmed',
                    ),
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Confirmed'),
          ),
        ),
      ],
    );
  }

  Widget _buildSamplePicker({String? module}) {
    final theme = Theme.of(context);
    final sampleIndexes = _sampleIndexesForModule(
      module,
      queue: module?.toUpperCase() == 'GOT'
          ? _activeSampleQueue
          : _GotSampleQueue.all,
    );
    final selectedValue = sampleIndexes.contains(_selectedSampleIndex)
        ? _selectedSampleIndex
        : null;

    final selectedSample =
        selectedValue == null ? null : _samples[selectedValue];

    return Material(
      key: ValueKey('got-fet-sample-$module-$_selectedSampleIndex'),
      color: Colors.transparent,
      child: InkWell(
        onTap: sampleIndexes.isEmpty
            ? null
            : () => _openSampleSearchSheet(module: module),
        borderRadius: AdvantaRadius.inputRadius,
        child: InputDecorator(
          isEmpty: selectedSample == null,
          decoration: InputDecoration(
            labelText: module == null ? 'Lot / Sample' : '$module Lot / Sample',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
            filled: true,
            fillColor: theme.inputDecorationTheme.fillColor,
          ),
          child: selectedSample == null
              ? Text(
                  sampleIndexes.isEmpty
                      ? 'Tidak ada lot/sample'
                      : 'Cari Lot ID, Batch, Hybrid, atau Status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.body2.copyWith(
                    color: _gotFetMutedColor(context),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${selectedSample.lotId} - ${selectedSample.batch}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.bodyBold.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        selectedSample.hybrid,
                        selectedSample.category,
                        selectedSample.processStage,
                      ].where((value) => value.trim().isNotEmpty).join(' | '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _openSampleSearchSheet({String? module}) async {
    final sampleIndexes = _sampleIndexesForModule(
      module,
      queue: module?.toUpperCase() == 'GOT'
          ? _activeSampleQueue
          : _GotSampleQueue.all,
    );
    if (sampleIndexes.isEmpty) return;

    final controller = TextEditingController();
    var activeFilter = 'Semua';
    final filterOptions = [
      'Semua',
      'Fresh',
      'Resample',
      'Open',
      'Submitted',
      'Approved',
      'Received',
      'Ready to Plant',
      'To Obs. Veg',
      'To Obs. Gen',
      'Waiting Review',
    ];

    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _gotFetCardColor(context),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = controller.text.trim();
            final filteredIndexes = [
              for (final index in sampleIndexes)
                if (_sampleMatchesQuery(_samples[index], query) &&
                    _sampleMatchesFilter(_samples[index], activeFilter))
                  index,
            ];
            final visibleIndexes = filteredIndexes.take(80).toList();
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module == null
                          ? 'Cari Lot / Sample'
                          : 'Cari $module Lot / Sample',
                      style: AdvantaText.heading3.copyWith(
                        color: _strongTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Lot ID, Batch, Hybrid, Lokasi, Status...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Bersihkan pencarian',
                                onPressed: () {
                                  controller.clear();
                                  setSheetState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                        filled: true,
                        fillColor:
                            Theme.of(context).inputDecorationTheme.fillColor,
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final filter in filterOptions) ...[
                            ChoiceChip(
                              label: Text(filter),
                              selected: activeFilter == filter,
                              onSelected: (_) {
                                setSheetState(() => activeFilter = filter);
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      filteredIndexes.length > visibleIndexes.length
                          ? 'Menampilkan ${visibleIndexes.length} dari ${filteredIndexes.length} hasil. Persempit pencarian untuk hasil lebih spesifik.'
                          : '${filteredIndexes.length} hasil ditemukan',
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filteredIndexes.isEmpty
                          ? Center(
                              child: Text(
                                'Lot/sample tidak ditemukan',
                                style: AdvantaText.bodyBold.copyWith(
                                  color: _gotFetMutedColor(context),
                                ),
                              ),
                            )
                          : ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: visibleIndexes.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, position) {
                                final index = visibleIndexes[position];
                                return _SampleSearchTile(
                                  sample: _samples[index],
                                  isSelected: index == _selectedSampleIndex,
                                  statusColor:
                                      _statusColor(_samples[index].status),
                                  onTap: () =>
                                      Navigator.of(sheetContext).pop(index),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();

    if (selectedIndex == null) return;
    HapticFeedback.selectionClick();
    _selectBatchIndex(selectedIndex);
  }

  bool _sampleMatchesQuery(_GotFetSample sample, String query) {
    if (query.isEmpty) return true;

    final normalizedQuery = query.toLowerCase();
    return [
      sample.lotId,
      sample.sampleId,
      sample.batchLotField,
      sample.landAreaName,
      sample.batch,
      sample.hybrid,
      sample.gender,
      sample.typeSeed,
      sample.category,
      sample.cropYear.toString(),
      sample.processStage,
      sample.testType,
      sample.status,
      sample.statusSample,
      sample.location,
      sample.village,
      sample.subDistrict,
      sample.district,
      sample.latitude?.toString() ?? '',
      sample.longitude?.toString() ?? '',
      sample.flagging,
      sample.reasonTesting,
      sample.noteSample,
      sample.pic,
    ].any((value) => value.toLowerCase().contains(normalizedQuery));
  }

  bool _sampleMatchesFilter(_GotFetSample sample, String filter) {
    if (filter == 'Semua') return true;

    final normalizedFilter = filter.toLowerCase();
    final searchableStatus = [
      sample.status,
      sample.statusSample,
      sample.statusGot2,
      sample.statusGotVeg,
      sample.finalStatusGot,
      sample.noteTanam,
    ].join(' ').toLowerCase();

    return searchableStatus.contains(normalizedFilter);
  }

  Widget _buildLotSummaryCard() {
    final sample = _selectedSample;
    final statusColor = _statusColor(sample.status);
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sample.lotId,
                  style: AdvantaText.heading2.copyWith(
                    color: _strongTextColor(context),
                  ),
                ),
              ),
              _StatusPill(label: sample.status, color: statusColor),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _MiniFact(label: 'Hybrid', value: sample.hybrid)),
              Expanded(
                  child: _MiniFact(label: 'Test Type', value: sample.testType)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _MiniFact(label: 'PIC', value: sample.pic)),
              Expanded(
                  child: _MiniFact(
                      label: 'Due', value: _dateFormat.format(sample.dueDate))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child:
                    _MiniFact(label: 'Status Workflow', value: sample.status),
              ),
              Expanded(
                child: _MiniFact(
                    label: 'Status Sample', value: sample.statusSample),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShipmentInfoCard() {
    final sample = _selectedSample;
    final commercialQty = sample.commercialQtyInventory == null
        ? '-'
        : _formatNumber(sample.commercialQtyInventory!);

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data Pengiriman',
            style: AdvantaText.heading3.copyWith(
              color: _strongTextColor(context),
            ),
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Batch', value: sample.batch),
          const SizedBox(height: 8),
          _InfoRow(label: 'Process Stage', value: sample.processStage),
          const SizedBox(height: 8),
          _InfoRow(label: 'Qty by DSS', value: _formatNumber(sample.qtyByDss)),
          const SizedBox(height: 8),
          _InfoRow(label: 'Commercial Qty Inventory', value: commercialQty),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Delivery Date 1',
              value: _formatDate(sample.deliveryDate1)),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Delivery Date 2',
              value: _formatDate(sample.deliveryDate2)),
          const SizedBox(height: 8),
          _InfoRow(label: 'Flagging', value: sample.flagging),
          const SizedBox(height: 8),
          _InfoRow(label: 'Reason Testing', value: sample.reasonTesting),
          const SizedBox(height: 8),
          _InfoRow(label: 'Status Sample', value: sample.statusSample),
        ],
      ),
    );
  }

  Widget _buildTrackingActionCard({VoidCallback? onConfirmed}) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Konfirmasi Tracking',
            style: AdvantaText.heading3.copyWith(
              color: _strongTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Gunakan tombol ini untuk mencatat progress sample sebelum tanam, termasuk request new sample bila sample tidak bisa diamati.',
            style: AdvantaText.body2.copyWith(
              color: _gotFetMutedColor(context),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final itemWidth = compact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 20) / 3;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.move_to_inbox_rounded),
                      label: const Text('Diterima'),
                      onPressed: _isSyncing
                          ? null
                          : () => _confirmTrackingStatus(
                                'Received',
                                onConfirmed: onConfirmed,
                              ),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.grass_rounded),
                      label: const Text('Siap Tanam'),
                      onPressed: _isSyncing
                          ? null
                          : () => _confirmTrackingStatus(
                                'Ready to Plant',
                                onConfirmed: onConfirmed,
                              ),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.change_circle_rounded),
                      label: const Text('Request Sample'),
                      onPressed: _isSyncing
                          ? null
                          : () => _confirmTrackingStatus(
                                'Request New Sample',
                                remarks:
                                    'Sample tidak bisa diamati, request new sample.',
                                onConfirmed: onConfirmed,
                              ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLotReviewActionCard({VoidCallback? onSubmitted}) {
    final module = _activeModuleCode;
    final sample = _selectedSample;

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Review Lot $module',
                  style: AdvantaText.heading3.copyWith(
                    color: _strongTextColor(context),
                  ),
                ),
              ),
              _StatusPill(
                label: _sampleObservationLabel(sample),
                color: _sampleObservationColor(sample),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Gunakan setelah hasil pengamatan lot ini dicek ulang.',
            style: AdvantaText.body2.copyWith(
              color: _gotFetMutedColor(context),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.rate_review_rounded),
                  label: const Text('Need Review'),
                  onPressed: _isSyncing
                      ? null
                      : () => _submitReviewDecision(
                            'Revision Required',
                            displayStatus: 'Need Review',
                            onSubmitted: onSubmitted,
                          ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('Confirmed'),
                  onPressed: _isSyncing
                      ? null
                      : () => _submitReviewDecision(
                            'Approved',
                            displayStatus: 'Confirmed',
                            onSubmitted: onSubmitted,
                          ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualDatabaseCard() {
    final sample = _selectedSample;
    final commercialQty = sample.commercialQtyInventory == null
        ? '-'
        : _formatNumber(sample.commercialQtyInventory!);

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data Admin Lab',
              style: AdvantaText.heading3.copyWith(
                color: _strongTextColor(context),
              )),
          const SizedBox(height: 12),
          _InfoRow(label: 'Batch', value: sample.batch),
          const SizedBox(height: 8),
          _InfoRow(label: 'Gender', value: sample.gender),
          const SizedBox(height: 8),
          _InfoRow(label: 'Type Seed', value: sample.typeSeed),
          const SizedBox(height: 8),
          _InfoRow(label: 'Category', value: sample.category),
          const SizedBox(height: 8),
          _InfoRow(label: 'Crop Year', value: sample.cropYear.toString()),
          const SizedBox(height: 8),
          _InfoRow(label: 'Process Stage', value: sample.processStage),
          const SizedBox(height: 8),
          _InfoRow(label: 'Qty by DSS', value: _formatNumber(sample.qtyByDss)),
          const SizedBox(height: 8),
          _InfoRow(label: 'Commercial Qty Inventory', value: commercialQty),
          const SizedBox(height: 8),
          _InfoRow(label: 'Flagging', value: sample.flagging),
          const SizedBox(height: 8),
          _InfoRow(label: 'Reason Testing', value: sample.reasonTesting),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Delivery Date 1',
              value: _formatDate(sample.deliveryDate1)),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Delivery Date 2',
              value: _formatDate(sample.deliveryDate2)),
          const SizedBox(height: 8),
          _InfoRow(label: 'Status GOT 2', value: sample.statusGot2),
          const SizedBox(height: 8),
          _InfoRow(label: 'Payment', value: sample.payment),
        ],
      ),
    );
  }

  Widget _buildPlantingScheduleCard() {
    final sample = _selectedSample;

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Input Tim $_activeModuleCode',
              style: AdvantaText.heading3.copyWith(
                color: _strongTextColor(context),
              )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text('Planting Date: ${_formatDate(sample.plantingDate)}'),
              onPressed: _pickPlantingDate,
            ),
          ),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Week Of Planting',
              value: sample.weekOfPlanting?.toString() ?? '-'),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Result Estimation',
              value: _formatDate(sample.resultEstimation)),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Week of Result Est.',
              value: sample.weekOfResultEstimation?.toString() ?? '-'),
          if (_activeModule == _InspectionModule.fet) ...[
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Jadwal Observasi Day 7',
              value: _formatDate(
                sample.plantingDate?.add(const Duration(days: 7)),
              ),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Jadwal Observasi Day 11',
              value: _formatDate(
                sample.plantingDate?.add(const Duration(days: 11)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildGotDropdown<String>(
            label: 'Note Tanam',
            helperText:
                'Progress pekerjaan tanam: On Process, Done, atau Resampling.',
            value: sample.noteTanam,
            options: _gotNoteTanamOptions,
            text: (value) => value,
            onChanged: (value) {
              setState(() => sample.noteTanam = value);
              _persistSelectedSamplePlanning();
            },
          ),
          const SizedBox(height: 10),
          _buildVillageCoordinateSelector(sample),
          const SizedBox(height: 10),
          _buildFieldIdentitySelector(sample),
          const SizedBox(height: 10),
          _buildManualFieldAreaField(sample),
          const SizedBox(height: 10),
          _buildGotDropdown<String>(
            label: 'Status Sample',
            value: sample.statusSample,
            helperText:
                'Kondisi/iterasi material sample; berbeda dari status workflow lot.',
            options: _gotStatusSampleOptions,
            text: (value) => value,
            onChanged: (value) {
              setState(() => sample.statusSample = value);
              _persistSelectedSamplePlanning();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFieldIdentitySelector(_GotFetSample sample) {
    final landName = sample.landAreaName.trim();
    final fieldBatch = sample.batchLotField.trim();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openFieldIdentityEditor(sample),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Identitas Lahan / Batch Lot Field',
          helperText:
              'Nama area boleh dibuat tim GOT; nomor lot pabrik tetap menjadi referensi data.',
          prefixIcon: Icon(Icons.landscape_rounded),
          filled: true,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    landName.isEmpty ? 'Nama lahan belum diisi' : landName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdvantaText.bodyBold.copyWith(
                      color: _gotFetTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    fieldBatch.isEmpty
                        ? 'Batch lot field belum diisi'
                        : 'Batch field: $fieldBatch',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdvantaText.caption.copyWith(
                      color: _gotFetMutedColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _openFieldIdentityEditor(_GotFetSample sample) async {
    final landController = TextEditingController(text: sample.landAreaName);
    final batchController = TextEditingController(text: sample.batchLotField);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Identitas Lahan GOT'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: landController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Nama Lahan / Area',
                  hintText: 'Contoh: Area Ngantru Utara',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: batchController,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Batch Lot Field',
                  hintText: 'Contoh: GOT-NGANTRU-01',
                  helperText:
                      'Dipakai pada nametag field; lot pabrik tetap dipakai untuk proses dan sinkronisasi.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        sample.landAreaName = landController.text.trim();
        sample.batchLotField = batchController.text.trim();
      });
      await _persistSelectedSamplePlanning(showResult: true);
    }
    landController.dispose();
    batchController.dispose();
  }

  Widget _buildManualFieldAreaField(_GotFetSample sample) {
    final note = sample.fieldAreaNote.trim();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openFieldAreaEditor(sample),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Field Area / Luasan',
          prefixIcon: Icon(Icons.straighten_rounded),
          filled: true,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatArea(sample.fieldArea),
                    style: AdvantaText.body1.copyWith(
                      color: _strongTextColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.edit_rounded,
              size: 20,
              color: _gotFetMutedColor(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFieldAreaEditor(_GotFetSample sample) async {
    final areaController = TextEditingController(
      text: FieldAreaRules.inputValue(sample.fieldArea),
    );
    final noteController = TextEditingController(text: sample.fieldAreaNote);
    String? validationError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Input Luasan Manual'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: areaController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Luasan',
                        hintText: 'Contoh: 0,0125',
                        suffixText: 'ha',
                        errorText: validationError,
                      ),
                      onChanged: (_) {
                        if (validationError == null) return;
                        setDialogState(() => validationError = null);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pilihan cepat',
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in _gotFieldAreaOptions)
                          ActionChip(
                            label: Text(_formatArea(option)),
                            onPressed: () {
                              areaController.text =
                                  FieldAreaRules.inputValue(option);
                              setDialogState(() => validationError = null);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      maxLength: 250,
                      decoration: const InputDecoration(
                        labelText: 'Catatan Luasan (opsional)',
                        hintText:
                            'Contoh: luasan efektif setelah dikurangi border',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Simpan Luasan'),
                  onPressed: () async {
                    final parsed =
                        FieldAreaRules.parseHectares(areaController.text);
                    if (parsed == null) {
                      setDialogState(() {
                        validationError =
                            'Masukkan angka luasan lebih besar dari 0.';
                      });
                      return;
                    }

                    setState(() {
                      sample.fieldArea = parsed;
                      sample.fieldAreaNote = noteController.text.trim();
                    });
                    Navigator.of(dialogContext).pop();
                    await _persistSelectedSamplePlanning(showResult: true);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    areaController.dispose();
    noteController.dispose();
  }

  Widget _buildPlantingBoundaryCard() {
    final color =
        _gotPlanningReady ? AdvantaColors.success : AdvantaColors.gold;

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Batas Proses Data Tanam',
                  style: AdvantaText.heading3.copyWith(
                    color: _strongTextColor(context),
                  ),
                ),
              ),
              _StatusPill(
                label: _gotPlanningReady ? 'Lengkap' : 'Belum lengkap',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _activeModule == _InspectionModule.fet
                ? 'Data tanam ini menjadi acuan jadwal Observasi Day 7 dan Day 11. Foto serta hasil FET baru dapat diproses setelah data tanam lengkap.'
                : 'Halaman ini menyimpan tanggal tanam, lokasi, field area, status sample, dan estimasi hasil. Submit GOT dilakukan dari menu Vegetatif atau Generative.',
            style: AdvantaText.body2.copyWith(
              color: _gotFetMutedColor(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save_rounded),
              label: const Text('Simpan & Tandai Tanam'),
              onPressed: _isSyncing || !_gotPlanningReady
                  ? null
                  : _markSelectedSamplePlanted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVillageCoordinateSelector(_GotFetSample sample) {
    final hasCoordinate = sample.latitude != null && sample.longitude != null;
    final displayName = sample.landAreaName.trim().isNotEmpty
        ? sample.landAreaName.trim()
        : sample.location;
    final subtitle = _isLoadingVillageCoordinates
        ? 'Memuat Village Coordinate...'
        : _villageCoordinateLoadError != null
            ? 'Gagal memuat: $_villageCoordinateLoadError'
            : hasCoordinate
                ? '${sample.landAreaName.trim().isEmpty ? '' : '${sample.location} • '}'
                    '${sample.latitude!.toStringAsFixed(6)}, ${sample.longitude!.toStringAsFixed(6)}'
                : 'Pilih desa dari master_fields';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isLoadingVillageCoordinates ? null : _openVillageCoordinatePicker,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Village Coordinate',
          prefixIcon: Icon(Icons.location_on_rounded),
          filled: true,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sample.village == '-' ? 'Belum dipilih' : displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AdvantaText.caption.copyWith(
                      color: _gotFetMutedColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }

  Future<void> _openVillageCoordinatePicker() async {
    var query = '';
    final selected = await showModalBottomSheet<_VillageCoordinate>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final normalized = query.trim().toLowerCase();
            final filtered = _villageCoordinates.where((village) {
              if (normalized.isEmpty) return true;
              return [
                village.village,
                village.subDistrict,
                village.district,
                village.region,
                village.coordinateLabel,
              ].join(' ').toLowerCase().contains(normalized);
            }).toList();
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pilih Village Coordinate',
                      style: AdvantaText.heading3.copyWith(
                        color: _strongTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Cari desa, kecamatan, kabupaten...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) {
                        setSheetState(() => query = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('Village Coordinate tidak ditemukan'),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final village = filtered[index];
                                return ListTile(
                                  leading: const Icon(Icons.place_outlined),
                                  title: Text(village.locationLabel),
                                  subtitle: Text(
                                    '${village.coordinateLabel} • ${village.sourceCount} sumber',
                                  ),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, village),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected == null || !mounted) return;
    final sample = _selectedSample;
    setState(() {
      sample.location = selected.locationLabel;
      sample.village = selected.village;
      sample.subDistrict = selected.subDistrict;
      sample.district = selected.district;
      sample.latitude = selected.latitude;
      sample.longitude = selected.longitude;
    });
    await _persistSelectedSamplePlanning();
  }

  Widget _buildGotDropdown<T>({
    required String label,
    required T? value,
    String? helperText,
    required List<T> options,
    required String Function(T value) text,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey('got-dropdown-$label-$value'),
      initialValue: options.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        helperText: helperText,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
      ),
      items: [
        for (final option in options)
          DropdownMenuItem<T>(
            value: option,
            child: Text(text(option), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }

  Widget _buildLotIdentityCard({
    required List<(String, String)> extraRows,
  }) {
    final rows = [
      ('Lot ID', _selectedSample.lotId),
      ('Hybrid', _selectedSample.hybrid),
      if (_selectedSample.batchLotField.trim().isNotEmpty)
        ('Batch Lot Field', _selectedSample.batchLotField),
      if (_selectedSample.landAreaName.trim().isNotEmpty)
        ('Nama Lahan', _selectedSample.landAreaName),
      ('Category', _selectedSample.category),
      ('Status Workflow', _selectedSample.status),
      ('Location', _selectedSample.location),
      ...extraRows,
    ];

    return _PanelCard(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _InfoRow(label: rows[i].$1, value: rows[i].$2),
            if (i != rows.length - 1) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }

  Widget _buildGotStageSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_GotObservationStage>(
        segments: const [
          ButtonSegment<_GotObservationStage>(
            value: _GotObservationStage.vegetative,
            label: Text('Vegetatif'),
          ),
          ButtonSegment<_GotObservationStage>(
            value: _GotObservationStage.finalGenerative,
            label: Text('Generative'),
          ),
        ],
        selected: {_gotObservationStage},
        onSelectionChanged: (selection) {
          _setGotObservationStage(selection.first);
        },
      ),
    );
  }

  Widget _buildGotStageLockBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _gotStageAccentColor.withAlpha(
          _gotFetIsDark(context) ? 54 : 24,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gotStageAccentColor.withAlpha(120)),
      ),
      child: Row(
        children: [
          Icon(_gotStageIcon, color: _gotStageAccentColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Fase terkunci: $_gotObservationStageLabel. Untuk fase lain, kembali ke menu GOT lalu pilih Vegetatif atau Generative.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AdvantaText.bodyBold.copyWith(
                color: _gotFetTextColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(_GotFetSample sample) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status Pengiriman',
              style: AdvantaText.heading3.copyWith(
                color: _strongTextColor(context),
              )),
          const SizedBox(height: 14),
          for (var i = 0; i < sample.steps.length; i++)
            _TimelineRow(
              step: sample.steps[i],
              isLast: i == sample.steps.length - 1,
              dateTimeFormat: _dateTimeFormat,
            ),
        ],
      ),
    );
  }

  Widget _buildGotCountForm() {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hasil Pengamatan',
              style: AdvantaText.heading3.copyWith(
                color: _strongTextColor(context),
              )),
          const SizedBox(height: 12),
          _buildGotObservationSyncStatus(),
          const SizedBox(height: 12),
          _CounterRow(
            label: 'Total Tanaman Diamati',
            value: _gotTotalObserved,
            controller: _gotTotalObservedController,
            onAdd: () => _adjustGotCount('total', 1),
            onRemove: () => _adjustGotCount('total', -1),
            onChanged: (value) => _setGotCountFromText('total', value),
          ),
          _CounterRow(
            label: 'Off-type',
            value: _gotOffType,
            controller: _gotOffTypeController,
            onAdd: () => _adjustGotCount('offType', 1),
            onRemove: () => _adjustGotCount('offType', -1),
            onChanged: (value) => _setGotCountFromText('offType', value),
          ),
          _CounterRow(
            label: 'Selfing',
            value: _gotSelfing,
            controller: _gotSelfingController,
            onAdd: () => _adjustGotCount('selfing', 1),
            onRemove: () => _adjustGotCount('selfing', -1),
            onChanged: (value) => _setGotCountFromText('selfing', value),
          ),
          _CounterRow(
            label: 'Male',
            value: _gotMale,
            controller: _gotMaleController,
            onAdd: () => _adjustGotCount('male', 1),
            onRemove: () => _adjustGotCount('male', -1),
            onChanged: (value) => _setGotCountFromText('male', value),
          ),
          _CounterRow(
            label: 'Tanaman Meragukan',
            value: _gotSuspicious,
            controller: _gotSuspiciousController,
            onAdd: () => _adjustGotCount('suspicious', 1),
            onRemove: () => _adjustGotCount('suspicious', -1),
            onChanged: (value) => _setGotCountFromText('suspicious', value),
          ),
          const Divider(height: 26),
          _InfoRow(
            label: 'Formula / Kelas',
            value: _gotCalculationReference,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Purity (%)',
            value: _gotCountsValid ? _gotPurity.toStringAsFixed(2) : 'Invalid',
            valueColor: _gotCountsValid ? _gotResultColor : AdvantaColors.error,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Acuan PASS',
            value: _gotPassFailReference,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Status Hasil',
            value: _gotResultLabel,
            valueColor: _gotResultColor,
          ),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Offtype (%)',
              value: _gotCountsValid
                  ? _gotOffTypePercent.toStringAsFixed(2)
                  : 'Invalid'),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Selfing (%)',
              value: _gotCountsValid
                  ? _gotSelfingPercent.toStringAsFixed(2)
                  : 'Invalid'),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Male (%)',
              value: _gotCountsValid
                  ? _gotMalePercent.toStringAsFixed(2)
                  : 'Invalid'),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Total (%)',
              value: _gotCountsValid ? '100.00' : 'Invalid'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Kolom Status Manual', value: _gotStatusColumnLabel),
        ],
      ),
    );
  }

  Widget _buildGotObservationSyncStatus() {
    final isError = _gotObservationLoadError != null;
    final icon = isError
        ? Icons.cloud_off_rounded
        : _isLoadingGotObservation
            ? Icons.cloud_sync_rounded
            : _hasPersistedGotObservation
                ? Icons.cloud_done_rounded
                : Icons.add_circle_outline_rounded;
    final color = isError
        ? AdvantaColors.error
        : _isLoadingGotObservation
            ? AdvantaColors.warning
            : _hasPersistedGotObservation
                ? AdvantaColors.success
                : _gotFetMutedColor(context);
    final text = isError
        ? 'Gagal memuat input database: $_gotObservationLoadError'
        : _isLoadingGotObservation
            ? 'Memuat input terakhir dari database...'
            : _hasPersistedGotObservation
                ? 'Menggunakan input tersimpan dari database. Tetap bisa diedit.'
                : 'Belum ada input tersimpan. Counter dimulai dari 0.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(_gotFetIsDark(context) ? 42 : 22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AdvantaText.caption.copyWith(
                color: _gotFetTextColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGotEvidenceSummaryCard() {
    final slots = _gotEvidenceSlots;
    final filledCount = [
      for (final slot in slots)
        if (_gotEvidenceBySlot.containsKey(slot.key)) slot,
    ].length;

    return _PanelCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AdvantaColors.green.withAlpha(
                _gotFetIsDark(context) ? 44 : 22,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.photo_library_rounded,
              color: AdvantaColors.greenDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Foto Evidence GOT',
                  style: AdvantaText.bodyBold.copyWith(
                    color: _gotFetTextColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  slots.isEmpty
                      ? 'Isi hasil pengamatan untuk membentuk folder evidence.'
                      : '$filledCount dari ${slots.length} slot evidence terisi',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.caption.copyWith(
                    color: _gotFetMutedColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(
            label: _gotObservationStageLabel,
            color: _gotStageAccentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSmartCameraStatusCard({required String module}) {
    final pending = _smartPhotoStatus.pendingUploads;
    final isDark = _gotFetIsDark(context);
    final color = pending == 0 ? AdvantaColors.success : AdvantaColors.warning;
    final lastQueuedText = _smartPhotoStatus.lastQueuedAt == null
        ? null
        : _dateTimeFormat.format(_smartPhotoStatus.lastQueuedAt!.toLocal());
    final fetMetadata = _currentFetPlotPhotoMetadata;
    final fetSummary = module == 'FET' && fetMetadata != null
        ? fetMetadata.warnings.isEmpty
            ? 'Watermark Lot & Ulangan tercetak • foto lolos smart check'
            : 'Watermark tercetak • cek plot: ${fetMetadata.warnings.join(', ')}'
        : null;

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withAlpha(isDark ? 44 : 22),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Camera $module',
                      style: AdvantaText.bodyBold.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      pending == 0
                          ? (fetSummary ??
                              'Quality check, duplicate guard, watermark metadata aktif')
                          : '$pending foto menunggu sync${lastQueuedText == null ? '' : ' | $lastQueuedText'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Sync foto offline',
                onPressed: _isRetryingPhotoQueue
                    ? null
                    : () => _drainSmartPhotoQueue(showResult: true),
                icon: _isRetryingPhotoQueue
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(label: 'Offline queue', color: color),
              _StatusPill(
                  label: 'Blur/gelap check', color: AdvantaColors.green),
              _StatusPill(label: 'Duplicate hash', color: AdvantaColors.green),
              _StatusPill(
                  label: 'Metadata watermark', color: AdvantaColors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGotEvidenceFolders() {
    if (_isLoadingGotObservation || _isLoadingGotEvidence) {
      return _PanelCard(
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Memuat folder evidence dari database...',
                style: AdvantaText.body2.copyWith(
                  color: _gotFetMutedColor(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_gotEvidenceLoadError != null) {
      return _PanelCard(
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: AdvantaColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Gagal memuat foto evidence: $_gotEvidenceLoadError',
                style: AdvantaText.body2.copyWith(
                  color: _gotFetTextColor(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final categoryCards = [
      for (final category in _GotEvidenceCategory.values)
        if (category != _GotEvidenceCategory.offType)
          _buildGotEvidenceCategoryCard(category),
    ];

    return Column(
      children: [
        for (var i = 0; i < categoryCards.length; i++) ...[
          categoryCards[i],
          if (i != categoryCards.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildGotEvidenceCategoryCard(_GotEvidenceCategory category) {
    final slots = _gotEvidenceSlotsForCategory(category);
    final filledCount = [
      for (final slot in slots)
        if (_gotEvidenceBySlot.containsKey(slot.key)) slot,
    ].length;
    final count = _gotEvidenceCountForCategory(category);
    final color = _gotEvidenceCategoryColor(category);
    final folderPath =
        '${_selectedSample.lotId} / $_gotObservationStageLabel / ${category.title}';

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withAlpha(_gotFetIsDark(context) ? 42 : 22),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(category.icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: AdvantaText.bodyBold.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Jumlah ${category.title}: $count | $filledCount/${slots.length} foto pendukung (maks $_gotMaxEvidenceSlotsPerCategory)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                label:
                    slots.isEmpty ? 'Kosong' : '$filledCount/${slots.length}',
                color: slots.isNotEmpty && filledCount == slots.length
                    ? AdvantaColors.success
                    : AdvantaColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Folder: $folderPath',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AdvantaText.caption.copyWith(
              color: _gotFetMutedColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (slots.isEmpty)
            _GotEvidenceEmptyFolder(
              category: category,
              count: count,
            )
          else
            for (var i = 0; i < slots.length; i++) ...[
              _GotEvidenceSlotTile(
                slot: slots[i],
                photo: _gotEvidenceBySlot[slots[i].key],
                color: color,
                syncing: _syncingGotEvidenceSlotKey == slots[i].key,
                onCapture: () =>
                    _pickGotEvidenceForSlot(slots[i], ImageSource.camera),
                onGallery: () =>
                    _pickGotEvidenceForSlot(slots[i], ImageSource.gallery),
                onView: _gotEvidenceBySlot[slots[i].key] == null
                    ? null
                    : () => _openGotEvidenceViewer(
                          slots[i],
                          _gotEvidenceBySlot[slots[i].key]!,
                        ),
              ),
              if (i != slots.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  List<_GotEvidenceSlot> get _gotEvidenceSlots => [
        for (final detail in _gotOffTypeDetails)
          ..._gotOffTypeSlotsForDetail(detail),
      ];

  List<_GotEvidenceSlot> _gotEvidenceSlotsForCategory(
    _GotEvidenceCategory category,
  ) {
    final slotCount = _gotEvidenceSlotCountForCategory(category);
    if (category == _GotEvidenceCategory.trueType) {
      if (_gotTrueType <= 0) return const [];
      final labels =
          GotRevisionRules.trueTypePhotoLabels(_gotObservationStagePayload);
      return [
        for (var index = 0; index < labels.length; index++)
          _GotEvidenceSlot(
            category: category,
            rcvNo: index + 1,
            customLabel: 'TT1 - ${labels[index]}',
          ),
      ];
    }

    return [
      for (var i = 1; i <= slotCount; i++)
        _GotEvidenceSlot(category: category, rcvNo: i),
    ];
  }

  int _gotEvidenceSlotCountForCategory(_GotEvidenceCategory category) {
    final count = _gotEvidenceCountForCategory(category);
    if (count <= 0) return 0;
    return math.min(count, _gotMaxEvidenceSlotsPerCategory);
  }

  int _gotEvidenceCountForCategory(_GotEvidenceCategory category) {
    return switch (category) {
      _GotEvidenceCategory.trueType => _gotTrueType,
      _GotEvidenceCategory.offType => _gotOffType,
      _GotEvidenceCategory.selfing => _gotSelfing,
      _GotEvidenceCategory.male => _gotMale,
    };
  }

  Color _gotEvidenceCategoryColor(_GotEvidenceCategory category) {
    return switch (category) {
      _GotEvidenceCategory.trueType => AdvantaColors.success,
      _GotEvidenceCategory.offType => AdvantaColors.error,
      _GotEvidenceCategory.selfing => const Color(0xFF5B5BD6),
      _GotEvidenceCategory.male => AdvantaColors.navy,
    };
  }

  Widget _buildGotOffTypeDetailsCard({bool readOnly = false}) {
    final actual = _gotOffTypeDetails.length;
    final ready = _gotOffTypeDetailsReady;
    final color = ready ? AdvantaColors.success : AdvantaColors.warning;

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_folder_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Detail Off-Type',
                  style: AdvantaText.heading3.copyWith(
                    color: _strongTextColor(context),
                  ),
                ),
              ),
              _StatusPill(label: '$actual jenis karakter', color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _gotOffType == 0
                ? 'Tidak ada Off-Type pada hasil pengamatan.'
                : 'Ada $_gotOffType temuan. Tambahkan satu detail untuk setiap jenis karakter yang berbeda; jumlah detail tidak harus sama dengan jumlah temuan. Setiap jenis wajib memiliki $_gotRequiredOffTypePhotosPerSample foto $_gotObservationStageLabel.',
            style: AdvantaText.body2.copyWith(
              color: _gotFetMutedColor(context),
              height: 1.35,
            ),
          ),
          if (_isLoadingGotOffTypes) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_gotOffTypeLoadError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Detail Off-Type belum dapat dimuat: $_gotOffTypeLoadError',
              style: AdvantaText.caption.copyWith(color: AdvantaColors.error),
            ),
          ],
          for (var index = 0; index < _gotOffTypeDetails.length; index++) ...[
            const SizedBox(height: 12),
            _buildGotOffTypeDetailItem(
              _gotOffTypeDetails[index],
              index: index,
              readOnly: readOnly,
            ),
          ],
          if (!readOnly && _gotOffType > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openGotOffTypeEditor,
                icon: const Icon(Icons.add_rounded),
                label: Text('Tambah Jenis Karakter Off-Type ${actual + 1}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGotOffTypeDetailItem(
    _GotOffTypeDetail detail, {
    required int index,
    required bool readOnly,
  }) {
    final slots = _gotOffTypeSlotsForDetail(detail);
    final filled =
        slots.where((slot) => _gotEvidenceBySlot.containsKey(slot.key)).length;
    final ready = filled == slots.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gotFetBorderColor(context)),
        color: _gotStageAccentColor.withAlpha(
          _gotFetIsDark(context) ? 20 : 10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'OT ${index + 1} • ${detail.title}',
                  style: AdvantaText.bodyBold.copyWith(
                    color: _gotFetTextColor(context),
                  ),
                ),
              ),
              _StatusPill(
                label: '$filled/${slots.length} foto',
                color: ready ? AdvantaColors.success : AdvantaColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail.similarity.label,
            style: AdvantaText.caption.copyWith(
              color: _gotFetMutedColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (detail.referenceHybrid.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Pembanding: ${detail.referenceHybrid}'),
          ],
          const SizedBox(height: 6),
          Text('Karakter: ${detail.characterNote}'),
          const SizedBox(height: 10),
          if (readOnly)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final slot in slots)
                  _StatusPill(
                    label: _gotEvidenceBySlot.containsKey(slot.key)
                        ? '${slot.label} ada'
                        : '${slot.label} kosong',
                    color: _gotEvidenceBySlot.containsKey(slot.key)
                        ? AdvantaColors.success
                        : AdvantaColors.warning,
                  ),
              ],
            )
          else
            for (var i = 0; i < slots.length; i++) ...[
              _GotEvidenceSlotTile(
                slot: slots[i],
                photo: _gotEvidenceBySlot[slots[i].key],
                color: AdvantaColors.error,
                syncing: _syncingGotEvidenceSlotKey == slots[i].key,
                onCapture: () =>
                    _pickGotEvidenceForSlot(slots[i], ImageSource.camera),
                onGallery: () =>
                    _pickGotEvidenceForSlot(slots[i], ImageSource.gallery),
                onView: _gotEvidenceBySlot[slots[i].key] == null
                    ? null
                    : () => _openGotEvidenceViewer(
                          slots[i],
                          _gotEvidenceBySlot[slots[i].key]!,
                        ),
              ),
              if (i != slots.length - 1) const SizedBox(height: 8),
            ],
          if (!readOnly) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _openGotOffTypeEditor(detail),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => _deleteGotOffTypeDetail(detail),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Hapus'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openGotOffTypeEditor([
    _GotOffTypeDetail? detail,
  ]) async {
    if (_gotOffTypeRules.isEmpty) {
      _showSnack('Master kategori Off-Type belum tersedia.');
      return;
    }
    var selectedRule = _gotOffTypeRules.firstWhere(
      (rule) => rule.id == detail?.ruleId,
      orElse: () => _gotOffTypeRules.first,
    );
    var similarity =
        detail?.similarity ?? _GotOffTypeSimilarity.similarFiOrHybrid;
    var saving = false;
    final characterController =
        TextEditingController(text: detail?.characterNote ?? '');
    final referenceController =
        TextEditingController(text: detail?.referenceHybrid ?? '');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(detail == null
                  ? 'Tambah Detail Off-Type'
                  : 'Edit Detail Off-Type'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedRule.id,
                        decoration:
                            const InputDecoration(labelText: 'Kategori / Tipe'),
                        items: [
                          for (final rule in _gotOffTypeRules)
                            DropdownMenuItem(
                              value: rule.id,
                              child: Text(
                                rule.displayLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedRule = _gotOffTypeRules.firstWhere(
                                    (rule) => rule.id == value,
                                  );
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<_GotOffTypeSimilarity>(
                        initialValue: similarity,
                        decoration: const InputDecoration(
                          labelText: 'Penilaian kemiripan',
                        ),
                        items: [
                          for (final value in _GotOffTypeSimilarity.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() => similarity = value);
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: referenceController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'FI / hybrid pembanding',
                          hintText: 'Optional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: characterController,
                        enabled: !saving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Catatan karakter *',
                          hintText: 'Jelaskan karakter pembeda tanaman',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final character = characterController.text.trim();
                          if (character.isEmpty) {
                            _showSnack('Catatan karakter wajib diisi.');
                            return;
                          }
                          setDialogState(() => saving = true);
                          try {
                            await _gotFetService.saveGotOffTypeDetail(
                              id: detail?.id,
                              lotId: _selectedSample.lotId,
                              sampleId: _selectedSample.sampleId,
                              plotId: _gotPlotId,
                              stage: _gotObservationStagePayload,
                              ruleId: selectedRule.id,
                              categoryNo: selectedRule.categoryNo,
                              typeCode: selectedRule.typeCode,
                              typeLabel: selectedRule.label,
                              characterNote: character,
                              similarityAssessment: similarity.payload,
                              referenceHybrid: referenceController.text.trim(),
                              requiredPhotoCount:
                                  _gotRequiredOffTypePhotosPerSample,
                              sortOrder: detail == null
                                  ? _gotOffTypeDetails.fold<int>(
                                        0,
                                        (maximum, item) =>
                                            math.max(maximum, item.sortOrder),
                                      ) +
                                      1
                                  : detail.sortOrder,
                              actor: _actorName,
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                          } catch (error) {
                            if (!mounted) return;
                            _showSnack(
                              'Gagal simpan detail Off-Type: ${_friendlyError(error)}',
                            );
                            setDialogState(() => saving = false);
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Menyimpan...' : 'Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
    characterController.dispose();
    referenceController.dispose();
  }

  Future<void> _deleteGotOffTypeDetail(
    _GotOffTypeDetail detail,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus detail Off-Type?'),
        content: Text(
          '${detail.title} beserta metadata fotonya akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _gotFetService.deleteGotOffTypeDetail(detail.id);
      if (mounted) _showSnack('Detail Off-Type dihapus.');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Gagal hapus detail: ${_friendlyError(error)}');
    }
  }

  Widget _buildNoteBox({
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'Catatan',
        hintText: 'Tulis catatan optional',
        prefixIcon: const Icon(Icons.notes_rounded),
        filled: true,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
      ),
    );
  }

  Widget _buildFetObservationDaySelector() {
    final plantingDate = _selectedSample.plantingDate;
    final observationDate = plantingDate?.add(Duration(days: _selectedFetDay));

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_view_week_rounded,
                color: AdvantaColors.primaryGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Detail Observasi FET',
                  style: AdvantaText.bodyBold.copyWith(
                    color: _strongTextColor(context),
                  ),
                ),
              ),
              _StatusPill(
                label: 'Day $_selectedFetDay',
                color: AdvantaColors.primaryGreen,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            observationDate == null
                ? 'Lengkapi Planting Date untuk menampilkan jadwal observasi.'
                : 'Jadwal berdasarkan Planting Date: ${_formatDate(observationDate)}',
            style: _mutedTextStyle(context),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 7,
                  label: Text('Observasi Day 7'),
                ),
                ButtonSegment<int>(
                  value: 11,
                  label: Text('Observasi Day 11'),
                ),
              ],
              selected: {_selectedFetDay},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                final day = selection.first;
                if (day == _selectedFetDay) return;
                _setControllerText(_fetNoteController, '');
                setState(() {
                  _selectedFetDay = day;
                  _selectedFetRemark = 'Done';
                  _latestFetObservation = null;
                });
                _queueSelectedFetObservationSync();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFetRemarksCard() {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remarks',
            style: AdvantaText.heading3.copyWith(
              color: _strongTextColor(context),
            ),
          ),
          const SizedBox(height: 12),
          _buildGotDropdown<String>(
            label: 'Status Remarks',
            value: _selectedFetRemark,
            options: FetRevisionRules.remarkOptions,
            text: (value) => value,
            onChanged: (value) => setState(() => _selectedFetRemark = value),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _fetNoteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Catatan Remarks',
              hintText: 'Tambahkan penjelasan Retest, Resampling, atau Done',
              prefixIcon: Icon(Icons.notes_rounded),
              filled: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplicationSelector() {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AdvantaColors.primaryGreen.withAlpha(
                    _gotFetIsDark(context) ? 46 : 24,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.filter_2_rounded,
                  color: AdvantaColors.primaryGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Konteks Day $_selectedFetDay • Ulangan FET',
                      style: AdvantaText.bodyBold.copyWith(
                        color: _strongTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Foto, kroscek, input, dan review mengikuti pilihan aktif.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _mutedTextStyle(context).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                label: 'D$_selectedFetDay • U$_selectedReplication',
                color: AdvantaColors.primaryGreen,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.looks_one_rounded),
                  label: Text('Ulangan 1'),
                ),
                ButtonSegment<int>(
                  value: 2,
                  icon: Icon(Icons.looks_two_rounded),
                  label: Text('Ulangan 2'),
                ),
              ],
              selected: {_selectedReplication},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                final nextReplication = selection.first;
                if (nextReplication == _selectedReplication) return;
                _setControllerText(_fetNoteController, '');
                setState(() {
                  _selectedReplication = nextReplication;
                  _selectedFetRemark = 'Done';
                  _latestFetObservation = null;
                });
                _queueSelectedFetObservationSync();
                _showSnack(
                  'Aktif di Day $_selectedFetDay Ulangan $nextReplication. Foto, hasil, dan remarks ikut berpindah.',
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final replication in const [1, 2])
                _FetReplicationMiniStatus(
                  replication: replication,
                  selected: replication == _selectedReplication,
                  photoReady: _fetPhotoReadyForReplication(replication),
                  submitted: _fetSubmittedForReplication(replication),
                  openItems: _fetOpenItemsForReplication(replication),
                  emergence: _fetEmergenceForReplication(replication),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFetAutoDetectionCard() {
    final result = _fetAutoDetectionBySlot[_currentFetSlotKey];
    final hasPhoto = _currentFetPlotPhoto != null;
    final isAnalyzing = _analyzingFetSlot == _currentFetSlotKey;
    final statusColor = isAnalyzing
        ? AdvantaColors.warning
        : result == null
            ? hasPhoto
                ? AdvantaColors.gold
                : AdvantaColors.mutedGrey
            : result.reviewCount == 0
                ? AdvantaColors.success
                : AdvantaColors.gold;
    final statusLabel = isAnalyzing
        ? 'Analisa'
        : result == null
            ? hasPhoto
                ? 'Siap'
                : 'Belum foto'
            : result.reviewCount == 0
                ? 'Prefill OK'
                : 'Perlu Review';

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(
                    _gotFetIsDark(context) ? 46 : 24,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto Detect Foto Asli',
                      style: AdvantaText.bodyBold.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      result == null
                          ? hasPhoto
                              ? 'Foto asli akan dibagi langsung menjadi grid 10 x 10.'
                              : 'Ambil foto plot agar grid 10 x 10 bisa dianalisa.'
                          : 'Foto asli ${result.sourceWidth}x${result.sourceHeight} dianalisa langsung.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(label: statusLabel, color: statusColor),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  label: '${result.grownCount} tumbuh',
                  color: AdvantaColors.success,
                ),
                _StatusPill(
                  label: '${result.notGrownCount} tidak tumbuh',
                  color: AdvantaColors.error,
                ),
                _StatusPill(
                  label: '${result.reviewCount} review',
                  color: result.reviewCount == 0
                      ? AdvantaColors.success
                      : AdvantaColors.gold,
                ),
                _StatusPill(
                  label:
                      '${result.confidencePercent.toStringAsFixed(0)}% yakin',
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _InfoRow(
              label: 'Grid analisis',
              value: '10 x 10 mengikuti dimensi foto asli',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Metode deteksi',
              value: 'Hijau daun HSV/ExG per cell 10 x 10',
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: isAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_rounded),
              label: Text(
                  isAnalyzing ? 'Menganalisa foto...' : 'Analisa Ulang Foto'),
              onPressed: !hasPhoto || isAnalyzing
                  ? null
                  : () => _runFetAutoDetectionForCurrentPhoto(showResult: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFetPhotoReviewCard() {
    final plotPhoto = _currentFetPlotPhoto;
    final photoAspectRatio = _currentFetPhotoAspectRatio();
    final hasPhoto = plotPhoto != null;

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasPhoto
                      ? 'Kroscek Foto Plot 10 x 10'
                      : 'Visual Grid 10 x 10',
                  style: AdvantaText.heading3.copyWith(
                    color: _strongTextColor(context),
                  ),
                ),
              ),
              _StatusPill(
                label: 'D$_selectedFetDay • U$_selectedReplication',
                color: AdvantaColors.primaryGreen,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasPhoto
                ? 'Tap titik di atas foto untuk ubah status. Long press untuk pilih status langsung.'
                : 'Ambil foto plot dulu agar kroscek bisa dilakukan langsung dari gambar tanaman.',
            style: _mutedTextStyle(context),
          ),
          const SizedBox(height: 12),
          if (hasPhoto)
            _FetPhotoReviewBoard(
              file: plotPhoto,
              aspectRatio: photoAspectRatio,
              points: _currentReplication,
              statusColor: _fetStatusColor,
              statusLabel: _fetStatusShortLabel,
              onTap: _cycleFetPoint,
              onLongPress: _openFetPointStatusSheet,
            )
          else
            _FetPointGrid(
              points: _currentReplication,
              statusColor: _fetStatusColor,
              statusLabel: _fetStatusShortLabel,
              onTap: _cycleFetPoint,
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: '${_currentReplication.length} titik',
                color: AdvantaColors.primaryGreen,
              ),
              _StatusPill(
                label: 'Review zoom maks 4x',
                color: AdvantaColors.green,
              ),
              _StatusPill(
                label: hasPhoto ? 'Foto aktif' : 'Mode grid',
                color: hasPhoto ? AdvantaColors.success : AdvantaColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFetLegend() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final status in _FetPointStatus.values)
          _LegendChip(
            label: _fetStatusLabel(status),
            color: _fetStatusColor(status),
          ),
      ],
    );
  }

  Widget _buildFetInputForm() {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hasil Day $_selectedFetDay • Ulangan $_selectedReplication',
              style: AdvantaText.heading3.copyWith(
                color: _strongTextColor(context),
              )),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Total Titik Tanam',
            value: '${_currentReplication.length}',
          ),
          const SizedBox(height: 9),
          _InfoRow(label: 'Tumbuh', value: _currentReplicationGrown.toString()),
          const SizedBox(height: 9),
          _InfoRow(
              label: 'Tidak Tumbuh',
              value: _currentReplicationNotGrown.toString()),
          const SizedBox(height: 9),
          _InfoRow(
            label: 'Emergence (%)',
            value: _currentReplicationEmergence.toStringAsFixed(2),
            valueColor: AdvantaColors.success,
          ),
          const SizedBox(height: 9),
          _InfoRow(
            label: 'Status Hasil',
            value: _fetResultLabel,
            valueColor: _fetResultColor,
          ),
        ],
      ),
    );
  }

  Widget _buildPlotEvidenceCard() {
    return _PanelCard(
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: AspectRatio(
              aspectRatio: 1.45,
              child: _currentFetPlotPhoto == null
                  ? const _PlotPreview()
                  : _PlotPhotoPreview(file: _currentFetPlotPhoto!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(
                _currentFetPlotPhoto == null
                    ? Icons.add_rounded
                    : Icons.photo_library_rounded,
              ),
              label: Text(
                _currentFetPlotPhoto == null ? 'Tambah Foto' : 'Ganti Foto',
              ),
              onPressed: () => _showEvidenceSourceSheet(
                onCamera: () => _pickFetPlotPhoto(ImageSource.camera),
                onGallery: () => _pickFetPlotPhoto(ImageSource.gallery),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGotReviewResult() {
    return _PanelCard(
      child: Column(
        children: [
          _InfoRow(label: 'Stage Observasi', value: _gotObservationStageLabel),
          const SizedBox(height: 8),
          _InfoRow(label: 'No. Obs', value: _gotObservationNumber),
          const SizedBox(height: 8),
          _InfoRow(label: 'Total Tanaman Diamati', value: '$_gotTotalObserved'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Off-type', value: '$_gotOffType'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Selfing', value: '$_gotSelfing'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Male', value: '$_gotMale'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Tanaman Meragukan', value: '$_gotSuspicious'),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Purity (%)',
            value: _gotPurity.toStringAsFixed(2),
            valueColor: _gotResultColor,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Acuan PASS',
            value: _gotPassFailReference,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Status Hasil',
            value: _gotResultLabel,
            valueColor: _gotResultColor,
          ),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Offtype (%)',
              value: _gotOffTypePercent.toStringAsFixed(2)),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Selfing (%)',
              value: _gotSelfingPercent.toStringAsFixed(2)),
          const SizedBox(height: 8),
          _InfoRow(
              label: 'Male (%)', value: _gotMalePercent.toStringAsFixed(2)),
          const SizedBox(height: 12),
          _InfoRow(label: 'Foto Evidence', value: _gotEvidenceProgressText),
        ],
      ),
    );
  }

  Widget _buildFetReviewResult() {
    final result = _latestFetObservation;
    final totalPoints = result?.totalPoints ?? _currentReplication.length;
    final grown = result?.grownCount ?? _currentReplicationGrown;
    final notGrown = result?.notGrownCount ?? _currentReplicationNotGrown;
    final review = result?.reviewCount ?? _currentReplicationReview;
    final notReadable =
        result?.notReadableCount ?? _currentReplicationNotReadable;
    final emergence = result?.emergencePercent ?? _currentReplicationEmergence;
    final resultLabel = review + notReadable == 0 ? 'PASS' : 'FAIL';
    final resultColor =
        resultLabel == 'PASS' ? AdvantaColors.success : AdvantaColors.error;

    return _PanelCard(
      child: Column(
        children: [
          _InfoRow(label: 'Plot', value: result?.plotId ?? _fetPlotId),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Observasi',
            value:
                'Day ${result?.dap ?? _selectedFetDay} • Ulangan ${result?.replication ?? _selectedReplication}',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Data Review',
            value: result == null
                ? 'Belum ada submit tersimpan'
                : 'Submitted${result.submittedAt == null ? '' : ' | ${_dateTimeFormat.format(result.submittedAt!.toLocal())}'}',
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Total Titik Tanam', value: '$totalPoints'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Tumbuh', value: '$grown'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Tidak Tumbuh', value: '$notGrown'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Review', value: '$review'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Tidak Terbaca', value: '$notReadable'),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Emergence (%)',
            value: emergence.toStringAsFixed(2),
            valueColor: AdvantaColors.success,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Status Hasil',
            value: resultLabel,
            valueColor: resultColor,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Remarks',
            value: result?.remarkStatus ?? _selectedFetRemark,
          ),
          if ((result?.remarks?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'Catatan Remarks', value: result!.remarks!),
          ],
        ],
      ),
    );
  }

  Widget _buildFetReviewVisualCard() {
    final result = _latestFetObservation;
    final points = result?.pointStatuses.length == _fetGridPointCount
        ? result!.pointStatuses
        : _currentReplication;
    final localPhoto = _currentFetPlotPhoto;
    final photoAspectRatio = _currentFetPhotoAspectRatio();
    final photoUrl = result?.plotPhotoUrl;
    final hasVisual = localPhoto != null || (photoUrl?.isNotEmpty ?? false);

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Visual Review Plot',
                  style: AdvantaText.heading3.copyWith(
                    color: _strongTextColor(context),
                  ),
                ),
              ),
              _StatusPill(
                label: hasVisual ? 'Foto tersedia' : 'Tanpa foto',
                color:
                    hasVisual ? AdvantaColors.success : AdvantaColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasVisual
                ? 'Overlay grid ini mengikuti status titik yang tersimpan untuk ulangan aktif.'
                : 'Hasil titik tetap bisa direview, tetapi foto plot belum tersedia di data submit.',
            style: _mutedTextStyle(context),
          ),
          const SizedBox(height: 12),
          if (hasVisual)
            _FetReviewPhotoBoard(
              file: localPhoto,
              photoUrl: photoUrl,
              aspectRatio: photoAspectRatio,
              points: points,
              statusColor: _fetStatusColor,
              statusLabel: _fetStatusShortLabel,
            )
          else
            _FetPointGrid(
              points: points,
              statusColor: _fetStatusColor,
              statusLabel: _fetStatusShortLabel,
              onTap: (_) {},
            ),
        ],
      ),
    );
  }

  Widget _buildReviewTimeline() {
    final events = _reviewTimelineEvents.isEmpty
        ? [
            for (final step in _selectedSample.steps)
              _ReviewTimelineEvent(
                label: step.label,
                date: step.date,
                done: step.done,
              ),
          ]
        : _reviewTimelineEvents;

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Riwayat Status',
                    style: AdvantaText.heading3.copyWith(
                      color: _strongTextColor(context),
                    )),
              ),
              _StatusPill(
                label: _reviewTimelineEvents.isEmpty ? 'Fallback' : 'Realtime',
                color: _reviewTimelineEvents.isEmpty
                    ? AdvantaColors.warning
                    : AdvantaColors.success,
              ),
            ],
          ),
          if (_reviewTimelineLoadError != null) ...[
            const SizedBox(height: 8),
            _InlineStatusMessage(
              icon: Icons.cloud_off_rounded,
              color: AdvantaColors.warning,
              text:
                  'Belum bisa memuat riwayat database: $_reviewTimelineLoadError',
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < events.length; i++)
            _TimelineRow(
              step: _TrackingStep(
                events[i].label,
                events[i].date,
                events[i].done,
              ),
              isLast: i == events.length - 1,
              dateTimeFormat: _dateTimeFormat,
              actor: events[i].actor,
              remarks: events[i].remarks,
            ),
        ],
      ),
    );
  }

  void _adjustGotCount(String field, int delta) {
    setState(() {
      switch (field) {
        case 'total':
          _gotTotalObserved = math.max(0, _gotTotalObserved + delta);
          _gotOffType = math.min(_gotOffType, _gotTotalObserved);
          _gotSelfing = math.min(_gotSelfing, _gotTotalObserved);
          _gotMale = math.min(_gotMale, _gotTotalObserved);
          _gotSuspicious = math.min(_gotSuspicious, _gotTotalObserved);
          break;
        case 'offType':
          _gotOffType = _boundedCount(_gotOffType + delta);
          break;
        case 'selfing':
          _gotSelfing = _boundedCount(_gotSelfing + delta);
          break;
        case 'male':
          _gotMale = _boundedCount(_gotMale + delta);
          break;
        case 'suspicious':
          _gotSuspicious = _boundedCount(_gotSuspicious + delta);
          break;
      }
      _syncGotCountControllers();
    });
  }

  int _boundedCount(int value) => value.clamp(0, _gotTotalObserved).toInt();

  void _setGotCountFromText(String field, String rawValue) {
    final value = int.tryParse(rawValue.trim()) ?? 0;
    setState(() {
      switch (field) {
        case 'total':
          _gotTotalObserved = math.max(0, value);
          break;
        case 'offType':
          _gotOffType = math.max(0, value);
          break;
        case 'selfing':
          _gotSelfing = math.max(0, value);
          break;
        case 'male':
          _gotMale = math.max(0, value);
          break;
        case 'suspicious':
          _gotSuspicious = math.max(0, value);
          break;
      }
    });
  }

  void _syncGotCountControllers() {
    _setCounterText(_gotTotalObservedController, _gotTotalObserved);
    _setCounterText(_gotOffTypeController, _gotOffType);
    _setCounterText(_gotSelfingController, _gotSelfing);
    _setCounterText(_gotMaleController, _gotMale);
    _setCounterText(_gotSuspiciousController, _gotSuspicious);
  }

  void _setCounterText(TextEditingController controller, int value) {
    final text = value.toString();
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _cycleFetPoint(int index) {
    final current = _currentReplication[index];
    final next = switch (current) {
      _FetPointStatus.grown => _FetPointStatus.notGrown,
      _FetPointStatus.notGrown => _FetPointStatus.review,
      _FetPointStatus.review => _FetPointStatus.notReadable,
      _FetPointStatus.notReadable => _FetPointStatus.grown,
    };

    setState(() => _currentReplication[index] = next);
  }

  void _setFetPointStatus(int index, _FetPointStatus status) {
    setState(() => _currentReplication[index] = status);
  }

  void _openFetPointStatusSheet(int index) {
    HapticFeedback.selectionClick();
    final pointNo = index + 1;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _gotFetCardColor(context),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Titik Tanam $pointNo',
                      style: AdvantaText.heading3.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                  ),
                  _StatusPill(
                    label: _fetStatusLabel(_currentReplication[index]),
                    color: _fetStatusColor(_currentReplication[index]),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final status in _FetPointStatus.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _fetStatusColor(status).withAlpha(
                      _gotFetIsDark(context) ? 70 : 32,
                    ),
                    child: Text(
                      _fetStatusShortLabel(status),
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetIsDark(context)
                            ? Colors.white
                            : _fetStatusColor(status),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: Text(_fetStatusLabel(status)),
                  trailing: _currentReplication[index] == status
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: _fetStatusColor(status),
                        )
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setFetPointStatus(index, status);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickGotEvidenceForSlot(
    _GotEvidenceSlot slot,
    ImageSource source,
  ) async {
    if (_syncingGotEvidenceSlotKey != null) return;

    try {
      final image = source == ImageSource.camera
          ? await _captureWithStandaloneCamera(
              module: _InspectionModule.got,
              title: '${slot.category.title} - ${slot.label}',
              subtitle: _gotObservationStageLabel,
            )
          : await _imagePicker.pickImage(
              source: source,
              imageQuality: 86,
              maxWidth: 1800,
            );
      if (image == null || !mounted) return;

      final prepared = await _photoPipeline.preparePhoto(
        image: image,
        context: _SmartPhotoContext(
          module: 'got',
          lotId: _selectedSample.lotId,
          sampleId: _selectedSample.sampleId,
          plotId: _gotPlotId,
          stage: _gotObservationStagePayload,
          label: '${slot.category.title} ${slot.label}',
          source: source == ImageSource.camera ? 'camera' : 'gallery',
          actor: _actorName,
        ),
      );
      if (!mounted) return;
      setState(() => _syncingGotEvidenceSlotKey = slot.key);
      try {
        await _gotFetService.saveGotEvidencePhoto(
          file: prepared.file,
          lotId: _selectedSample.lotId,
          sampleId: _selectedSample.sampleId,
          plotId: _gotPlotId,
          stage: _gotObservationStagePayload,
          category: slot.evidenceCategoryKey,
          rcvNo: slot.rcvNo,
          rcvLabel: slot.label,
          uploadedBy: _actorName,
          offTypeDetailId: slot.offTypeDetailId,
        );
      } catch (_) {
        await _photoPipeline.enqueueGotEvidence(
          prepared: prepared,
          slot: slot,
          lotId: _selectedSample.lotId,
          sampleId: _selectedSample.sampleId,
          plotId: _gotPlotId,
          stage: _gotObservationStagePayload,
          uploadedBy: _actorName,
        );
        await _refreshSmartPhotoStatus();
        if (!mounted) return;
        HapticFeedback.selectionClick();
        _showSnack(
          '${slot.label} disimpan offline. Sync otomatis saat dicoba ulang.',
        );
        return;
      }
      if (!mounted) return;
      HapticFeedback.selectionClick();
      await _refreshSmartPhotoStatus();
      final reviewText = prepared.metadata.needsReview
          ? ' Quality: ${prepared.metadata.warnings.join(', ')}.'
          : '';
      final duplicateText =
          prepared.duplicateLikely ? ' Potensi duplikat terdeteksi.' : '';
      _showSnack(
        '${slot.label} ${slot.category.title} tersimpan.$reviewText$duplicateText',
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('Gagal simpan foto ${slot.label}: ${_friendlyError(error)}');
    } finally {
      if (mounted && _syncingGotEvidenceSlotKey == slot.key) {
        setState(() => _syncingGotEvidenceSlotKey = null);
      }
    }
  }

  void _openGotEvidenceViewer(
    _GotEvidenceSlot slot,
    _GotEvidencePhoto photo,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor:
              _gotFetIsDark(context) ? AdvantaColors.navyDark : Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${slot.category.title} - ${slot.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdvantaText.heading3.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.7,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        photo.photoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Text(
                          'Foto tidak bisa dimuat',
                          style: AdvantaText.bodyBold.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Text(
                    [
                      _selectedSample.lotId,
                      _gotObservationStageLabel,
                      photo.rcvLabel,
                      if (photo.uploadedAt != null)
                        _dateTimeFormat.format(photo.uploadedAt!.toLocal()),
                    ].join(' | '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AdvantaText.caption.copyWith(
                      color: Colors.white.withAlpha(215),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runFetAutoDetectionForCurrentPhoto({
    bool showResult = false,
  }) async {
    final file = _currentFetAnalysisPhoto;
    if (file == null || _analyzingFetSlot != null) return;
    final slotKey = _currentFetSlotKey;
    final replication = _selectedReplication;
    final day = _selectedFetDay;

    setState(() => _analyzingFetSlot = slotKey);
    try {
      final result = await _analyzeFetPlotPhoto(file);
      if (!mounted) return;
      setState(() {
        _fetAutoDetectionBySlot[slotKey] = result;
        _replaceFetPoints(replication, result.pointStatuses, day: day);
        if (_analyzingFetSlot == slotKey) {
          _analyzingFetSlot = null;
        }
      });
      if (showResult) _showFetAutoDetectionSnack(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_analyzingFetSlot == slotKey) {
          _analyzingFetSlot = null;
        }
      });
      if (showResult) {
        _showSnack('Auto detect FET gagal: ${_friendlyError(error)}');
      }
    }
  }

  void _replaceFetPoints(
    int replication,
    List<_FetPointStatus> points, {
    int? day,
  }) {
    final normalized = _initialFetPoints();
    final copyLength = math.min(points.length, _fetGridPointCount);
    for (var index = 0; index < copyLength; index++) {
      normalized[index] = points[index];
    }
    _fetPointsBySlot[_fetSlotKeyFor(replication, day: day)] = normalized;
  }

  void _showFetAutoDetectionSnack(_FetAutoDetectionResult result) {
    _showSnack(
      'Auto detect FET: ${result.grownCount} tumbuh, '
      '${result.notGrownCount} tidak tumbuh, '
      '${result.reviewCount} perlu review.',
    );
  }

  Future<_FetAutoDetectionResult> _analyzeFetPlotPhoto(
    File sourceFile,
  ) async {
    final bytes = await sourceFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;

    try {
      final sourceWidth = sourceImage.width;
      final sourceHeight = sourceImage.height;
      final rawBytes = await sourceImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rawBytes == null) {
        throw const GotFetStorageException(
          'Gagal membaca pixel foto FET.',
        );
      }
      final detection = _detectFetPointStatuses(
        rawBytes,
        imageWidth: sourceWidth,
        imageHeight: sourceHeight,
      );

      return _FetAutoDetectionResult(
        pointStatuses: detection.statuses,
        greenRatios: detection.greenRatios,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        analyzedAt: DateTime.now(),
      );
    } finally {
      sourceImage.dispose();
      codec.dispose();
    }
  }

  ({List<_FetPointStatus> statuses, List<double> greenRatios})
      _detectFetPointStatuses(
    ByteData rawBytes, {
    required int imageWidth,
    required int imageHeight,
  }) {
    final statuses = <_FetPointStatus>[];
    final greenRatios = <double>[];
    final cellWidth = imageWidth / _fetGridColumns;
    final cellHeight = imageHeight / _fetGridRows;

    for (var row = 0; row < _fetGridRows; row++) {
      for (var col = 0; col < _fetGridColumns; col++) {
        final ratio = _greenPixelRatioForCell(
          rawBytes,
          row,
          col,
          cellWidth: cellWidth,
          cellHeight: cellHeight,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );
        greenRatios.add(ratio);
        if (ratio >= _fetGreenHighThreshold) {
          statuses.add(_FetPointStatus.grown);
        } else if (ratio <= _fetGreenLowThreshold) {
          statuses.add(_FetPointStatus.notGrown);
        } else {
          statuses.add(_FetPointStatus.review);
        }
      }
    }

    return (statuses: statuses, greenRatios: greenRatios);
  }

  double _greenPixelRatioForCell(
    ByteData rawBytes,
    int row,
    int col, {
    required double cellWidth,
    required double cellHeight,
    required int imageWidth,
    required int imageHeight,
  }) {
    final left = (col * cellWidth + cellWidth * .18)
        .round()
        .clamp(0, imageWidth - 1)
        .toInt();
    final right = ((col + 1) * cellWidth - cellWidth * .18)
        .round()
        .clamp(left + 1, imageWidth)
        .toInt();
    final top = (row * cellHeight + cellHeight * .18)
        .round()
        .clamp(0, imageHeight - 1)
        .toInt();
    final bottom = ((row + 1) * cellHeight - cellHeight * .18)
        .round()
        .clamp(top + 1, imageHeight)
        .toInt();
    final step = math.max(2, (math.min(cellWidth, cellHeight) / 22).floor());
    var greenPixels = 0;
    var totalPixels = 0;

    for (var y = top; y < bottom; y += step) {
      for (var x = left; x < right; x += step) {
        final offset = (y * imageWidth + x) * 4;
        final r = rawBytes.getUint8(offset);
        final g = rawBytes.getUint8(offset + 1);
        final b = rawBytes.getUint8(offset + 2);
        totalPixels++;
        if (_isFetLeafGreen(r, g, b)) greenPixels++;
      }
    }

    if (totalPixels == 0) return 0;
    return greenPixels / totalPixels;
  }

  bool _isFetLeafGreen(int r, int g, int b) {
    final sum = r + g + b + 1;
    final exg = 2 * g - r - b;
    final normalizedExg = exg / sum;
    final greenDominance = g - math.max(r, b);
    final brightness = sum / 3;
    final leafGreen =
        brightness > 35 && g > 45 && greenDominance > 8 && normalizedExg > .07;
    final lightLeafGreen =
        brightness > 75 && g > r * 1.03 && g > b * 1.05 && exg > 18;
    return leafGreen || lightLeafGreen;
  }

  Future<void> _pickFetPlotPhoto(
    ImageSource source, {
    bool openAnalysisAfterPick = false,
  }) async {
    if (!_gotPlanningReady) {
      _showSnack('Lengkapi dan simpan Data Tanam sebelum mengambil foto FET.');
      return;
    }
    try {
      final image = source == ImageSource.camera
          ? await _captureWithStandaloneCamera(
              module: _InspectionModule.fet,
              title:
                  'Plot FET Day $_selectedFetDay • Ulangan $_selectedReplication',
              subtitle: 'Mode wide • sejajarkan plot pada grid 3 x 3',
            )
          : await _imagePicker.pickImage(
              source: source,
              imageQuality: 88,
              maxWidth: 2200,
            );
      if (image == null || !mounted) return;
      final prepared = await _photoPipeline.preparePhoto(
        image: image,
        context: _SmartPhotoContext(
          module: 'fet',
          lotId: _selectedSample.lotId,
          sampleId: _selectedSample.sampleId,
          plotId: _fetPlotId,
          stage: 'Day $_selectedFetDay',
          replication: _selectedReplication,
          label: 'Plot D$_selectedFetDay U$_selectedReplication',
          source: source == ImageSource.camera ? 'camera' : 'gallery',
          actor: _actorName,
        ),
      );
      if (!mounted) return;
      final replication = _selectedReplication;
      final day = _selectedFetDay;
      final slotKey = _currentFetSlotKey;
      setState(() {
        _fetPlotPhotosBySlot[slotKey] = prepared.file;
        _fetAnalysisPhotosBySlot[slotKey] = prepared.analysisFile;
        _fetPlotMetadataBySlot[slotKey] = prepared.metadata;
        _fetAutoDetectionBySlot.remove(slotKey);
        _replaceFetPoints(replication, _initialFetPoints(), day: day);
        _analyzingFetSlot = slotKey;
      });

      _FetAutoDetectionResult? detectionResult;
      Object? detectionError;
      try {
        detectionResult = await _analyzeFetPlotPhoto(
          prepared.analysisFile,
        );
      } catch (error) {
        detectionError = error;
      }
      if (!mounted) return;
      setState(() {
        if (detectionResult != null) {
          _fetAutoDetectionBySlot[slotKey] = detectionResult;
          _replaceFetPoints(
            replication,
            detectionResult.pointStatuses,
            day: day,
          );
        }
        if (_analyzingFetSlot == slotKey) {
          _analyzingFetSlot = null;
        }
      });

      final reviewText = prepared.metadata.needsReview
          ? ' Cek lagi: ${prepared.metadata.warnings.join(', ')}.'
          : '';
      final duplicateText =
          prepared.duplicateLikely ? ' Potensi duplikat.' : '';
      final detectionText = detectionResult == null
          ? ' Auto detect belum berhasil${detectionError == null ? '.' : ': ${_friendlyError(detectionError)}.'}'
          : ' Auto detect: ${detectionResult.grownCount} tumbuh, ${detectionResult.reviewCount} review.';
      _showSnack(
        'Foto plot FET siap dianalisis.$detectionText$reviewText$duplicateText',
      );
      if (openAnalysisAfterPick) {
        _openPage(_GotFetPage.fetAnalysis);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Gagal mengambil foto FET: ${_friendlyError(e)}');
    }
  }

  Future<XFile?> _captureWithStandaloneCamera({
    required _InspectionModule module,
    required String title,
    required String subtitle,
  }) async {
    final image = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          return _StandaloneCameraScreen(
            module: module,
            title: title,
            subtitle: subtitle,
          );
        },
      ),
    );
    if (!mounted) return null;
    return image;
  }

  Future<void> _pickPlantingDate() async {
    final sample = _selectedSample;
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: sample.plantingDate ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null || !mounted) return;

    final resultEstimation = picked.add(const Duration(days: 65));
    setState(() {
      sample.plantingDate = picked;
      sample.weekOfPlanting = _excelWeekOfYear(picked);
      sample.resultEstimation = resultEstimation;
      sample.weekOfResultEstimation = _excelWeekOfYear(resultEstimation);
      if (!_gotNoteTanamOptions.contains(sample.noteTanam)) {
        sample.noteTanam = 'On Process';
      }
    });
    await _persistSelectedSamplePlanning();
  }

  Future<void> _persistSelectedSamplePlanning({bool showResult = false}) async {
    final sample = _selectedSample;
    try {
      await _gotFetService.updateSamplePlanning(
        batch: sample.batch,
        plantingDate: sample.plantingDate,
        weekOfPlanting: sample.weekOfPlanting,
        resultEstimation: sample.resultEstimation,
        weekOfResultEstimation: sample.weekOfResultEstimation,
        noteTanam: sample.noteTanam,
        location: sample.location,
        village: sample.village,
        subDistrict: sample.subDistrict,
        district: sample.district,
        latitude: sample.latitude,
        longitude: sample.longitude,
        fieldArea: sample.fieldArea,
        fieldAreaNote: sample.fieldAreaNote,
        landAreaName: sample.landAreaName,
        batchLotField: sample.batchLotField,
        statusSample: sample.statusSample,
      );
      if (showResult && mounted) {
        _showSnack('Data tanam ${sample.batch} tersimpan.');
      }
    } catch (error) {
      if (!mounted) return;
      _showSnack('Gagal update data Batch: ${_friendlyError(error)}');
    }
  }

  Future<void> _markSelectedSamplePlanted() async {
    final sample = _selectedSample;
    if (!_gotPlanningReady ||
        sample.plantingDate == null ||
        sample.weekOfPlanting == null ||
        sample.resultEstimation == null ||
        sample.weekOfResultEstimation == null ||
        sample.latitude == null ||
        sample.longitude == null ||
        sample.fieldArea == null) {
      _showSnack(
        'Lengkapi tanggal tanam, Village Coordinate, dan field area.',
      );
      return;
    }

    await _runBackendAction(
      successMessage: 'Batch ${sample.batch} berhasil ditandai Tanam.',
      action: () async {
        await _gotFetService.markSamplePlanted(
          batch: sample.batch,
          lotId: sample.lotId,
          plantingDate: sample.plantingDate!,
          weekOfPlanting: sample.weekOfPlanting!,
          resultEstimation: sample.resultEstimation!,
          weekOfResultEstimation: sample.weekOfResultEstimation!,
          location: sample.location,
          village: sample.village,
          subDistrict: sample.subDistrict,
          district: sample.district,
          latitude: sample.latitude!,
          longitude: sample.longitude!,
          fieldArea: sample.fieldArea!,
          fieldAreaNote: sample.fieldAreaNote,
          landAreaName: sample.landAreaName,
          batchLotField: sample.batchLotField,
          statusSample: sample.statusSample,
          actor: _actorName,
        );
        if (!mounted) return;
        setState(() {
          sample.noteTanam = 'Done';
          sample.status = 'To Obs. Veg';
          _selectFirstSampleForActiveQueue(_activeModuleCode);
        });
      },
    );
  }

  Future<void> _submitGotResult() async {
    if (!_gotPlanningReady) {
      _showSnack('Batch harus ditandai Tanam sebelum observasi GOT.');
      return;
    }
    if (!_gotCountsValid) {
      _showSnack('Jumlah off-type, selfing, dan male melebihi total tanaman.');
      return;
    }
    if (!_gotEvidenceReady) {
      _showSnack(
        _gotOffTypeDetails.isEmpty
            ? 'Tambahkan minimal satu jenis karakter Off-Type yang ditemukan.'
            : 'Lengkapi $_gotRequiredOffTypePhotosPerSample foto untuk setiap jenis karakter Off-Type.',
      );
      return;
    }

    final workflowStatus =
        _gotObservationStage == _GotObservationStage.vegetative
            ? 'To Obs. Gen'
            : 'Waiting Review';

    await _runBackendAction(
      successMessage:
          'GOT $_gotObservationStageLabel ${_selectedSample.lotId} submitted.',
      action: () async {
        await _gotFetService.submitGotObservation(
          lotId: _selectedSample.lotId,
          sampleId: _selectedSample.sampleId,
          hybrid: _selectedSample.hybrid,
          plotId: _gotPlotId,
          stage: _gotObservationStagePayload,
          totalObserved: _gotTotalObserved,
          offTypeCount: _gotOffType,
          selfingCount: _gotSelfing,
          maleCount: _gotMale,
          suspiciousCount: _gotSuspicious,
          trueTypeCount: _gotTrueType,
          purityPercent: _gotPurity,
          submittedBy: _actorName,
          evidencePhotos: const [],
          remarks: _remarksWithManualContext(
            _gotNoteController,
            includeGotStage: true,
          ),
        );
        await _gotFetService.updateGotStageSummary(
          batch: _selectedSample.batch,
          stage: _gotObservationStagePayload,
          totalObserved: _gotTotalObserved,
          purityPercent: _gotPurity,
          offTypePercent: _gotOffTypePercent,
          selfingPercent: _gotSelfingPercent,
          malePercent: _gotMalePercent,
        );
        if (!mounted) return;
        setState(() {
          _selectedSample.status = workflowStatus;
          _selectFirstSampleForActiveQueue(_activeModuleCode);
        });
      },
    );
  }

  Future<void> _submitFetResult() async {
    if (!_gotPlanningReady) {
      _showSnack('Lengkapi dan simpan Data Tanam sebelum submit FET.');
      return;
    }
    if (!_fetPhotoReady) {
      _showSnack('Foto FET Day $_selectedFetDay belum tersedia.');
      return;
    }
    if (_currentReplicationHasOpenItems) {
      _showSnack('Selesaikan titik review/tidak terbaca sebelum submit.');
      return;
    }

    await _runBackendAction(
      successMessage:
          'FET Day $_selectedFetDay Ulangan $_selectedReplication: $_selectedFetRemark.',
      action: () async {
        await _gotFetService.submitFetObservation(
          lotId: _selectedSample.lotId,
          sampleId: _selectedSample.sampleId,
          hybrid: _selectedSample.hybrid,
          plotId: _fetPlotId,
          replication: _selectedReplication,
          dap: _selectedFetDay,
          totalPoints: _currentReplication.length,
          grownCount: _currentReplicationGrown,
          notGrownCount: _currentReplicationNotGrown,
          reviewCount: _currentReplicationReview,
          notReadableCount: _currentReplicationNotReadable,
          emergencePercent: _currentReplicationEmergence,
          pointStatuses: [
            for (final point in _currentReplication) _fetStatusPayload(point),
          ],
          submittedBy: _actorName,
          remarkStatus: _selectedFetRemark,
          plotPhoto: _currentFetPlotPhoto,
          remarks: _optionalText(_fetNoteController),
        );
        final sampleStatus =
            _selectedFetRemark == 'Done' ? 'FET Submitted' : _selectedFetRemark;
        await _gotFetService.updateSampleStatus(
          batch: _selectedSample.batch,
          status: sampleStatus,
        );
        if (!mounted) return;
        setState(() {
          _selectedSample.status = sampleStatus;
          _selectFirstSampleForActiveQueue(_activeModuleCode);
        });
      },
    );
  }

  Future<void> _submitReviewDecision(
    String status, {
    String? displayStatus,
    VoidCallback? onSubmitted,
  }) async {
    final previousStatus = _selectedSample.status;
    final module = switch (_page) {
      _GotFetPage.gotReview => 'GOT',
      _GotFetPage.fetReview => 'FET',
      _ => _reviewSegment == 0 ? 'GOT' : 'FET',
    };

    await _runBackendAction(
      successMessage:
          'Decision ${_selectedSample.lotId}: ${displayStatus ?? status}',
      action: () async {
        await _gotFetService.submitReviewDecision(
          lotId: _selectedSample.lotId,
          sampleId: _selectedSample.sampleId,
          module: module,
          previousStatus: previousStatus,
          newStatus: status,
          reviewer: _actorName,
          remarks: 'Decision from $module review screen',
        );
        await _gotFetService.updateSampleStatus(
          batch: _selectedSample.batch,
          status: status,
        );
        if (!mounted) return;
        setState(() {
          _selectedSample.status = status;
          _selectFirstSampleForActiveQueue(_activeModuleCode);
        });
        onSubmitted?.call();
      },
    );
  }

  Future<void> _confirmTrackingStatus(
    String status, {
    String? remarks,
    VoidCallback? onConfirmed,
  }) async {
    final sample = _selectedSample;

    await _runBackendAction(
      successMessage: 'Tracking ${sample.batch}: $status',
      action: () async {
        await _gotFetService.appendTrackingEvent(
          lotId: sample.lotId,
          status: status,
          actor: _actorName,
          remarks: remarks ?? 'Lot tracking confirmation for ${sample.batch}',
        );
        await _gotFetService.updateSampleStatus(
          batch: sample.batch,
          status: status,
        );
        if (!mounted) return;
        setState(() {
          sample.status = status;
          _selectFirstSampleForActiveQueue(_activeModuleCode);
        });
        onConfirmed?.call();
      },
    );
  }

  Future<void> _runBackendAction({
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      await action();
      if (!mounted) return;
      _showSnack(successMessage);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Gagal sinkronisasi: ${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _showEvidenceSourceSheet({
    required VoidCallback onCamera,
    required VoidCallback onGallery,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded),
                  title: const Text('Ambil dari Kamera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Pilih dari Gallery'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onGallery();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String get _actorName {
    final name = _session?.name.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = _session?.email.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'GOT & FET User';
  }

  String? _optionalText(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  String? _remarksWithManualContext(
    TextEditingController controller, {
    bool includeGotStage = false,
  }) {
    final base = _optionalText(controller);
    final contextParts = [
      'Batch: ${_selectedSample.batch}',
      'Process Stage: ${_selectedSample.processStage}',
      if (includeGotStage) 'GOT Stage: $_gotObservationStageLabel',
      if (includeGotStage) 'No. Obs: $_gotObservationNumber',
    ];
    final contextText = contextParts.join(' | ');
    if (base == null) return contextText;
    return '$base\n$contextText';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return _dateFormat.format(date);
  }

  String _formatNumber(num value) {
    final formatter = NumberFormat.decimalPattern('id_ID');
    return formatter.format(value);
  }

  String _formatArea(double? value) {
    return FieldAreaRules.display(value);
  }

  String _formatPercent(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  String _normalizeRuleText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _containsRuleTerm(String source, List<String> terms) {
    final paddedSource = ' ${_normalizeRuleText(source)} ';
    for (final term in terms) {
      final normalizedTerm = _normalizeRuleText(term);
      if (normalizedTerm.isEmpty) continue;
      if (paddedSource.contains(' $normalizedTerm ')) return true;
    }
    return false;
  }

  int _excelWeekOfYear(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final firstDay = DateTime(date.year);
    return (day.difference(firstDay).inDays ~/ 7) + 1;
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.length <= 140) return message;
    return '${message.substring(0, 140)}...';
  }

  int _countStatus(List<_FetPointStatus> points, _FetPointStatus status) {
    return points.where((point) => point == status).length;
  }

  List<_FetPointStatus> _readFetPointStatuses(Map<String, dynamic> row) {
    final raw = _readValue(row, const ['point_statuses']);
    if (raw is! List) return const [];

    final statuses = <_FetPointStatus>[];
    for (final item in raw) {
      if (item is Map) {
        statuses.add(
          _fetStatusFromPayload(
            item['status']?.toString() ?? item['value']?.toString() ?? '',
          ),
        );
      } else {
        statuses.add(_fetStatusFromPayload(item.toString()));
      }
    }
    return statuses;
  }

  double _gotPercent(int count) {
    if (_gotTotalObserved == 0) return 0;
    return (count / _gotTotalObserved) * 100;
  }

  String _fetStatusPayload(_FetPointStatus status) {
    return switch (status) {
      _FetPointStatus.grown => 'grown',
      _FetPointStatus.notGrown => 'not_grown',
      _FetPointStatus.review => 'review',
      _FetPointStatus.notReadable => 'not_readable',
    };
  }

  _FetPointStatus _fetStatusFromPayload(String value) {
    return switch (value.toLowerCase().trim()) {
      'grown' || 'g' || 'tumbuh' => _FetPointStatus.grown,
      'not_grown' ||
      'not grown' ||
      'ng' ||
      'tidak tumbuh' =>
        _FetPointStatus.notGrown,
      'not_readable' ||
      'not readable' ||
      'nr' ||
      'tidak terbaca' =>
        _FetPointStatus.notReadable,
      _ => _FetPointStatus.review,
    };
  }

  Color _fetStatusColor(_FetPointStatus status) {
    return switch (status) {
      _FetPointStatus.grown => AdvantaColors.success,
      _FetPointStatus.notGrown => AdvantaColors.error,
      _FetPointStatus.review => AdvantaColors.gold,
      _FetPointStatus.notReadable => AdvantaColors.mutedGrey,
    };
  }

  String _fetStatusLabel(_FetPointStatus status) {
    return switch (status) {
      _FetPointStatus.grown => 'Tumbuh',
      _FetPointStatus.notGrown => 'Tidak Tumbuh',
      _FetPointStatus.review => 'Perlu Review',
      _FetPointStatus.notReadable => 'Tidak Terbaca',
    };
  }

  String _fetStatusShortLabel(_FetPointStatus status) {
    return switch (status) {
      _FetPointStatus.grown => 'G',
      _FetPointStatus.notGrown => 'NG',
      _FetPointStatus.review => 'R',
      _FetPointStatus.notReadable => 'NR',
    };
  }

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('approved')) return AdvantaColors.success;
    if (normalized.contains('request new sample') ||
        normalized.contains('resample') ||
        normalized.contains('resampling')) {
      return AdvantaColors.error;
    }
    if (normalized.contains('generative') ||
        normalized.contains('generatif') ||
        normalized.contains('obs gen')) {
      return const Color(0xFF4361EE);
    }
    if (normalized.contains('vegetative') ||
        normalized.contains('vegetatif') ||
        normalized.contains('obs veg')) {
      return AdvantaColors.primaryGreen;
    }
    if (normalized.contains('hold') || normalized.contains('revision')) {
      return AdvantaColors.gold;
    }
    if (normalized.contains('reject') || normalized.contains('overdue')) {
      return AdvantaColors.error;
    }
    if (normalized.contains('review')) return AdvantaColors.gold;
    if (normalized.contains('submit')) return AdvantaColors.primaryGreen;
    if (normalized.contains('ready to plant')) {
      return AdvantaColors.primaryGreen;
    }
    if (normalized.contains('received')) return const Color(0xFF4361EE);
    return AdvantaColors.mutedGrey;
  }

  TextStyle _sectionTitle(BuildContext context) {
    return AdvantaText.heading3.copyWith(color: _strongTextColor(context));
  }

  TextStyle _mutedTextStyle(BuildContext context) {
    return AdvantaText.caption.copyWith(color: _gotFetMutedColor(context));
  }

  Color _strongTextColor(BuildContext context) {
    return _gotFetTextColor(context);
  }

  _GotFetSample _sampleFromRow(Map<String, dynamic> row) {
    final batch = _readText(row, const ['batch', 'Batch']);
    final testType = _readText(
      row,
      const ['test_type', 'testType', 'Test Type', 'module'],
      fallback: _inferTestType(row),
    );

    return _GotFetSample(
      lotId:
          _readText(row, const ['lot_id', 'lotId', 'Batch'], fallback: batch),
      sampleId: _readText(
        row,
        const ['sample_id', 'sampleId', 'No', 'no'],
        fallback: batch,
      ),
      hybrid: _readText(row, const ['hybrid_all', 'hybrid', 'Hybrid All']),
      crop: _readText(row, const ['category', 'Category']),
      season: _readText(row, const ['crop_year', 'Crop Year']),
      testType: testType,
      status: _readText(
        row,
        const [
          'workflow_status',
          'Workflow Status',
          'status',
          'Status Sample',
          'status_sample',
          'Status GOT 2',
          'status_got_2',
        ],
        fallback: 'Open',
      ),
      pic: _readText(row, const ['pic', 'PIC'], fallback: '-'),
      dueDate:
          _readDate(row, const ['result_estimation', 'Result Estimation']) ??
              DateTime.now(),
      gender: _readText(row, const ['gender', 'Gender']),
      typeSeed: _readText(row, const ['type_seed', 'Type Seed']),
      category: _readText(row, const ['category', 'Category']),
      cropYear: _readInt(row, const ['crop_year', 'Crop Year']),
      processStage: _readText(row, const ['process_stage', 'Process Stage']),
      batch: batch,
      noteSample: _readText(row, const ['note_sample', 'Note Sample']),
      qtyByDss: _readInt(row, const ['qty_by_dss', 'Qty by DSS']),
      commercialQtyInventory: _readNum(
        row,
        const ['commercial_qty_inventory', 'Commercial Qty Inventory'],
      ),
      flagging: _readText(row, const ['flagging', 'Flagging']),
      reasonTesting: _readText(
        row,
        const [
          'reason_testing',
          'note_sample_reason_testing',
          'Note Sample/ Reason testing'
        ],
      ),
      deliveryDate1:
          _readDate(row, const ['delivery_date_1', 'Delivery Date 1']),
      deliveryDate2:
          _readDate(row, const ['delivery_date_2', 'Delivery Date 2']),
      plantingDate: _readDate(row, const ['planting_date', 'Planting Date']),
      weekOfPlanting: _readOptionalInt(
        row,
        const ['week_of_planting', 'Week Of Planting'],
      ),
      resultEstimation:
          _readDate(row, const ['result_estimation', 'Result Estimation']),
      weekOfResultEstimation: _readOptionalInt(
        row,
        const ['week_of_result_estimation', 'Week of Result Est.'],
      ),
      noteTanam: _readText(row, const ['note_tanam', 'Note Tanam']),
      location: _readText(row, const ['location', 'Location']),
      village:
          _readText(row, const ['village_desa', 'Village', 'Village Desa']),
      subDistrict: _readText(
        row,
        const ['sub_district_kec', 'Sub District', 'Kecamatan'],
      ),
      district: _readText(row, const ['district_kab', 'District', 'Kabupaten']),
      latitude: _readDouble(row, const ['latitude']),
      longitude: _readDouble(row, const ['longitude']),
      fieldArea: _readDouble(row, const ['field_area', 'Field Area']),
      fieldAreaNote: _readText(
        row,
        const ['field_area_note', 'Field Area Note', 'Catatan Luasan'],
        fallback: '',
      ),
      statusGot2: _readText(row, const ['status_got_2', 'Status GOT 2']),
      landAreaName: _readText(
        row,
        const ['land_area_name', 'Land Area Name', 'Nama Lahan'],
        fallback: '',
      ),
      batchLotField: _readText(
        row,
        const ['batch_lot_field', 'Batch Lot Field'],
        fallback: '',
      ),
      statusGotVeg: _readText(
        row,
        const ['status_got_veg', 'Status GOT Veg'],
      ),
      finalStatusGot: _readText(
        row,
        const ['final_status_got', 'Final Status GOT'],
      ),
      statusSample: _readText(
        row,
        const ['status_sample', 'Status Sample'],
        fallback: 'Fresh',
      ),
      vegetativeObservationNo:
          _readNullableText(row, const ['vegetative_no_obs', 'No. Obs']),
      finalObservationNo:
          _readNullableText(row, const ['final_no_obs', 'Final No. Obs']),
      payment: _readText(row, const ['payment', 'Payment']),
      steps: _trackingStepsFromRow(row),
    );
  }

  String _inferTestType(Map<String, dynamic> row) {
    final processStage =
        _readText(row, const ['process_stage', 'Process Stage']).toUpperCase();
    final hasGotValue = _readNullableText(row, const [
          'status_got_2',
          'Status GOT 2',
          'status_got_veg',
          'Status GOT Veg',
          'final_status_got',
          'Final Status GOT',
        ]) !=
        null;
    if (hasGotValue || processStage == 'DSS' || processStage == 'DCS') {
      return 'GOT';
    }
    return 'FET';
  }

  List<_TrackingStep> _trackingStepsFromRow(Map<String, dynamic> row) {
    final deliveryDate =
        _readDate(row, const ['delivery_date_1', 'Delivery Date 1']);
    final plantingDate =
        _readDate(row, const ['planting_date', 'Planting Date']);
    final resultDate =
        _readDate(row, const ['result_estimation', 'Result Estimation']);
    final now = DateTime.now();

    return [
      _TrackingStep(
          'Sample Created', deliveryDate ?? now, deliveryDate != null),
      _TrackingStep('Dispatched', deliveryDate ?? now, deliveryDate != null),
      _TrackingStep('Planted', plantingDate ?? now, plantingDate != null),
      _TrackingStep('Observed', resultDate ?? now, resultDate != null),
      _TrackingStep('Reviewed', resultDate ?? now, false),
      _TrackingStep('Completed', resultDate ?? now, false),
    ];
  }

  dynamic _readValue(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      if (row.containsKey(key)) return row[key];
      final normalizedKey = _normalizeColumnKey(key);
      for (final entry in row.entries) {
        if (_normalizeColumnKey(entry.key) == normalizedKey) return entry.value;
      }
    }
    return null;
  }

  String _readText(
    Map<String, dynamic> row,
    List<String> keys, {
    String fallback = '-',
  }) {
    final value = _readValue(row, keys);
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String? _readNullableText(Map<String, dynamic> row, List<String> keys) {
    final value = _readValue(row, keys);
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int _readInt(Map<String, dynamic> row, List<String> keys) {
    return _readOptionalInt(row, keys) ?? 0;
  }

  int? _readOptionalInt(Map<String, dynamic> row, List<String> keys) {
    final value = _readValue(row, keys);
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  num? _readNum(Map<String, dynamic> row, List<String> keys) {
    final value = _readValue(row, keys);
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  double? _readDouble(Map<String, dynamic> row, List<String> keys) {
    final value = _readNum(row, keys);
    return value?.toDouble();
  }

  DateTime? _readDate(Map<String, dynamic> row, List<String> keys) {
    final value = _readValue(row, keys);
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      final excelEpoch = DateTime(1899, 12, 30);
      return excelEpoch.add(Duration(days: value.floor()));
    }
    return DateTime.tryParse(value.toString());
  }

  String _normalizeColumnKey(String key) {
    return key
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  List<_FetPointStatus> _initialFetPoints() {
    return List<_FetPointStatus>.filled(
      _fetGridPointCount,
      _FetPointStatus.review,
      growable: true,
    );
  }
}

class _PageScaffold extends StatelessWidget {
  final Widget child;

  const _PageScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [child],
      ),
    );
  }
}

class _SampleStatePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _SampleStatePage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AdvantaColors.green.withAlpha(
                    _gotFetIsDark(context) ? 52 : 24,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: _gotFetIsDark(context)
                      ? Colors.white
                      : AdvantaColors.greenDark,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AdvantaText.heading2.copyWith(
                  color: _gotFetTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AdvantaText.body2.copyWith(
                  color: _gotFetMutedColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return const GotFetOverlayLoader(
      title: 'Menyimpan hasil inspeksi...',
      message: 'Sinkronisasi data GOT & FET ke server sedang berjalan.',
      progress: .72,
    );
  }
}

class _BrandHeader extends StatelessWidget {
  final String? userName;
  final _GotFetSample? selectedSample;

  const _BrandHeader({
    required this.userName,
    required this.selectedSample,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    final textColor = isDark ? Colors.white : AdvantaColors.textDark;
    final mutedColor = _gotFetMutedColor(context);
    final borderColor =
        isDark ? Colors.white.withAlpha(26) : AdvantaColors.lineLight;
    final highlight = isDark ? const Color(0xFF7BE48C) : _GotFetUi.greenDark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  AdvantaColors.navyDeep,
                  AdvantaColors.navyDark,
                  AdvantaColors.darkSurface,
                ]
              : const [
                  Colors.white,
                  AdvantaColors.skySoft,
                  Color(0xFFE8F6FF),
                ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: _gotFetShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -28,
            bottom: -42,
            child: Opacity(
              opacity: isDark ? 0.08 : 0.10,
              child: Image.asset(
                _GotFetAssets.appLogo,
                width: 210,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    _GotFetAssets.appLogo,
                    width: 78,
                    height: 50,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.fact_check_rounded,
                      color: highlight,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GOT & FET',
                          style: AdvantaText.heading2.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Digital Inspection for Quality Seeds',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdvantaText.caption.copyWith(
                            color: highlight,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withAlpha(10)
                          : AdvantaColors.skySoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      color: textColor,
                      size: 21,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                userName?.trim().isNotEmpty == true
                    ? 'Halo, $userName'
                    : 'Selamat datang',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AdvantaText.display.copyWith(
                  color: textColor,
                  fontSize: 28,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                selectedSample == null
                    ? 'Active lot: menunggu data Batch dari Supabase'
                    : 'Active lot: ${selectedSample!.lotId} | ${selectedSample!.status}',
                style: AdvantaText.body2.copyWith(
                  color: highlight,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _HeaderStat(
                      label: 'Hybrid',
                      value: selectedSample?.hybrid ?? '-',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeaderStat(
                      label: 'Test',
                      value: selectedSample?.testType ?? '-',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeaderStat(
                      label: 'PIC',
                      value: selectedSample?.pic ?? '-',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Traceable inspection, real-time input, and review-ready output.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AdvantaText.caption.copyWith(color: mutedColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withAlpha(9)
            : AdvantaColors.lightSurface.withAlpha(210),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gotFetBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdvantaText.caption.copyWith(
              color: _gotFetMutedColor(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdvantaText.caption.copyWith(
              color: _gotFetTextColor(context),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final Widget child;

  const _PanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _gotFetCardColor(context),
        borderRadius: AdvantaRadius.cardRadius,
        border: Border.all(color: _gotFetBorderColor(context)),
        boxShadow: _gotFetShadow(context),
      ),
      child: child,
    );
  }
}

class _SampleSearchTile extends StatelessWidget {
  final _GotFetSample sample;
  final bool isSelected;
  final Color statusColor;
  final VoidCallback onTap;

  const _SampleSearchTile({
    required this.sample,
    required this.isSelected,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    final accentColor = sample.testType.toUpperCase().contains('FET')
        ? AdvantaColors.greenDark
        : AdvantaColors.green;
    final backgroundColor = isSelected
        ? (isDark
            ? AdvantaColors.green.withAlpha(38)
            : AdvantaColors.greenSoft.withAlpha(220))
        : (isDark ? Colors.white.withAlpha(7) : AdvantaColors.lightSurface);

    final chips = [
      sample.testType,
      sample.category,
      sample.processStage,
      sample.location,
      sample.statusSample,
    ].where((value) => value.trim().isNotEmpty && value != '-').toList();

    return Material(
      color: backgroundColor,
      borderRadius: AdvantaRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AdvantaRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(isDark ? 42 : 22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.qr_code_2_rounded,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sample.lotId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.bodyBold.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Batch ${sample.batch} | ${sample.hybrid}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final chip in chips)
                            _SampleSearchChip(label: chip),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusPill(label: sample.status, color: statusColor),
                  if (isSelected) ...[
                    const SizedBox(height: 8),
                    Icon(
                      Icons.check_circle_rounded,
                      color: AdvantaColors.green,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleSearchChip extends StatelessWidget {
  final String label;

  const _SampleSearchChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withAlpha(10) : AdvantaColors.lightBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gotFetBorderColor(context)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AdvantaText.caption.copyWith(
          color: _gotFetMutedColor(context),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ModuleStrip extends StatelessWidget {
  final String logoAsset;
  final String title;
  final String subtitle;

  const _ModuleStrip({
    required this.logoAsset,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Row(
        children: [
          _FeatureLogoTile(asset: logoAsset, size: 58),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.heading3.copyWith(
                    color: _gotFetTextColor(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.caption.copyWith(
                    color: _gotFetMutedColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureLogoTile extends StatelessWidget {
  final String asset;
  final double size;

  const _FeatureLogoTile({
    required this.asset,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _gotFetIsDark(context)
            ? Colors.white.withAlpha(8)
            : AdvantaColors.skySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gotFetBorderColor(context)),
      ),
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.image_not_supported_rounded,
          color: _GotFetUi.greenDark,
          size: size * .45,
        ),
      ),
    );
  }
}

class _SegmentLogo extends StatelessWidget {
  final String asset;

  const _SegmentLogo({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: 20,
      height: 20,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.fact_check_rounded,
        color: _gotFetTextColor(context),
        size: 18,
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricData> cards;

  const _MetricGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 640 ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: crossAxisCount == 4 ? 2.2 : 1.9,
          children: [
            for (final card in cards) _MetricCard(data: card),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;

  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AdvantaRadius.cardRadius,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: AdvantaRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _gotFetCardColor(context),
            borderRadius: AdvantaRadius.cardRadius,
            border: Border.all(color: _gotFetBorderColor(context)),
            boxShadow: _gotFetShadow(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(data.icon, color: data.color, size: 22),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      data.value,
                      maxLines: 1,
                      style: AdvantaText.heading2.copyWith(
                        color:
                            _gotFetIsDark(context) ? Colors.white : data.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdvantaText.caption.copyWith(
                      color: _gotFetMutedColor(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuActionCard extends StatelessWidget {
  final _MenuAction action;
  final VoidCallback onTap;

  const _MenuActionCard({
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return Material(
      color: _gotFetCardColor(context),
      borderRadius: AdvantaRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AdvantaRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: AdvantaRadius.cardRadius,
            border: Border.all(color: _gotFetBorderColor(context)),
            boxShadow: _gotFetShadow(context),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (action.logoAsset == null)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _GotFetUi.green.withAlpha(isDark ? 65 : 22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    action.icon,
                    color: isDark ? Colors.white : _GotFetUi.greenDark,
                  ),
                )
              else
                _FeatureLogoTile(asset: action.logoAsset!, size: 48),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  action.title,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: AdvantaText.bodyBold.copyWith(
                    color: _gotFetTextColor(context),
                    fontSize: 14,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                action.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AdvantaText.caption.copyWith(
                  color: _gotFetMutedColor(context),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowSummary extends StatelessWidget {
  final List<(String, IconData)> steps;

  const _WorkflowSummary({required this.steps});

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workflow Summary',
                style: AdvantaText.heading3.copyWith(
                  color: _gotFetTextColor(context),
                ),
              ),
              const SizedBox(height: 14),
              if (compact)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: steps.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.18,
                  ),
                  itemBuilder: (context, index) {
                    return _WorkflowNode(
                      label: steps[index].$1,
                      icon: steps[index].$2,
                    );
                  },
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      Expanded(
                        child: _WorkflowNode(
                          label: steps[i].$1,
                          icon: steps[i].$2,
                        ),
                      ),
                      if (i != steps.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: _gotFetMutedColor(context),
                            size: 16,
                          ),
                        ),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _WorkflowNode extends StatelessWidget {
  final String label;
  final IconData icon;

  const _WorkflowNode({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          color: _gotFetTextColor(context),
          size: 22,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AdvantaText.caption.copyWith(
            color: _gotFetTextColor(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _GuidanceBanner extends StatelessWidget {
  final String text;
  final Color color;

  const _GuidanceBanner({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 60 : 28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(isDark ? 100 : 70)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AdvantaText.bodyBold.copyWith(
          color: isDark ? Colors.white : _GotFetUi.greenDark,
        ),
      ),
    );
  }
}

enum _CameraMockupMode { got, fet }

class _CameraMockup extends StatelessWidget {
  final _CameraMockupMode mode;
  final String title;
  final String footer;

  const _CameraMockup({
    required this.mode,
    required this.title,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(48),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: mode == _CameraMockupMode.got
                  ? _GotPlantPainter()
                  : _PlotFieldPainter(),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: mode == _CameraMockupMode.got
                  ? const _CameraMarkerFrame()
                  : const _PlotMarkerFrame(),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 88,
            child: _GuidanceBanner(text: title, color: AdvantaColors.success),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CameraButton(icon: Icons.close_rounded),
                _CameraButton(icon: Icons.camera_alt_rounded, primary: true),
                _CameraButton(
                  icon: mode == _CameraMockupMode.got
                      ? Icons.help_outline_rounded
                      : Icons.flashlight_on_rounded,
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 68,
            child: Text(
              footer,
              textAlign: TextAlign.center,
              style: AdvantaText.caption.copyWith(
                color: Colors.white.withAlpha(210),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraButton extends StatelessWidget {
  final IconData icon;
  final bool primary;

  const _CameraButton({
    required this.icon,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: primary ? 58 : 46,
      height: primary ? 58 : 46,
      decoration: BoxDecoration(
        color: primary ? _GotFetUi.green : Colors.black.withAlpha(150),
        shape: BoxShape.circle,
        border: Border.all(
          color: primary ? Colors.white : Colors.white.withAlpha(55),
          width: primary ? 2 : 1,
        ),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _CameraMarkerFrame extends StatelessWidget {
  const _CameraMarkerFrame();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MarkerFramePainter(showCenter: true));
  }
}

class _PlotMarkerFrame extends StatelessWidget {
  const _PlotMarkerFrame();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MarkerFramePainter(showGrid: true));
  }
}

class _WorkflowProgressCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_WorkflowStepData> steps;

  const _WorkflowProgressCard({
    required this.title,
    required this.subtitle,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    final completed = steps.where((step) => step.done).length;
    final color = completed == steps.length
        ? AdvantaColors.success
        : AdvantaColors.warning;

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(_gotFetIsDark(context) ? 46 : 24),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.route_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AdvantaText.bodyBold.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(label: '$completed/${steps.length}', color: color),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final step in steps) _WorkflowStepChip(step: step),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkflowStepChip extends StatelessWidget {
  final _WorkflowStepData step;

  const _WorkflowStepChip({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = step.done
        ? AdvantaColors.success
        : step.active
            ? AdvantaColors.primaryGreen
            : AdvantaColors.mutedGrey;
    final isDark = _gotFetIsDark(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 168),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 50 : 22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(step.active ? 170 : 95)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            step.done ? Icons.check_circle_rounded : step.icon,
            size: 18,
            color: isDark ? Colors.white : color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.caption.copyWith(
                    color: _gotFetTextColor(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  step.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.caption.copyWith(
                    color: _gotFetMutedColor(context),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AdvantaText.body2.copyWith(
              color: _gotFetMutedColor(context),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AdvantaText.bodyBold.copyWith(
              color: valueColor ?? _gotFetTextColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineStatusMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InlineStatusMessage({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(_gotFetIsDark(context) ? 42 : 20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AdvantaText.caption.copyWith(
                color: _gotFetTextColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final _TrackingStep step;
  final bool isLast;
  final DateFormat dateTimeFormat;
  final String? actor;
  final String? remarks;

  const _TimelineRow({
    required this.step,
    required this.isLast,
    required this.dateTimeFormat,
    this.actor,
    this.remarks,
  });

  @override
  Widget build(BuildContext context) {
    final color = step.done ? AdvantaColors.success : AdvantaColors.mutedGrey;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  step.done ? Icons.check_rounded : Icons.more_horiz_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: color.withAlpha(95),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.label,
                          style: AdvantaText.bodyBold.copyWith(
                            color: _gotFetTextColor(context),
                          ),
                        ),
                      ),
                      Text(
                        dateTimeFormat.format(step.date),
                        style: AdvantaText.caption.copyWith(
                          color: _gotFetMutedColor(context),
                        ),
                      ),
                    ],
                  ),
                  if ((actor?.isNotEmpty ?? false) ||
                      (remarks?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (actor?.isNotEmpty ?? false) actor!,
                        if (remarks?.isNotEmpty ?? false) remarks!,
                      ].join(' | '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 50 : 24),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AdvantaText.caption.copyWith(
          color: isDark ? Colors.white : color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FetReplicationMiniStatus extends StatelessWidget {
  final int replication;
  final bool selected;
  final bool photoReady;
  final bool submitted;
  final int openItems;
  final double emergence;

  const _FetReplicationMiniStatus({
    required this.replication,
    required this.selected,
    required this.photoReady,
    required this.submitted,
    required this.openItems,
    required this.emergence,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    final color = selected ? AdvantaColors.primaryGreen : AdvantaColors.navy;
    final background = selected
        ? color.withAlpha(isDark ? 52 : 26)
        : (isDark ? Colors.white.withAlpha(8) : AdvantaColors.lightSurface);
    final textColor = selected
        ? (isDark ? Colors.white : AdvantaColors.greenDark)
        : _gotFetTextColor(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 144, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? color.withAlpha(180) : _gotFetBorderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected
                    ? AdvantaColors.primaryGreen
                    : _gotFetMutedColor(context),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Ulangan $replication',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.bodyBold.copyWith(color: textColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${emergence.toStringAsFixed(1)}% emergence',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdvantaText.caption.copyWith(
              color: _gotFetMutedColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusPill(
                label: photoReady ? 'Foto ada' : 'Belum foto',
                color: photoReady ? AdvantaColors.success : AdvantaColors.gold,
              ),
              _StatusPill(
                label: openItems == 0 ? 'Kroscek OK' : '$openItems terbuka',
                color: openItems == 0
                    ? AdvantaColors.success
                    : AdvantaColors.warning,
              ),
              _StatusPill(
                label: selected
                    ? submitted
                        ? 'Submit'
                        : 'Draft'
                    : 'Pilih cek',
                color: selected && submitted
                    ? AdvantaColors.primaryGreen
                    : AdvantaColors.mutedGrey,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  final String label;
  final String value;

  const _MiniFact({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AdvantaText.caption.copyWith(
            color: _gotFetMutedColor(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AdvantaText.bodyBold.copyWith(
            color: _gotFetTextColor(context),
          ),
        ),
      ],
    );
  }
}

class _CounterRow extends StatelessWidget {
  final String label;
  final int value;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final ValueChanged<String> onChanged;

  const _CounterRow({
    required this.label,
    required this.value,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  void _triggerHaptic() {
    HapticFeedback.vibrate();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AdvantaText.body2.copyWith(
                color: _gotFetTextColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Kurangi $label',
            onPressed: () {
              _triggerHaptic();
              onRemove();
            },
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 76,
            child: Semantics(
              label: '$label $value',
              textField: true,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: onChanged,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  filled: true,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                ),
                style: AdvantaText.bodyBold.copyWith(
                  color: _gotFetTextColor(context),
                ),
              ),
            ),
          ),
          IconButton.filled(
            tooltip: 'Tambah $label',
            onPressed: () {
              _triggerHaptic();
              onAdd();
            },
            icon: const Icon(Icons.add_rounded),
            style: IconButton.styleFrom(
              backgroundColor: _GotFetUi.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _DualActionBar extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final IconData leftIcon;
  final IconData rightIcon;
  final bool rightEnabled;
  final Color? rightColor;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _DualActionBar({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftIcon,
    required this.rightIcon,
    required this.onLeft,
    required this.onRight,
    this.rightEnabled = true,
    this.rightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: Icon(leftIcon),
            label: Text(leftLabel),
            onPressed: onLeft,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: rightColor ?? _GotFetUi.green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _GotFetUi.line,
              disabledForegroundColor: _GotFetUi.navy.withAlpha(95),
            ),
            icon: Icon(rightIcon),
            label: Text(rightLabel),
            onPressed: rightEnabled ? onRight : null,
          ),
        ),
      ],
    );
  }
}

class _GotEvidenceEmptyFolder extends StatelessWidget {
  final _GotEvidenceCategory category;
  final int count;

  const _GotEvidenceEmptyFolder({
    required this.category,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _gotFetIsDark(context)
            ? Colors.white.withAlpha(8)
            : AdvantaColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gotFetBorderColor(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_off_rounded,
            color: _gotFetMutedColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 0
                  ? 'Belum ada temuan ${category.title} untuk stage ini.'
                  : 'Slot foto akan muncul setelah jumlah ${category.title} terbaca, maksimal 6 foto per kategori.',
              style: AdvantaText.caption.copyWith(
                color: _gotFetMutedColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GotEvidenceSlotTile extends StatelessWidget {
  final _GotEvidenceSlot slot;
  final _GotEvidencePhoto? photo;
  final Color color;
  final bool syncing;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback? onView;

  const _GotEvidenceSlotTile({
    required this.slot,
    required this.photo,
    required this.color,
    required this.syncing,
    required this.onCapture,
    required this.onGallery,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    final hasPhoto = photo != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : AdvantaColors.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPhoto ? color.withAlpha(120) : _gotFetBorderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onView,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: hasPhoto
                        ? Image.network(
                            photo!.photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _EvidenceThumbFallback(
                              icon: Icons.broken_image_rounded,
                              color: color,
                            ),
                          )
                        : _EvidenceThumbFallback(
                            icon: Icons.add_a_photo_rounded,
                            color: color,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${slot.label} - ${slot.category.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.bodyBold.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasPhoto
                          ? 'Foto tersimpan${photo!.uploadedAt == null ? '' : ' | ${photo!.uploadedAt!.toLocal().toString().substring(0, 16)}'}'
                          : 'Belum ada foto evidence',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (syncing)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.3),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: syncing ? null : onCapture,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(hasPhoto ? 'Ganti Foto' : 'Ambil Foto'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Pilih dari gallery',
                onPressed: syncing ? null : onGallery,
                icon: const Icon(Icons.photo_library_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Lihat foto',
                onPressed: onView,
                icon: const Icon(Icons.visibility_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EvidenceThumbFallback extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _EvidenceThumbFallback({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withAlpha(_gotFetIsDark(context) ? 46 : 24),
      child: Icon(icon, color: color),
    );
  }
}

class _PlotPreview extends StatelessWidget {
  const _PlotPreview();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(painter: _PlotFieldPainter()),
    );
  }
}

class _PlotPhotoPreview extends StatelessWidget {
  final File file;

  const _PlotPhotoPreview({required this.file});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: Colors.black,
        child: Image.file(file, fit: BoxFit.contain),
      ),
    );
  }
}

class _FetPhotoReviewBoard extends StatelessWidget {
  final File file;
  final double aspectRatio;
  final List<_FetPointStatus> points;
  final Color Function(_FetPointStatus status) statusColor;
  final String Function(_FetPointStatus status) statusLabel;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onLongPress;

  const _FetPhotoReviewBoard({
    required this.file,
    required this.aspectRatio,
    required this.points,
    required this.statusColor,
    required this.statusLabel,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Colors.black,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(80),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _PlotPreview(),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(isDark ? 18 : 8),
                  ),
                ),
                CustomPaint(
                  painter: _FetPhotoGridPainter(
                    lineColor: Colors.white.withAlpha(92),
                  ),
                ),
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _fetGridColumns,
                    childAspectRatio: aspectRatio,
                  ),
                  itemCount: points.length,
                  itemBuilder: (context, index) {
                    final status = points[index];
                    final color = statusColor(status);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(index),
                      onLongPress: () => onLongPress(index),
                      child: Center(
                        child: _FetPointMarker(
                          label: statusLabel(status),
                          color: color,
                          filled: status != _FetPointStatus.grown,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FetReviewPhotoBoard extends StatelessWidget {
  final File? file;
  final String? photoUrl;
  final double aspectRatio;
  final List<_FetPointStatus> points;
  final Color Function(_FetPointStatus status) statusColor;
  final String Function(_FetPointStatus status) statusLabel;

  const _FetReviewPhotoBoard({
    required this.file,
    required this.photoUrl,
    required this.aspectRatio,
    required this.points,
    required this.statusColor,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Colors.black,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(80),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (file != null)
                  Image.file(
                    file!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _PlotPreview(),
                  )
                else
                  Image.network(
                    photoUrl ?? '',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _PlotPreview(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(18),
                  ),
                ),
                CustomPaint(
                  painter: _FetPhotoGridPainter(
                    lineColor: Colors.white.withAlpha(92),
                  ),
                ),
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _fetGridColumns,
                    childAspectRatio: aspectRatio,
                  ),
                  itemCount: points.length,
                  itemBuilder: (context, index) {
                    final status = points[index];
                    return Center(
                      child: _FetPointMarker(
                        label: statusLabel(status),
                        color: statusColor(status),
                        filled: status != _FetPointStatus.grown,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FetPointMarker extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _FetPointMarker({
    required this.label,
    required this.color,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.68,
      heightFactor: 0.68,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color.withAlpha(215) : color.withAlpha(118),
          border: Border.all(color: Colors.white.withAlpha(210), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(75),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                maxLines: 1,
                style: AdvantaText.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FetPhotoGridPainter extends CustomPainter {
  final Color lineColor;

  const _FetPhotoGridPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    for (var i = 1; i < _fetGridColumns; i++) {
      final x = size.width * i / _fetGridColumns;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var i = 1; i < _fetGridRows; i++) {
      final y = size.height * i / _fetGridRows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FetPhotoGridPainter oldDelegate) {
    return lineColor != oldDelegate.lineColor;
  }
}

class _FetPointGrid extends StatelessWidget {
  final List<_FetPointStatus> points;
  final Color Function(_FetPointStatus status) statusColor;
  final String Function(_FetPointStatus status) statusLabel;
  final ValueChanged<int> onTap;

  const _FetPointGrid({
    required this.points,
    required this.statusColor,
    required this.statusLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return AspectRatio(
      aspectRatio: _fetGridColumns / _fetGridRows,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _fetGridColumns,
          crossAxisSpacing: 5,
          mainAxisSpacing: 5,
        ),
        itemCount: points.length,
        itemBuilder: (context, index) {
          final status = points[index];
          final color = statusColor(status);
          return InkWell(
            onTap: () => onTap(index),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withAlpha(isDark ? 62 : 22),
                shape: BoxShape.circle,
                border: Border.all(color: color),
              ),
              child: Text(
                statusLabel(status),
                maxLines: 1,
                style: AdvantaText.caption.copyWith(
                  color: isDark ? Colors.white : color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 44 : 22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: AdvantaText.caption.copyWith(
              color: _gotFetTextColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GotPlantPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF16210E);
    canvas.drawRect(Offset.zero & size, bg);

    final seedPaint = Paint()..color = const Color(0xFF4A3716);
    for (var y = 24.0; y < size.height; y += 22) {
      for (var x = 12.0; x < size.width; x += 28) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: 16, height: 10),
          seedPaint,
        );
      }
    }

    final stemPaint = Paint()
      ..color = AdvantaColors.success
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final leafPaint = Paint()
      ..color = AdvantaColors.lightGreen
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height * 0.58);
    canvas.drawLine(center, Offset(center.dx, size.height * 0.22), stemPaint);
    for (var i = 0; i < 6; i++) {
      final top = size.height * (0.28 + i * 0.065);
      final side = i.isEven ? -1.0 : 1.0;
      final path = Path()
        ..moveTo(center.dx, top)
        ..quadraticBezierTo(
          center.dx + side * size.width * 0.22,
          top - 28,
          center.dx + side * size.width * 0.32,
          top + 14,
        )
        ..quadraticBezierTo(
          center.dx + side * size.width * 0.18,
          top + 32,
          center.dx,
          top + 8,
        )
        ..close();
      canvas.drawPath(path, leafPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlotFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1D260F);
    canvas.drawRect(Offset.zero & size, bg);

    final rowPaint = Paint()
      ..color = const Color(0xFF5A3F17).withAlpha(150)
      ..strokeWidth = 8;
    for (var y = size.height * 0.08; y < size.height; y += size.height / 11) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 10), rowPaint);
    }

    final pointPaint = Paint()..color = AdvantaColors.lightGreen;
    for (var r = 0; r < _fetGridRows; r++) {
      for (var c = 0; c < _fetGridColumns; c++) {
        final dx = size.width * (0.07 + c * 0.095);
        final dy = size.height * (0.1 + r * 0.087);
        canvas.drawCircle(Offset(dx, dy), 3.8, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MarkerFramePainter extends CustomPainter {
  final bool showCenter;
  final bool showGrid;

  const _MarkerFramePainter({
    this.showCenter = false,
    this.showGrid = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 34.0;
    final contentRect =
        Rect.fromLTWH(12, 46, size.width - 24, size.height - 150);
    final rect = showGrid ? _squareRectInside(contentRect) : contentRect;

    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(len, 0), linePaint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(0, len), linePaint);
    canvas.drawLine(
        rect.topRight, rect.topRight - const Offset(len, 0), linePaint);
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(0, len), linePaint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + const Offset(len, 0), linePaint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft - const Offset(0, len), linePaint);
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight - const Offset(len, 0), linePaint);
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight - const Offset(0, len), linePaint);

    if (showCenter) {
      final center = rect.center;
      canvas.drawLine(center - const Offset(18, 0),
          center + const Offset(18, 0), linePaint);
      canvas.drawLine(center - const Offset(0, 18),
          center + const Offset(0, 18), linePaint);
    }

    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withAlpha(95)
        ..strokeWidth = 1;
      for (var i = 1; i < _fetGridColumns; i++) {
        final x = rect.left + rect.width * i / _fetGridColumns;
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      }
      for (var i = 1; i < _fetGridRows; i++) {
        final y = rect.top + rect.height * i / _fetGridRows;
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;

  Rect _squareRectInside(Rect rect) {
    final side = math.min(rect.width, rect.height);
    return Rect.fromCenter(center: rect.center, width: side, height: side);
  }
}
