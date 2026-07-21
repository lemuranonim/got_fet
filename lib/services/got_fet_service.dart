import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class GotFetService {
  GotFetService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const evidenceBucket = 'got_fet_evidence';
  static const samplesTable = 'got_fet_samples';
  static const gotObservationTable = 'got_fet_got_observation';
  static const fetObservationTable = 'got_fet_fet_observation';
  static const photoEvidenceTable = 'got_fet_photo_evidence';
  static const sampleTrackingTable = 'got_fet_sample_tracking';
  static const reviewHistoryTable = 'got_fet_review_history';
  static const masterFieldsTable = 'master_fields';
  static const offTypeRulesTable = 'got_fet_off_type_rules';
  static const offTypeDetailsTable = 'got_fet_off_type_details';

  Stream<List<Map<String, dynamic>>> watchSampleRows() {
    return _supabase
        .from(samplesTable)
        .stream(primaryKey: ['batch']).order('batch');
  }

  Stream<List<Map<String, dynamic>>> watchReviewTimelineRows({
    required String lotId,
    required String sampleId,
    required String module,
  }) {
    final trackingStream = _supabase
        .from(sampleTrackingTable)
        .stream(primaryKey: ['id'])
        .eq('lot_id', lotId)
        .order('event_datetime', ascending: false)
        .map((rows) => [
              for (final row in rows)
                {
                  ...Map<String, dynamic>.from(row),
                  '_source': 'tracking',
                },
            ]);

    final reviewStream = _supabase
        .from(reviewHistoryTable)
        .stream(primaryKey: ['id'])
        .eq('sample_id', sampleId)
        .order('review_datetime', ascending: false)
        .map((rows) => [
              for (final row in rows)
                if (row['lot_id']?.toString() == lotId &&
                    row['module']?.toString().toUpperCase() ==
                        module.toUpperCase())
                  {
                    ...Map<String, dynamic>.from(row),
                    '_source': 'review',
                  },
            ]);

    return _combineTimelineStreams(trackingStream, reviewStream);
  }

  Future<List<Map<String, dynamic>>> fetchSampleRows() async {
    final response = await _supabase.from(samplesTable).select().order('batch');
    return [
      for (final row in response) Map<String, dynamic>.from(row),
    ];
  }

  Future<void> updateSamplePlanning({
    required String batch,
    DateTime? plantingDate,
    int? weekOfPlanting,
    DateTime? resultEstimation,
    int? weekOfResultEstimation,
    String? noteTanam,
    String? location,
    String? village,
    String? subDistrict,
    String? district,
    double? latitude,
    double? longitude,
    double? fieldArea,
    String? statusSample,
  }) async {
    await _supabase.from(samplesTable).update({
      'planting_date': _dateOnly(plantingDate),
      'week_of_planting': weekOfPlanting,
      'result_estimation': _dateOnly(resultEstimation),
      'week_of_result_estimation': weekOfResultEstimation,
      'note_tanam': noteTanam,
      'location': location,
      'village_desa': village,
      'sub_district_kec': subDistrict,
      'district_kab': district,
      'latitude': latitude,
      'longitude': longitude,
      'field_area': fieldArea,
      'status_sample': statusSample,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('batch', batch);
  }

  Future<void> updateSampleStatus({
    required String batch,
    required String status,
  }) async {
    await _supabase.from(samplesTable).update({
      'status_sample': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('batch', batch);
  }

  Future<List<Map<String, dynamic>>> fetchVillageCoordinateRows() async {
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var from = 0;

    while (true) {
      final response = await _supabase.from(masterFieldsTable).select('''
        region,
        district_kab,
        sub_district_kec,
        village_desa,
        coordinate,
        correction_tagging
      ''').range(from, from + pageSize - 1);
      final page = [
        for (final row in response) Map<String, dynamic>.from(row),
      ];
      rows.addAll(page);
      if (page.length < pageSize) break;
      from += pageSize;
    }

    return rows;
  }

  Future<List<Map<String, dynamic>>> fetchOffTypeRuleRows() async {
    final response = await _supabase
        .from(offTypeRulesTable)
        .select()
        .eq('is_active', true)
        .order('category_no')
        .order('type_code');
    return [
      for (final row in response) Map<String, dynamic>.from(row),
    ];
  }

  Future<void> markSamplePlanted({
    required String batch,
    required String lotId,
    required DateTime plantingDate,
    required int weekOfPlanting,
    required DateTime resultEstimation,
    required int weekOfResultEstimation,
    required String location,
    required String village,
    required String subDistrict,
    required String district,
    required double latitude,
    required double longitude,
    required double fieldArea,
    required String actor,
  }) async {
    await updateSamplePlanning(
      batch: batch,
      plantingDate: plantingDate,
      weekOfPlanting: weekOfPlanting,
      resultEstimation: resultEstimation,
      weekOfResultEstimation: weekOfResultEstimation,
      noteTanam: 'Done',
      location: location,
      village: village,
      subDistrict: subDistrict,
      district: district,
      latitude: latitude,
      longitude: longitude,
      fieldArea: fieldArea,
      statusSample: 'Planted',
    );
    await appendTrackingEvent(
      lotId: lotId,
      status: 'Planted',
      actor: actor,
      remarks: 'Batch $batch ditandai Tanam berdasarkan Village Coordinate',
      eventAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Stream<List<Map<String, dynamic>>> watchGotObservationRows({
    required String lotId,
    required String sampleId,
    required String plotId,
    required String stage,
  }) {
    return _supabase
        .from(gotObservationTable)
        .stream(primaryKey: ['id'])
        .eq('sample_id', sampleId)
        .order('submitted_datetime', ascending: false)
        .map((rows) {
          final filteredRows = [
            for (final row in rows)
              if (row['lot_id']?.toString() == lotId &&
                  row['plot_id']?.toString() == plotId &&
                  row['observation_stage']?.toString() == stage)
                Map<String, dynamic>.from(row),
          ];
          filteredRows.sort((a, b) {
            final aDate = DateTime.tryParse(
                  a['submitted_datetime']?.toString() ?? '',
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = DateTime.tryParse(
                  b['submitted_datetime']?.toString() ?? '',
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          return filteredRows;
        });
  }

  Future<Map<String, dynamic>?> fetchLatestGotObservation({
    required String lotId,
    required String sampleId,
    required String plotId,
    required String stage,
  }) async {
    final response = await _supabase
        .from(gotObservationTable)
        .select()
        .eq('lot_id', lotId)
        .eq('sample_id', sampleId)
        .eq('plot_id', plotId)
        .eq('observation_stage', stage)
        .order('submitted_datetime', ascending: false)
        .limit(1);

    if (response.isEmpty) return null;
    return Map<String, dynamic>.from(response.first);
  }

  Stream<List<Map<String, dynamic>>> watchFetObservationRows({
    required String lotId,
    required String sampleId,
    required String plotId,
    required int replication,
  }) {
    return _supabase
        .from(fetObservationTable)
        .stream(primaryKey: ['id'])
        .eq('sample_id', sampleId)
        .order('submitted_datetime', ascending: false)
        .map((rows) {
          final filteredRows = [
            for (final row in rows)
              if (row['lot_id']?.toString() == lotId &&
                  row['plot_id']?.toString() == plotId &&
                  row['replication']?.toString() == replication.toString())
                Map<String, dynamic>.from(row),
          ];
          filteredRows.sort((a, b) {
            final aDate = DateTime.tryParse(
                  a['submitted_datetime']?.toString() ?? '',
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = DateTime.tryParse(
                  b['submitted_datetime']?.toString() ?? '',
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          return filteredRows;
        });
  }

  Future<Map<String, dynamic>?> fetchLatestFetObservation({
    required String lotId,
    required String sampleId,
    required String plotId,
    required int replication,
  }) async {
    final response = await _supabase
        .from(fetObservationTable)
        .select()
        .eq('lot_id', lotId)
        .eq('sample_id', sampleId)
        .eq('plot_id', plotId)
        .eq('replication', replication)
        .order('submitted_datetime', ascending: false)
        .limit(1);

    if (response.isEmpty) return null;
    return Map<String, dynamic>.from(response.first);
  }

  Future<void> submitGotObservation({
    required String lotId,
    required String sampleId,
    required String hybrid,
    required String plotId,
    required String stage,
    required int totalObserved,
    required int offTypeCount,
    required int selfingCount,
    required int maleCount,
    required int suspiciousCount,
    required int trueTypeCount,
    required double purityPercent,
    required String submittedBy,
    required List<File> evidencePhotos,
    String? remarks,
  }) async {
    final submittedAt = DateTime.now().toUtc().toIso8601String();
    final photoUrls = await uploadEvidencePhotos(
      files: evidencePhotos,
      lotId: lotId,
      module: 'got',
    );

    final payload = {
      'lot_id': lotId,
      'sample_id': sampleId,
      'hybrid': hybrid,
      'plot_id': plotId,
      'observation_stage': stage,
      'total_observed': totalObserved,
      'off_type_count': offTypeCount,
      'selfing_count': selfingCount,
      'male_count': maleCount,
      'suspicious_count': suspiciousCount,
      'true_type_count': trueTypeCount,
      'purity_percent': purityPercent,
      'remarks': remarks,
      'submitted_by': submittedBy,
      'submitted_datetime': submittedAt,
      'review_status': 'Submitted',
      'created_by_user_id': _supabase.auth.currentUser?.id,
    };

    final existing = await fetchLatestGotObservation(
      lotId: lotId,
      sampleId: sampleId,
      plotId: plotId,
      stage: stage,
    );

    if (existing == null) {
      await _supabase.from(gotObservationTable).insert(payload);
    } else {
      final existingId = existing['id'];
      final update = Map<String, dynamic>.from(payload)
        ..remove('created_by_user_id');
      if (existingId != null) {
        await _supabase
            .from(gotObservationTable)
            .update(update)
            .eq('id', existingId);
      } else {
        await _supabase
            .from(gotObservationTable)
            .update(update)
            .eq('lot_id', lotId)
            .eq('sample_id', sampleId)
            .eq('plot_id', plotId)
            .eq('observation_stage', stage);
      }
    }

    await _insertPhotoEvidence(
      lotId: lotId,
      sampleId: sampleId,
      testType: 'GOT',
      module: 'got',
      plotId: plotId,
      uploadedBy: submittedBy,
      uploadedAt: submittedAt,
      photoUrls: photoUrls,
    );

    await appendTrackingEvent(
      lotId: lotId,
      status: 'Submitted',
      actor: submittedBy,
      remarks: 'GOT observation submitted',
      eventAt: submittedAt,
    );
  }

  Future<void> submitFetObservation({
    required String lotId,
    required String sampleId,
    required String hybrid,
    required String plotId,
    required int replication,
    required int dap,
    required int totalPoints,
    required int grownCount,
    required int notGrownCount,
    required int reviewCount,
    required int notReadableCount,
    required double emergencePercent,
    required List<String> pointStatuses,
    required String submittedBy,
    File? plotPhoto,
    String? remarks,
  }) async {
    final submittedAt = DateTime.now().toUtc().toIso8601String();
    final photoUrls = plotPhoto == null
        ? <String>[]
        : await uploadEvidencePhotos(
            files: [plotPhoto],
            lotId: lotId,
            module: 'fet',
            replication: 'u$replication',
          );

    final payload = {
      'lot_id': lotId,
      'sample_id': sampleId,
      'hybrid': hybrid,
      'plot_id': plotId,
      'replication': replication,
      'dap': dap,
      'total_points': totalPoints,
      'grown_count': grownCount,
      'not_grown_count': notGrownCount,
      'review_count': reviewCount,
      'not_readable_count': notReadableCount,
      'emergence_percent': emergencePercent,
      'point_statuses': [
        for (var i = 0; i < pointStatuses.length; i++)
          {'point_no': i + 1, 'status': pointStatuses[i]},
      ],
      'plot_photo_url': photoUrls.isEmpty ? null : photoUrls.first,
      'remarks': remarks,
      'submitted_by': submittedBy,
      'submitted_datetime': submittedAt,
      'review_status': 'Submitted',
      'created_by_user_id': _supabase.auth.currentUser?.id,
      'updated_at': submittedAt,
    };

    await _supabase.from(fetObservationTable).upsert(
          payload,
          onConflict: 'lot_id,sample_id,plot_id,replication',
        );

    await _insertPhotoEvidence(
      lotId: lotId,
      sampleId: sampleId,
      testType: 'FET',
      module: 'fet',
      plotId: plotId,
      replication: replication.toString(),
      uploadedBy: submittedBy,
      uploadedAt: submittedAt,
      photoUrls: photoUrls,
    );

    await appendTrackingEvent(
      lotId: lotId,
      status: 'Submitted',
      actor: submittedBy,
      remarks: 'FET replication $replication submitted',
      eventAt: submittedAt,
    );
  }

  Future<void> submitReviewDecision({
    required String lotId,
    required String sampleId,
    required String module,
    required String previousStatus,
    required String newStatus,
    required String reviewer,
    String? remarks,
  }) async {
    final reviewedAt = DateTime.now().toUtc().toIso8601String();

    await _supabase.from('got_fet_review_history').insert({
      'lot_id': lotId,
      'sample_id': sampleId,
      'module': module,
      'previous_status': previousStatus,
      'new_status': newStatus,
      'review_action': newStatus,
      'reviewer': reviewer,
      'review_datetime': reviewedAt,
      'remarks': remarks,
      'created_by_user_id': _supabase.auth.currentUser?.id,
    });

    if (newStatus == 'Approved' || newStatus == 'Rejected') {
      await _supabase.from('got_fet_final_decision').insert({
        'lot_id': lotId,
        'sample_id': sampleId,
        'module': module,
        'decision': newStatus,
        'decided_by': reviewer,
        'decision_datetime': reviewedAt,
        'remarks': remarks,
        'created_by_user_id': _supabase.auth.currentUser?.id,
      });
    }

    await appendTrackingEvent(
      lotId: lotId,
      status: newStatus,
      actor: reviewer,
      remarks: remarks,
      eventAt: reviewedAt,
    );
  }

  Stream<List<Map<String, dynamic>>> watchGotOffTypeDetailRows({
    required String lotId,
    required String sampleId,
    required String plotId,
    required String stage,
  }) {
    return _supabase
        .from(offTypeDetailsTable)
        .stream(primaryKey: ['id'])
        .eq('sample_id', sampleId)
        .order('sort_order')
        .map((rows) => [
              for (final row in rows)
                if (row['lot_id']?.toString() == lotId &&
                    row['plot_id']?.toString() == plotId &&
                    row['observation_stage']?.toString() == stage)
                  Map<String, dynamic>.from(row),
            ]);
  }

  Future<Map<String, dynamic>> saveGotOffTypeDetail({
    String? id,
    required String lotId,
    required String sampleId,
    required String plotId,
    required String stage,
    required String ruleId,
    required int categoryNo,
    required String typeCode,
    required String typeLabel,
    required String characterNote,
    required String similarityAssessment,
    required String referenceHybrid,
    required int requiredPhotoCount,
    required int sortOrder,
    required String actor,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'lot_id': lotId,
      'sample_id': sampleId,
      'plot_id': plotId,
      'observation_stage': stage,
      'rule_id': ruleId,
      'category_no': categoryNo,
      'type_code': typeCode,
      'type_label': typeLabel,
      'character_note': characterNote,
      'similarity_assessment': similarityAssessment,
      'reference_hybrid': referenceHybrid,
      'required_photo_count': requiredPhotoCount,
      'sort_order': sortOrder,
      'updated_by': actor,
      'updated_at': now,
    };

    if (id == null || id.trim().isEmpty) {
      final response = await _supabase
          .from(offTypeDetailsTable)
          .insert({
            ...payload,
            'created_by': actor,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }

    final response = await _supabase
        .from(offTypeDetailsTable)
        .update(payload)
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> deleteGotOffTypeDetail(String id) async {
    await _supabase.from(offTypeDetailsTable).delete().eq('id', id);
  }

  Stream<List<Map<String, dynamic>>> watchGotEvidenceRows({
    required String lotId,
    required String sampleId,
    required String plotId,
    required String stage,
  }) {
    return _supabase
        .from(photoEvidenceTable)
        .stream(primaryKey: ['id'])
        .eq('sample_id', sampleId)
        .order('uploaded_datetime', ascending: false)
        .map((rows) {
          final filteredRows = [
            for (final row in rows)
              if (row['lot_id']?.toString() == lotId &&
                  row['module']?.toString().toLowerCase() == 'got' &&
                  row['plot_id']?.toString() == plotId &&
                  row['observation_stage']?.toString() == stage)
                Map<String, dynamic>.from(row),
          ];
          filteredRows.sort((a, b) {
            final aDate = DateTime.tryParse(
                  a['uploaded_datetime']?.toString() ?? '',
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = DateTime.tryParse(
                  b['uploaded_datetime']?.toString() ?? '',
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          return filteredRows;
        });
  }

  Future<void> saveGotEvidencePhoto({
    required File file,
    required String lotId,
    required String sampleId,
    required String plotId,
    required String stage,
    required String category,
    required int rcvNo,
    required String rcvLabel,
    required String uploadedBy,
    String? offTypeDetailId,
  }) async {
    final uploadedAt = DateTime.now().toUtc().toIso8601String();
    if (!file.existsSync()) {
      throw const GotFetStorageException(
        'File foto tidak ditemukan di perangkat setelah capture.',
      );
    }
    if (file.lengthSync() == 0) {
      throw const GotFetStorageException(
        'File foto kosong, silakan capture ulang.',
      );
    }

    final uploadedPath = await _uploadEvidencePhoto(
      file: file,
      lotId: lotId,
      module: 'got',
      stage: stage,
      category:
          offTypeDetailId == null ? category : '${category}_$offTypeDetailId',
      replication: rcvLabel,
    );
    final photoUrl =
        _supabase.storage.from(evidenceBucket).getPublicUrl(uploadedPath);
    final payload = {
      'lot_id': lotId,
      'sample_id': sampleId,
      'test_type': 'GOT',
      'module': 'got',
      'plot_id': plotId,
      'replication': rcvLabel,
      'observation_stage': stage,
      'evidence_category': category,
      'rcv_no': rcvNo,
      'rcv_label': rcvLabel,
      'off_type_detail_id': offTypeDetailId,
      'storage_path': uploadedPath,
      'photo_url': photoUrl,
      'uploaded_by': uploadedBy,
      'uploaded_datetime': uploadedAt,
      'review_status': 'Submitted',
      'created_by_user_id': _supabase.auth.currentUser?.id,
      'updated_at': uploadedAt,
    };

    try {
      final candidates = await _supabase
          .from(photoEvidenceTable)
          .select('id, off_type_detail_id')
          .eq('lot_id', lotId)
          .eq('sample_id', sampleId)
          .eq('module', 'got')
          .eq('plot_id', plotId)
          .eq('observation_stage', stage)
          .eq('evidence_category', category)
          .eq('rcv_no', rcvNo);
      final existing = [
        for (final row in candidates)
          if (row['off_type_detail_id']?.toString() == offTypeDetailId) row,
      ];

      if (existing.isEmpty) {
        await _supabase.from(photoEvidenceTable).insert(payload);
        return;
      }

      final existingId = existing.first['id'];
      if (existingId == null) {
        throw const GotFetStorageException(
          'Metadata evidence ditemukan tanpa ID yang valid.',
        );
      }

      await _supabase
          .from(photoEvidenceTable)
          .update(payload)
          .eq('id', existingId as Object);
    } catch (error) {
      throw GotFetStorageException(
        'Foto sudah terupload ke Storage, tapi metadata gagal disimpan ke tabel $photoEvidenceTable. '
        'Pastikan schema/policy tabel evidence sudah dijalankan. Detail: ${_errorMessage(error)}',
      );
    }
  }

  Future<List<String>> uploadEvidencePhotos({
    required Iterable<File> files,
    required String lotId,
    required String module,
    String? replication,
  }) async {
    final urls = <String>[];
    for (final file in files) {
      final uploadedPath = await _uploadEvidencePhoto(
        file: file,
        lotId: lotId,
        module: module,
        replication: replication,
      );
      urls.add(
          _supabase.storage.from(evidenceBucket).getPublicUrl(uploadedPath));
    }
    return urls;
  }

  Future<void> appendTrackingEvent({
    required String lotId,
    required String status,
    required String actor,
    String? remarks,
    String? eventAt,
  }) async {
    await _supabase.from('got_fet_sample_tracking').insert({
      'lot_id': lotId,
      'status': status,
      'actor': actor,
      'event_datetime': eventAt ?? DateTime.now().toUtc().toIso8601String(),
      'remarks': remarks,
      'created_by_user_id': _supabase.auth.currentUser?.id,
    });
  }

  Stream<List<Map<String, dynamic>>> _combineTimelineStreams(
    Stream<List<Map<String, dynamic>>> trackingStream,
    Stream<List<Map<String, dynamic>>> reviewStream,
  ) {
    late final StreamController<List<Map<String, dynamic>>> controller;
    StreamSubscription<List<Map<String, dynamic>>>? trackingSubscription;
    StreamSubscription<List<Map<String, dynamic>>>? reviewSubscription;
    var trackingRows = <Map<String, dynamic>>[];
    var reviewRows = <Map<String, dynamic>>[];

    void emit() {
      if (controller.isClosed) return;
      final rows = [...trackingRows, ...reviewRows];
      rows.sort((a, b) {
        final aDate = DateTime.tryParse(
              (a['event_datetime'] ?? a['review_datetime'])?.toString() ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(
              (b['event_datetime'] ?? b['review_datetime'])?.toString() ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      controller.add(rows);
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        trackingSubscription = trackingStream.listen(
          (rows) {
            trackingRows = rows;
            emit();
          },
          onError: controller.addError,
        );
        reviewSubscription = reviewStream.listen(
          (rows) {
            reviewRows = rows;
            emit();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await trackingSubscription?.cancel();
        await reviewSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  Future<String> _uploadEvidencePhoto({
    required File file,
    required String lotId,
    required String module,
    String? stage,
    String? category,
    String? replication,
  }) async {
    final safeLotId = _safeSegment(lotId);
    final safeModule = _safeSegment(module);
    final safeStage = _safeSegment(stage ?? 'main');
    final safeCategory = _safeSegment(category ?? 'general');
    final safeReplication = _safeSegment(replication ?? 'main');
    final extension = _fileExtension(file.path);
    final contentType = _contentTypeForExtension(extension);
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final objectPath =
        '$safeLotId/$safeModule/$safeStage/$safeCategory/$safeReplication/$fileName';

    try {
      await _supabase.storage.from(evidenceBucket).upload(
            objectPath,
            file,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );
    } catch (error) {
      throw GotFetStorageException(
        'Upload foto ke bucket "$evidenceBucket" gagal. '
        'Pastikan bucket Storage, MIME type image, dan policy upload sudah aktif. '
        'Detail: ${_errorMessage(error)}',
      );
    }

    return objectPath;
  }

  Future<void> _insertPhotoEvidence({
    required String lotId,
    required String sampleId,
    required String testType,
    required String module,
    required String plotId,
    required String uploadedBy,
    required String uploadedAt,
    required List<String> photoUrls,
    String? replication,
  }) async {
    if (photoUrls.isEmpty) return;

    await _supabase.from(photoEvidenceTable).insert([
      for (final url in photoUrls)
        {
          'lot_id': lotId,
          'sample_id': sampleId,
          'test_type': testType,
          'module': module,
          'plot_id': plotId,
          'replication': replication,
          'photo_url': url,
          'uploaded_by': uploadedBy,
          'uploaded_datetime': uploadedAt,
          'review_status': 'Submitted',
          'created_by_user_id': _supabase.auth.currentUser?.id,
        },
    ]);
  }

  String _safeSegment(String value) {
    return value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
  }

  String _fileExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return 'jpg';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  String _contentTypeForExtension(String extension) {
    return switch (extension.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'jpeg' || 'jpg' => 'image/jpeg',
      _ => 'image/jpeg',
    };
  }

  String _errorMessage(Object error) {
    if (error is StorageException) return error.message;
    if (error is PostgrestException) return error.message;
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  String? _dateOnly(DateTime? value) {
    if (value == null) return null;
    return value.toIso8601String().split('T').first;
  }
}

class GotFetStorageException implements Exception {
  final String message;

  const GotFetStorageException(this.message);

  @override
  String toString() => message;
}
