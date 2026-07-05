part of 'got_fet_screen.dart';

enum _CameraAlignmentMode { portrait, overhead }

class _StandaloneCameraScreen extends StatefulWidget {
  final _InspectionModule module;
  final String title;
  final String subtitle;

  const _StandaloneCameraScreen({
    required this.module,
    required this.title,
    required this.subtitle,
  });

  @override
  State<_StandaloneCameraScreen> createState() =>
      _StandaloneCameraScreenState();
}

class _StandaloneCameraScreenState extends State<_StandaloneCameraScreen> {
  static const _toleranceDegrees = 8.0;
  static const _gotSteadyHintDegrees = 14.0;
  static const _requiredStableDuration = Duration(milliseconds: 600);

  camera.CameraController? _controller;
  List<camera.CameraDescription> _cameras = [];
  StreamSubscription<AccelerometerEvent>? _subscription;
  AccelerometerEvent? _event;
  DateTime? _alignedSince;
  Object? _cameraError;
  Object? _sensorError;
  camera.FlashMode _flashMode = camera.FlashMode.off;
  bool _cameraReady = false;
  bool _captureEnabled = false;
  bool _isCapturing = false;

  _CameraAlignmentMode get _mode => widget.module == _InspectionModule.fet
      ? _CameraAlignmentMode.overhead
      : _CameraAlignmentMode.portrait;

  bool get _usesStabilityGate => widget.module == _InspectionModule.fet;

  String get _moduleCode =>
      widget.module == _InspectionModule.fet ? 'FET' : 'GOT';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _subscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      _handleAccelerometer,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _sensorError = error;
          _captureEnabled = !_usesStabilityGate && _cameraReady;
          _alignedSince = null;
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera([
    camera.CameraDescription? preferredCamera,
  ]) async {
    final previousController = _controller;
    setState(() {
      _cameraReady = false;
      _cameraError = null;
      _controller = null;
    });
    await previousController?.dispose();

    try {
      final cameras = await camera.availableCameras();
      if (cameras.isEmpty) {
        throw StateError('Kamera tidak ditemukan di perangkat ini.');
      }
      final selectedCamera = preferredCamera ??
          cameras.firstWhere(
            (cameraDescription) =>
                cameraDescription.lensDirection ==
                camera.CameraLensDirection.back,
            orElse: () => cameras.first,
          );
      final controller = camera.CameraController(
        selectedCamera,
        camera.ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: camera.ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await _configureAutoFocus(controller);
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {
        _flashMode = camera.FlashMode.off;
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameras = cameras;
        _controller = controller;
        _cameraReady = true;
        _captureEnabled = !_usesStabilityGate;
        _alignedSince = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError = error;
        _cameraReady = false;
        _captureEnabled = false;
      });
    }
  }

  Future<void> _configureAutoFocus(camera.CameraController controller) async {
    try {
      await controller.setFocusMode(camera.FocusMode.auto);
    } catch (_) {
      // Some devices expose a fixed-focus camera; capture can still continue.
    }
    try {
      await controller.setExposureMode(camera.ExposureMode.auto);
    } catch (_) {}
    try {
      await controller.setFocusPoint(const Offset(.5, .5));
    } catch (_) {}
    try {
      await controller.setExposurePoint(const Offset(.5, .5));
    } catch (_) {}
  }

  Future<void> _refreshFocusBeforeCapture(
    camera.CameraController controller,
  ) async {
    if (widget.module != _InspectionModule.got) return;
    await _configureAutoFocus(controller);
  }

