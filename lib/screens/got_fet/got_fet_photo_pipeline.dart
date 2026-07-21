part of 'got_fet_screen.dart';

class _SmartPhotoPipeline {
  static const _queueKey = 'got_fet.smart_photo.queue';
  static const _fingerprintsKey = 'got_fet.smart_photo.fingerprints';
  static const _fingerprintLimit = 90;

  SharedPreferences? _prefs;
  Directory? _photoRoot;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    final supportDir = await getApplicationSupportDirectory();
    final photoRoot =
        Directory('${supportDir.path}${Platform.pathSeparator}got_fet_photos');
    if (!photoRoot.existsSync()) {
      await photoRoot.create(recursive: true);
    }
    _photoRoot = photoRoot;
  }

  Future<_PreparedSmartPhoto> preparePhoto({
    required XFile image,
    required _SmartPhotoContext context,
  }) async {
    await initialize();
    final sourceFile = File(image.path);
    if (!sourceFile.existsSync()) {
      throw const GotFetStorageException(
          'File foto tidak ditemukan setelah capture.');
    }

    final bytes = await sourceFile.readAsBytes();
    final fingerprint = sha1.convert(bytes).toString();
    final analysis = await _SmartPhotoQuality.analyze(bytes);
    final metadata = _SmartPhotoMetadata(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      module: context.module,
      lotId: context.lotId,
      sampleId: context.sampleId,
      plotId: context.plotId,
      stage: context.stage,
      label: context.label,
      source: context.source,
      capturedBy: context.actor,
      capturedAt: DateTime.now().toUtc(),
      localPath: '',
      fingerprint: fingerprint,
      width: analysis.width,
      height: analysis.height,
      fileBytes: bytes.length,
      averageLuma: analysis.averageLuma,
      edgeScore: analysis.edgeScore,
      warnings: analysis.warnings,
    );
    final localFile = await _copyIntoManagedFolder(
      sourceFile: sourceFile,
      metadata: metadata,
      extension: _extensionForPath(sourceFile.path),
    );
    final duplicateLikely = _fingerprints().contains(fingerprint);
    final hydratedMetadata = metadata.copyWith(localPath: localFile.path);
    await _rememberFingerprint(fingerprint);

    return _PreparedSmartPhoto(
      file: localFile,
      metadata: hydratedMetadata,
      duplicateLikely: duplicateLikely,
    );
  }

  Future<void> enqueueGotEvidence({
    required _PreparedSmartPhoto prepared,
    required _GotEvidenceSlot slot,
    required String lotId,
    required String sampleId,
    required String plotId,
    required String stage,
    required String uploadedBy,
  }) async {
    await initialize();
    final entries = _queueEntries();
    final entry = _QueuedGotEvidencePhoto(
      id: prepared.metadata.id,
      localPath: prepared.file.path,
      lotId: lotId,
      sampleId: sampleId,
      plotId: plotId,
      stage: stage,
      category: slot.evidenceCategoryKey,
      offTypeDetailId: slot.offTypeDetailId,
      rcvNo: slot.rcvNo,
      rcvLabel: slot.label,
      uploadedBy: uploadedBy,
      queuedAt: DateTime.now().toUtc(),
      metadata: prepared.metadata,
    );
    final nextEntries = [
      for (final item in entries)
        if (item.id != entry.id) item,
      entry,
    ];
    await _saveQueue(nextEntries);
  }

  Future<int> syncPendingGotEvidence(GotFetService service) async {
    await initialize();
    final entries = _queueEntries();
    if (entries.isEmpty) return 0;

    var synced = 0;
    final remaining = <_QueuedGotEvidencePhoto>[];
    for (final entry in entries) {
      final file = File(entry.localPath);
      if (!file.existsSync() || file.lengthSync() == 0) {
        synced++;
        continue;
      }
      try {
        await service.saveGotEvidencePhoto(
          file: file,
          lotId: entry.lotId,
          sampleId: entry.sampleId,
          plotId: entry.plotId,
          stage: entry.stage,
          category: entry.category,
          rcvNo: entry.rcvNo,
          rcvLabel: entry.rcvLabel,
          uploadedBy: entry.uploadedBy,
          offTypeDetailId: entry.offTypeDetailId,
        );
        synced++;
      } catch (_) {
        remaining.add(entry);
      }
    }
    await _saveQueue(remaining);
    return synced;
  }

  Future<_SmartPhotoStatus> status() async {
    await initialize();
    final entries = _queueEntries();
    return _SmartPhotoStatus(
      pendingUploads: entries.length,
      lastQueuedAt: entries.isEmpty ? null : entries.last.queuedAt,
    );
  }

  Future<File> _copyIntoManagedFolder({
    required File sourceFile,
    required _SmartPhotoMetadata metadata,
    required String extension,
  }) async {
    final root = _photoRoot;
    if (root == null) {
      throw const GotFetStorageException(
          'Folder lokal smart camera belum siap.');
    }
    final moduleDir = Directory(
      [
        root.path,
        _safeSegment(metadata.module),
        _safeSegment(metadata.lotId),
        _safeSegment(metadata.sampleId),
      ].join(Platform.pathSeparator),
    );
    if (!moduleDir.existsSync()) {
      await moduleDir.create(recursive: true);
    }
    final nameParts = [
      metadata.capturedAt.toIso8601String().replaceAll(RegExp(r'[:.]'), ''),
      _safeSegment(metadata.stage ?? 'main'),
      _safeSegment(metadata.label),
    ];
    final target = File(
      '${moduleDir.path}${Platform.pathSeparator}${nameParts.join('_')}.$extension',
    );
    return sourceFile.copy(target.path);
  }

  List<_QueuedGotEvidencePhoto> _queueEntries() {
    final raw = _prefs?.getString(_queueKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return [
        for (final item in data)
          if (item is Map<String, dynamic>)
            _QueuedGotEvidencePhoto.fromJson(item)
          else if (item is Map)
            _QueuedGotEvidencePhoto.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveQueue(List<_QueuedGotEvidencePhoto> entries) async {
    await _prefs?.setString(
      _queueKey,
      jsonEncode([for (final entry in entries) entry.toJson()]),
    );
  }

  List<String> _fingerprints() {
    final raw = _prefs?.getStringList(_fingerprintsKey);
    return raw == null ? const [] : List<String>.from(raw);
  }

  Future<void> _rememberFingerprint(String fingerprint) async {
    final current = _fingerprints();
    final next = [
      fingerprint,
      for (final item in current)
        if (item != fingerprint) item,
    ].take(_fingerprintLimit).toList();
    await _prefs?.setStringList(_fingerprintsKey, next);
  }

  String _extensionForPath(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) return 'jpg';
    final ext = path.substring(dotIndex + 1).toLowerCase();
    return switch (ext) {
      'jpeg' || 'jpg' || 'png' || 'webp' => ext == 'jpeg' ? 'jpg' : ext,
      _ => 'jpg',
    };
  }

  String _safeSegment(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    return safe.isEmpty ? 'item' : safe;
  }
}

class _SmartPhotoContext {
  final String module;
  final String lotId;
  final String sampleId;
  final String? plotId;
  final String? stage;
  final String label;
  final String source;
  final String actor;

  const _SmartPhotoContext({
    required this.module,
    required this.lotId,
    required this.sampleId,
    required this.plotId,
    required this.stage,
    required this.label,
    required this.source,
    required this.actor,
  });
}

class _PreparedSmartPhoto {
  final File file;
  final _SmartPhotoMetadata metadata;
  final bool duplicateLikely;

  const _PreparedSmartPhoto({
    required this.file,
    required this.metadata,
    required this.duplicateLikely,
  });

  String get summary {
    final mb = metadata.fileBytes / (1024 * 1024);
    final parts = [
      '${metadata.width}x${metadata.height}',
      '${mb.toStringAsFixed(1)} MB',
      if (duplicateLikely) 'mirip foto sebelumnya',
      if (metadata.warnings.isNotEmpty) metadata.warnings.first,
    ];
    return parts.join(' | ');
  }
}

class _SmartPhotoMetadata {
  final String id;
  final String module;
  final String lotId;
  final String sampleId;
  final String? plotId;
  final String? stage;
  final String label;
  final String source;
  final String capturedBy;
  final DateTime capturedAt;
  final String localPath;
  final String fingerprint;
  final int width;
  final int height;
  final int fileBytes;
  final double averageLuma;
  final double edgeScore;
  final List<String> warnings;

  const _SmartPhotoMetadata({
    required this.id,
    required this.module,
    required this.lotId,
    required this.sampleId,
    required this.plotId,
    required this.stage,
    required this.label,
    required this.source,
    required this.capturedBy,
    required this.capturedAt,
    required this.localPath,
    required this.fingerprint,
    required this.width,
    required this.height,
    required this.fileBytes,
    required this.averageLuma,
    required this.edgeScore,
    required this.warnings,
  });

  String get watermarkText {
    final localTime = capturedAt.toLocal().toString().substring(0, 16);
    return [
      module.toUpperCase(),
      lotId,
      if (plotId != null && plotId!.isNotEmpty) plotId,
      if (stage != null && stage!.isNotEmpty) stage,
      label,
      capturedBy,
      localTime,
    ].join(' | ');
  }

  bool get needsReview => warnings.isNotEmpty;

  _SmartPhotoMetadata copyWith({String? localPath}) {
    return _SmartPhotoMetadata(
      id: id,
      module: module,
      lotId: lotId,
      sampleId: sampleId,
      plotId: plotId,
      stage: stage,
      label: label,
      source: source,
      capturedBy: capturedBy,
      capturedAt: capturedAt,
      localPath: localPath ?? this.localPath,
      fingerprint: fingerprint,
      width: width,
      height: height,
      fileBytes: fileBytes,
      averageLuma: averageLuma,
      edgeScore: edgeScore,
      warnings: warnings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'module': module,
      'lotId': lotId,
      'sampleId': sampleId,
      'plotId': plotId,
      'stage': stage,
      'label': label,
      'source': source,
      'capturedBy': capturedBy,
      'capturedAt': capturedAt.toIso8601String(),
      'localPath': localPath,
      'fingerprint': fingerprint,
      'width': width,
      'height': height,
      'fileBytes': fileBytes,
      'averageLuma': averageLuma,
      'edgeScore': edgeScore,
      'warnings': warnings,
    };
  }

  factory _SmartPhotoMetadata.fromJson(Map<String, dynamic> json) {
    return _SmartPhotoMetadata(
      id: json['id']?.toString() ?? '',
      module: json['module']?.toString() ?? 'got',
      lotId: json['lotId']?.toString() ?? '-',
      sampleId: json['sampleId']?.toString() ?? '-',
      plotId: json['plotId']?.toString(),
      stage: json['stage']?.toString(),
      label: json['label']?.toString() ?? '-',
      source: json['source']?.toString() ?? 'camera',
      capturedBy: json['capturedBy']?.toString() ?? '-',
      capturedAt: DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      localPath: json['localPath']?.toString() ?? '',
      fingerprint: json['fingerprint']?.toString() ?? '',
      width: _jsonInt(json['width']),
      height: _jsonInt(json['height']),
      fileBytes: _jsonInt(json['fileBytes']),
      averageLuma: _jsonDouble(json['averageLuma']),
      edgeScore: _jsonDouble(json['edgeScore']),
      warnings: [
        for (final item in (json['warnings'] as List? ?? const []))
          item.toString(),
      ],
    );
  }
}

class _SmartPhotoQuality {
  final int width;
  final int height;
  final double averageLuma;
  final double edgeScore;
  final List<String> warnings;

  const _SmartPhotoQuality({
    required this.width,
    required this.height,
    required this.averageLuma,
    required this.edgeScore,
    required this.warnings,
  });

  static Future<_SmartPhotoQuality> analyze(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec(targetWidth: 40);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = byteData?.buffer.asUint8List() ?? Uint8List(0);
      final stats = _samplePixelStats(
        pixels: pixels,
        width: image.width,
        height: image.height,
      );
      final warnings = <String>[];
      final minSide = math.min(descriptor.width, descriptor.height);
      if (minSide < 900) warnings.add('resolusi rendah');
      if (bytes.length > 8 * 1024 * 1024) warnings.add('file besar');
      if (stats.averageLuma < 54) warnings.add('foto gelap');
      if (stats.edgeScore < 5.2) warnings.add('potensi blur');
      return _SmartPhotoQuality(
        width: descriptor.width,
        height: descriptor.height,
        averageLuma: stats.averageLuma,
        edgeScore: stats.edgeScore,
        warnings: warnings,
      );
    } catch (_) {
      return _SmartPhotoQuality(
        width: 0,
        height: 0,
        averageLuma: 0,
        edgeScore: 0,
        warnings: const ['quality check gagal'],
      );
    } finally {
      image?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static ({double averageLuma, double edgeScore}) _samplePixelStats({
    required Uint8List pixels,
    required int width,
    required int height,
  }) {
    if (pixels.isEmpty || width <= 1 || height <= 1) {
      return (averageLuma: 0, edgeScore: 0);
    }
    final lumas = List<double>.filled(width * height, 0);
    var totalLuma = 0.0;
    for (var i = 0, pixelIndex = 0;
        i < pixels.length - 3;
        i += 4, pixelIndex++) {
      final luma =
          pixels[i] * 0.2126 + pixels[i + 1] * 0.7152 + pixels[i + 2] * 0.0722;
      lumas[pixelIndex] = luma;
      totalLuma += luma;
    }

    var edgeTotal = 0.0;
    var edgeCount = 0;
    for (var y = 1; y < height; y++) {
      for (var x = 1; x < width; x++) {
        final index = y * width + x;
        final dx = (lumas[index] - lumas[index - 1]).abs();
        final dy = (lumas[index] - lumas[index - width]).abs();
        edgeTotal += dx + dy;
        edgeCount += 2;
      }
    }
    return (
      averageLuma: totalLuma / lumas.length,
      edgeScore: edgeCount == 0 ? 0 : edgeTotal / edgeCount,
    );
  }
}

class _QueuedGotEvidencePhoto {
  final String id;
  final String localPath;
  final String lotId;
  final String sampleId;
  final String plotId;
  final String stage;
  final String category;
  final String? offTypeDetailId;
  final int rcvNo;
  final String rcvLabel;
  final String uploadedBy;
  final DateTime queuedAt;
  final _SmartPhotoMetadata metadata;

  const _QueuedGotEvidencePhoto({
    required this.id,
    required this.localPath,
    required this.lotId,
    required this.sampleId,
    required this.plotId,
    required this.stage,
    required this.category,
    this.offTypeDetailId,
    required this.rcvNo,
    required this.rcvLabel,
    required this.uploadedBy,
    required this.queuedAt,
    required this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'localPath': localPath,
      'lotId': lotId,
      'sampleId': sampleId,
      'plotId': plotId,
      'stage': stage,
      'category': category,
      'offTypeDetailId': offTypeDetailId,
      'rcvNo': rcvNo,
      'rcvLabel': rcvLabel,
      'uploadedBy': uploadedBy,
      'queuedAt': queuedAt.toIso8601String(),
      'metadata': metadata.toJson(),
    };
  }

  factory _QueuedGotEvidencePhoto.fromJson(Map<String, dynamic> json) {
    final metadataJson = json['metadata'];
    return _QueuedGotEvidencePhoto(
      id: json['id']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      lotId: json['lotId']?.toString() ?? '-',
      sampleId: json['sampleId']?.toString() ?? '-',
      plotId: json['plotId']?.toString() ?? '-',
      stage: json['stage']?.toString() ?? '-',
      category: json['category']?.toString() ?? '-',
      offTypeDetailId: json['offTypeDetailId']?.toString(),
      rcvNo: _jsonInt(json['rcvNo']),
      rcvLabel: json['rcvLabel']?.toString() ?? '-',
      uploadedBy: json['uploadedBy']?.toString() ?? '-',
      queuedAt: DateTime.tryParse(json['queuedAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      metadata: metadataJson is Map<String, dynamic>
          ? _SmartPhotoMetadata.fromJson(metadataJson)
          : _SmartPhotoMetadata.fromJson(
              metadataJson is Map
                  ? Map<String, dynamic>.from(metadataJson)
                  : const {},
            ),
    );
  }
}

class _SmartPhotoStatus {
  final int pendingUploads;
  final DateTime? lastQueuedAt;

  const _SmartPhotoStatus({
    this.pendingUploads = 0,
    this.lastQueuedAt,
  });
}

int _jsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _jsonDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