  void _handleAccelerometer(AccelerometerEvent event) {
    final reading = _CameraLevelReading.fromEvent(
      event,
      toleranceDegrees: _toleranceDegrees,
      mode: _mode,
    );
    final now = DateTime.now();
    var nextCaptureEnabled = !_usesStabilityGate && _cameraReady;

    if (_usesStabilityGate && reading.isAligned) {
      _alignedSince ??= now;
      nextCaptureEnabled =
          now.difference(_alignedSince!) >= _requiredStableDuration;
    } else if (_usesStabilityGate) {
      _alignedSince = null;
    }

    final becameEnabled = nextCaptureEnabled && !_captureEnabled;
    if (!mounted) return;
    setState(() {
      _event = event;
      _sensorError = null;
      _captureEnabled = nextCaptureEnabled;
    });
    if (becameEnabled) HapticFeedback.mediumImpact();
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (!_captureEnabled ||
        !_cameraReady ||
        _isCapturing ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    setState(() => _isCapturing = true);
    try {
      await _refreshFocusBeforeCapture(controller);
      final image = await controller.takePicture();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(image);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal capture foto: $error')),
      );
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final nextMode = _flashMode == camera.FlashMode.off
        ? camera.FlashMode.torch
        : camera.FlashMode.off;
    try {
      await controller.setFlashMode(nextMode);
      if (!mounted) return;
      setState(() => _flashMode = nextMode);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flash tidak tersedia di kamera ini.')),
      );
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _controller == null) return;
    final currentIndex = _cameras.indexWhere(
      (description) => description.name == _controller!.description.name,
    );
    final nextIndex =
        currentIndex < 0 ? 0 : (currentIndex + 1) % _cameras.length;
    await _initializeCamera(_cameras[nextIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final reading = _event == null
        ? null
        : _CameraLevelReading.fromEvent(
            _event!,
            toleranceDegrees: _toleranceDegrees,
            mode: _mode,
          );
    final hasError = _usesStabilityGate && _sensorError != null;
    final cameraHasError = _cameraError != null;
    final gotSteady = reading == null ||
        reading.angleDegrees <= _gotSteadyHintDegrees ||
        _sensorError != null;
    final statusColor = hasError
        ? AdvantaColors.error
        : !_usesStabilityGate
            ? gotSteady
                ? AdvantaColors.success
                : AdvantaColors.warning
            : _captureEnabled
                ? AdvantaColors.success
                : reading?.isAligned == true
                    ? AdvantaColors.warning
                    : _gotFetMutedColor(context);
    final statusText = hasError
        ? 'Sensor kemiringan tidak tersedia'
        : !_usesStabilityGate
            ? !_cameraReady
                ? 'Menyiapkan autofocus...'
                : _sensorError != null
                    ? 'Autofocus aktif - sensor stabilitas tidak tersedia'
                    : reading == null
                        ? 'Autofocus aktif - membaca stabilitas tangan'
                        : gotSteady
                            ? 'Autofocus aktif - tangan stabil'
                            : 'Autofocus aktif - tangan agak goyang'
            : reading == null
                ? 'Membaca sensor kemiringan...'
                : _captureEnabled
                    ? 'Posisi siap capture'
                    : reading.isAligned
                        ? 'Tahan posisi sampai stabil'
                        : _mode == _CameraAlignmentMode.overhead
                            ? 'Datar/tegak luruskan kamera ke objek'
                            : 'Tegakkan HP portrait dan luruskan kamera';
    final guidanceText = !_usesStabilityGate
        ? 'Capture tidak dikunci sensor. Fokus otomatis di tengah frame dan stabilitas hanya menjadi panduan.'
        : 'Ambil foto aktif saat HP datar di atas objek dan stabil.';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildCameraPreview()),
          Positioned.fill(
            child: _StandaloneCameraTemplate(
              module: widget.module,
              ready: _captureEnabled,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _CameraOverlayButton(
                    tooltip: 'Tutup kamera',
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kamera $_moduleCode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdvantaText.bodyBold.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdvantaText.caption.copyWith(
                            color: Colors.white.withAlpha(210),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CameraOverlayButton(
                    tooltip: _flashMode == camera.FlashMode.off
                        ? 'Nyalakan flash'
                        : 'Matikan flash',
                    icon: _flashMode == camera.FlashMode.off
                        ? Icons.flash_off_rounded
                        : Icons.flash_on_rounded,
                    onPressed: _cameraReady ? _toggleFlash : null,
                  ),
                  if (_cameras.length > 1) ...[
                    const SizedBox(width: 8),
                    _CameraOverlayButton(
                      tooltip: 'Ganti kamera',
                      icon: Icons.cameraswitch_rounded,
                      onPressed: _cameraReady ? _switchCamera : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (cameraHasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _CameraMessagePanel(
                  icon: Icons.no_photography_rounded,
                  title: 'Kamera belum bisa dibuka',
                  message: _friendlyCameraError(_cameraError!),
                  actionLabel: 'Coba Lagi',
                  onAction: () => _initializeCamera(),
                ),
              ),
            )
          else if (!_cameraReady)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    'Membuka kamera...',
                    style: AdvantaText.bodyBold.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_usesStabilityGate)
                      _CameraBalancePanel(
                        reading: reading,
                        ready: _captureEnabled,
                        statusColor: statusColor,
                        statusText: reading == null
                            ? statusText
                            : '$statusText | ${reading.angleDegrees.toStringAsFixed(1)} deg',
                        guidanceText: guidanceText,
                      )
                    else
                      _GotCameraAssistPanel(
                        reading: reading,
                        ready: _cameraReady,
                        steady: gotSteady,
                        statusColor: statusColor,
                        statusText: statusText,
                        guidanceText: guidanceText,
                      ),
                    const SizedBox(height: 14),
                    _StandaloneCaptureButton(
                      enabled: _cameraReady && _captureEnabled && !_isCapturing,
                      capturing: _isCapturing,
                      onPressed: _capturePhoto,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AdvantaText.caption.copyWith(
                        color: Colors.white.withAlpha(210),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _controller;
    if (!_cameraReady ||
        controller == null ||
        !controller.value.isInitialized) {
      return Container(color: Colors.black);
    }

    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return Center(child: camera.CameraPreview(controller));
    }

    final orientation = MediaQuery.orientationOf(context);
    final previewWidth = orientation == Orientation.portrait
        ? previewSize.height
        : previewSize.width;
    final previewHeight = orientation == Orientation.portrait
        ? previewSize.width
        : previewSize.height;

    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: previewWidth,
          height: previewHeight,
          child: camera.CameraPreview(controller),
        ),
      ),
    );
  }

  String _friendlyCameraError(Object error) {
    final message = error.toString();
    if (message.contains('CameraAccessDenied')) {
      return 'Izin kamera belum diberikan untuk aplikasi ini.';
    }
    if (message.contains('Kamera tidak ditemukan')) return message;
    return 'Pastikan izin kamera aktif, lalu coba buka kamera lagi.';
  }
}

class _StandaloneCameraTemplate extends StatelessWidget {
  final _InspectionModule module;
  final bool ready;

  const _StandaloneCameraTemplate({
    required this.module,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 94, 20, 178),
        child: CustomPaint(
          painter: _StandaloneCameraTemplatePainter(
            showCenter: module == _InspectionModule.got,
            showGrid: module == _InspectionModule.fet,
            ready: ready,
          ),
        ),
      ),
    );
  }
}

class _StandaloneCameraTemplatePainter extends CustomPainter {
  final bool showCenter;
  final bool showGrid;
  final bool ready;

  const _StandaloneCameraTemplatePainter({
    required this.showCenter,
    required this.showGrid,
    required this.ready,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final frameColor =
        ready ? AdvantaColors.success : Colors.white.withAlpha(230);
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final linePaint = Paint()
      ..color = frameColor
      ..strokeWidth = ready ? 4 : 3
      ..strokeCap = StrokeCap.round;
    final dimPaint = Paint()
      ..color = Colors.black.withAlpha(72)
      ..style = PaintingStyle.fill;
    final cutout = Path()..addRRect(RRect.fromRectXY(rect, 18, 18));
    final overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(cutout, Offset.zero);
    canvas.drawPath(overlay, dimPaint);

    const corner = 46.0;
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(corner, 0), linePaint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(0, corner), linePaint);
    canvas.drawLine(
        rect.topRight, rect.topRight - const Offset(corner, 0), linePaint);
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(0, corner), linePaint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + const Offset(corner, 0), linePaint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft - const Offset(0, corner), linePaint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight - const Offset(corner, 0), linePaint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight - const Offset(0, corner), linePaint);

    if (showCenter) {
      final center = rect.center;
      final centerPaint = Paint()
        ..color = frameColor.withAlpha(210)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(center, 28, centerPaint..style = PaintingStyle.stroke);
      centerPaint.style = PaintingStyle.fill;
      canvas.drawLine(center - const Offset(24, 0),
          center + const Offset(24, 0), centerPaint);
      canvas.drawLine(center - const Offset(0, 24),
          center + const Offset(0, 24), centerPaint);
    }

    if (showGrid) {
      final gridPaint = Paint()
        ..color = frameColor.withAlpha(130)
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
  bool shouldRepaint(covariant _StandaloneCameraTemplatePainter oldDelegate) {
    return showCenter != oldDelegate.showCenter ||
        showGrid != oldDelegate.showGrid ||
        ready != oldDelegate.ready;
  }
}

class _GotCameraAssistPanel extends StatelessWidget {
  final _CameraLevelReading? reading;
  final bool ready;
  final bool steady;
  final Color statusColor;
  final String statusText;
  final String guidanceText;

  const _GotCameraAssistPanel({
    required this.reading,
    required this.ready,
    required this.steady,
    required this.statusColor,
    required this.statusText,
    required this.guidanceText,
  });

  @override
  Widget build(BuildContext context) {
    final angleText = reading == null
        ? 'Sensor'
        : '${reading!.angleDegrees.toStringAsFixed(1)} deg';
    final pillText = ready
        ? steady
            ? 'Stabil'
            : 'Goyang'
        : 'Memuat';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(172),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withAlpha(150)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withAlpha(42),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: statusColor.withAlpha(130)),
            ),
            child: Icon(Icons.center_focus_strong_rounded, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.bodyBold.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  guidanceText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.caption.copyWith(
                    color: Colors.white.withAlpha(210),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _CameraStatusChip(label: pillText, color: statusColor),
              const SizedBox(height: 6),
              Text(
                angleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AdvantaText.caption.copyWith(
                  color: Colors.white.withAlpha(190),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CameraStatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _CameraStatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AdvantaText.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CameraBalancePanel extends StatelessWidget {
  final _CameraLevelReading? reading;
  final bool ready;
  final Color statusColor;
  final String statusText;
  final String guidanceText;

  const _CameraBalancePanel({
    required this.reading,
    required this.ready,
    required this.statusColor,
    required this.statusText,
    required this.guidanceText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(172),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withAlpha(150)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: _CameraLevelTarget(
              reading: reading,
              ready: ready,
              statusColor: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.bodyBold.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  guidanceText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AdvantaText.caption.copyWith(
                    color: Colors.white.withAlpha(210),
                    fontWeight: FontWeight.w800,
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

class _StandaloneCaptureButton extends StatelessWidget {
  final bool enabled;
  final bool capturing;
  final VoidCallback onPressed;

  const _StandaloneCaptureButton({
    required this.enabled,
    required this.capturing,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: IconButton(
        tooltip: 'Ambil foto',
        onPressed: enabled ? onPressed : null,
        style: IconButton.styleFrom(
          backgroundColor:
              enabled ? AdvantaColors.success : Colors.white.withAlpha(42),
          disabledBackgroundColor: Colors.white.withAlpha(42),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withAlpha(130),
          side: BorderSide(
            color: enabled ? Colors.white : Colors.white.withAlpha(70),
            width: 3,
          ),
        ),
        icon: capturing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.camera_alt_rounded, size: 32),
      ),
    );
  }
}

class _CameraOverlayButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _CameraOverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withAlpha(150),
        disabledBackgroundColor: Colors.black.withAlpha(90),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withAlpha(115),
        side: BorderSide(color: Colors.white.withAlpha(58)),
      ),
      icon: Icon(icon),
    );
  }
}

class _CameraMessagePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _CameraMessagePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(190),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(50)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AdvantaText.heading3.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AdvantaText.body2.copyWith(
              color: Colors.white.withAlpha(220),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _CameraLevelReading {
  final double angleDegrees;
  final double xOffset;
  final double yOffset;
  final bool isAligned;

  const _CameraLevelReading({
    required this.angleDegrees,
    required this.xOffset,
    required this.yOffset,
    required this.isAligned,
  });

  factory _CameraLevelReading.fromEvent(
    AccelerometerEvent event, {
    required double toleranceDegrees,
    required _CameraAlignmentMode mode,
  }) {
    final (targetAxis, horizontalAxis, verticalAxis) = switch (mode) {
      _CameraAlignmentMode.overhead => (
          event.z.abs().clamp(0.01, double.infinity).toDouble(),
          event.x,
          event.y,
        ),
      _CameraAlignmentMode.portrait => (
          event.y.abs().clamp(0.01, double.infinity).toDouble(),
          event.x,
          event.z,
        ),
    };
    final lateral = math.sqrt(
      horizontalAxis * horizontalAxis + verticalAxis * verticalAxis,
    );
    final angleRadians = math.atan2(lateral, targetAxis);
    final angleDegrees = angleRadians * 180 / math.pi;
    final toleranceRadians = toleranceDegrees * math.pi / 180;
    final toleranceAcceleration = math.sin(toleranceRadians) * 9.80665;

    return _CameraLevelReading(
      angleDegrees: angleDegrees,
      xOffset: (horizontalAxis / toleranceAcceleration)
          .clamp(-1.25, 1.25)
          .toDouble(),
      yOffset:
          (verticalAxis / toleranceAcceleration).clamp(-1.25, 1.25).toDouble(),
      isAligned: angleDegrees <= toleranceDegrees,
    );
  }
}

class _CameraLevelTarget extends StatelessWidget {
  final _CameraLevelReading? reading;
  final bool ready;
  final Color statusColor;

  const _CameraLevelTarget({
    required this.reading,
    required this.ready,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 220.0);
        final outerSize = size * 0.82;
        final center = size / 2;
        final radius = outerSize / 2;
        final dotSize = ready ? 30.0 : 24.0;
        final x = (reading?.xOffset ?? 0) * radius;
        final y = (reading?.yOffset ?? 0) * radius;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: outerSize,
                height: outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withAlpha(isDark ? 22 : 12),
                  border: Border.all(
                    color: statusColor.withAlpha(120),
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: outerSize * 0.48,
                height: outerSize * 0.48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor.withAlpha(100),
                    width: 1.5,
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _gotFetMutedColor(context),
                  shape: BoxShape.circle,
                ),
              ),
              Positioned(
                left: center + x - dotSize / 2,
                top: center + y - dotSize / 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withAlpha(80),
                        blurRadius: ready ? 18 : 10,
                        spreadRadius: ready ? 3 : 1,
                      ),
                    ],
                  ),
                  child: ready
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
