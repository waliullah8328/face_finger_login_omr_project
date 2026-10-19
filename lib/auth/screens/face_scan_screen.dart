import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../theme.dart';
import '../face_embedder.dart';
import '../face_frame.dart';
import '../widgets/auth_widgets.dart';

/// What the caller made of the captured face (registered, recognised, ...).
class FaceScanOutcome {
  final bool success;
  final String title;
  final String message;

  const FaceScanOutcome.success(this.title, [this.message = ''])
      : success = true;
  const FaceScanOutcome.failure(this.title, this.message) : success = false;
}

enum _Phase { starting, position, blink, capture, processing, success, failed }

/// Live face scan with a liveness check: the face must be centred and
/// straight, then blink (a printed photo cannot), then a few frames are
/// turned into embeddings and handed to [onCaptured].
///
/// Pops with `true` once [onCaptured] reports success.
class FaceScanScreen extends StatefulWidget {
  final String title;

  /// How many embeddings to collect (more at sign up, for a sturdier record).
  final int samples;

  final Future<FaceScanOutcome> Function(List<List<double>> samples)
      onCaptured;

  const FaceScanScreen({
    super.key,
    required this.title,
    required this.onCaptured,
    this.samples = 3,
  });

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Consecutive well-placed frames needed before asking for a blink.
  static const _steadyNeeded = 4;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      minFaceSize: 0.2,
    ),
  );
  FaceEmbedder? _embedder;
  CameraController? _camera;

  _Phase _phase = _Phase.starting;
  String _hint = 'ক্যামেরা চালু হচ্ছে…';
  String? _failure;
  bool _cameraError = false;

  bool _busy = false;
  int _steady = 0;
  bool _eyesOpenSeen = false;
  bool _eyesClosedSeen = false;
  final List<List<double>> _samples = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spin.dispose();
    _stopCamera();
    unawaited(_detector.close().catchError((_) {}));
    _embedder?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera is a shared resource: release it in the background.
    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        _phase.index < _Phase.processing.index) {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _cameraError = false;
      _failure = null;
      _phase = _Phase.starting;
      _hint = 'ক্যামেরা চালু হচ্ছে…';
    });
    try {
      _embedder ??= await FaceEmbedder.load();
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', null);
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: FaceFrame.imageFormatGroup,
      );
      await camera.initialize();
      if (!mounted) {
        camera.dispose();
        return;
      }
      _camera = camera;
      _resetScan();
      await camera.startImageStream(_onFrame);
    } on CameraException catch (e) {
      _showCameraError(e.code.contains('Denied')
          ? 'ক্যামেরার অনুমতি দিন — ফোনের সেটিংস থেকে অনুমতি চালু করে আবার চেষ্টা করুন।'
          : 'ক্যামেরা চালু করা যায়নি।');
    } catch (_) {
      _showCameraError('ফেস স্ক্যানার চালু করা যায়নি।');
    }
  }

  void _showCameraError(String message) {
    if (!mounted) return;
    setState(() {
      _cameraError = true;
      _phase = _Phase.failed;
      _failure = message;
      _hint = 'ক্যামেরা চালু হয়নি';
    });
  }

  void _stopCamera() {
    final camera = _camera;
    _camera = null;
    if (camera == null) return;
    // Disposing also stops the image stream.
    camera.dispose();
    if (mounted) setState(() {});
  }

  void _resetScan() {
    setState(() {
      _phase = _Phase.position;
      _hint = 'মুখটি বৃত্তের ভেতরে রাখুন';
      _failure = null;
      _steady = 0;
      _eyesOpenSeen = false;
      _eyesClosedSeen = false;
      _samples.clear();
    });
  }

  Future<void> _retry() async {
    if (_camera == null) return _start();
    _resetScan();
    if (!_camera!.value.isStreamingImages) {
      await _camera!.startImageStream(_onFrame);
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    final camera = _camera;
    if (_busy || camera == null || _phase.index >= _Phase.processing.index) {
      return;
    }
    _busy = true;
    try {
      final frame = FaceFrame.fromCamera(image, camera);
      if (frame == null) return;
      final faces = await _detector.processImage(frame.toInputImage());
      if (mounted) await _handle(frame, faces);
    } catch (_) {
      // A dropped frame is harmless; the next one will be analysed.
    } finally {
      _busy = false;
    }
  }

  Future<void> _handle(FaceFrame frame, List<Face> faces) async {
    if (_phase.index >= _Phase.processing.index) return;
    final String? problem = faces.isEmpty
        ? 'ক্যামেরার সামনে মুখ রাখুন'
        : faces.length > 1
            ? 'শুধু একজন ক্যামেরার সামনে থাকুন'
            : _placementProblem(faces.first, frame.uprightSize);
    if (problem != null) {
      setState(() {
        _steady = 0;
        _hint = problem;
      });
      return;
    }

    final face = faces.first;
    final eyes = math.min(face.leftEyeOpenProbability ?? 1,
        face.rightEyeOpenProbability ?? 1);

    switch (_phase) {
      case _Phase.position:
        _steady++;
        if (_steady >= _steadyNeeded) {
          HapticFeedback.selectionClick();
          setState(() {
            _phase = _Phase.blink;
            _hint = 'এবার একবার চোখের পলক ফেলুন';
          });
        } else {
          setState(() => _hint = 'ঠিক আছে, এভাবেই থাকুন…');
        }
      case _Phase.blink:
        if (eyes > 0.7) {
          if (_eyesClosedSeen) {
            HapticFeedback.selectionClick();
            setState(() {
              _phase = _Phase.capture;
              _hint = 'স্ক্যান হচ্ছে, নড়বেন না…';
            });
          } else if (!_eyesOpenSeen) {
            setState(() => _eyesOpenSeen = true);
          }
        } else if (eyes < 0.25 && _eyesOpenSeen && !_eyesClosedSeen) {
          setState(() => _eyesClosedSeen = true);
        }
      case _Phase.capture:
        if (eyes < 0.6) return;
        _samples.add(_embedder!.embed(frame, face.boundingBox));
        setState(() {});
        if (_samples.length >= widget.samples) await _finish();
      default:
        break;
    }
  }

  /// Why the face is not usable yet, or `null` when it is well placed.
  String? _placementProblem(Face face, Size image) {
    final box = face.boundingBox;
    if (box.width < image.width * 0.3) return 'আরেকটু কাছে আসুন';
    if (box.width > image.width * 0.85) return 'একটু দূরে সরুন';
    final dx = (box.center.dx - image.width / 2).abs() / image.width;
    final dy = (box.center.dy - image.height / 2).abs() / image.height;
    if (dx > 0.18 ||
        dy > 0.18 ||
        box.left < 0 ||
        box.top < 0 ||
        box.right > image.width ||
        box.bottom > image.height) {
      return 'মুখটি বৃত্তের মাঝখানে আনুন';
    }
    if ((face.headEulerAngleY ?? 0).abs() > 12 ||
        (face.headEulerAngleZ ?? 0).abs() > 10 ||
        (face.headEulerAngleX ?? 0).abs() > 15) {
      return 'মাথা সোজা রেখে ক্যামেরার দিকে তাকান';
    }
    return null;
  }

  Future<void> _finish() async {
    setState(() {
      _phase = _Phase.processing;
      _hint = 'যাচাই করা হচ্ছে…';
    });
    try {
      await _camera?.stopImageStream();
    } catch (_) {}
    final outcome = await widget.onCaptured(List.of(_samples));
    if (!mounted) return;
    if (outcome.success) {
      HapticFeedback.mediumImpact();
      setState(() {
        _phase = _Phase.success;
        _hint = outcome.title;
        _failure = outcome.message.isEmpty ? null : outcome.message;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.pop(context, true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _phase = _Phase.failed;
        _hint = outcome.title;
        _failure = outcome.message;
      });
    }
  }

  double get _progress => switch (_phase) {
        _Phase.starting => 0,
        _Phase.position => 0.3 * _steady / _steadyNeeded,
        _Phase.blink =>
          0.3 + (_eyesOpenSeen ? 0.1 : 0) + (_eyesClosedSeen ? 0.2 : 0),
        _Phase.capture => 0.6 + 0.4 * _samples.length / widget.samples,
        _Phase.processing || _Phase.success => 1,
        _Phase.failed => 1,
      };

  int get _stepIndex => switch (_phase) {
        _Phase.starting || _Phase.position => 0,
        _Phase.blink => 1,
        _Phase.capture || _Phase.processing => 2,
        _Phase.success => 3,
        _Phase.failed => -1,
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewport =
        math.min(math.min(size.width * 0.72, size.height * 0.34), 300.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF12050E),
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 1.1,
              colors: [Color(0xFF4A0B3C), Color(0xFF12050E)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'ফিরে যান',
                        onPressed: () => Navigator.pop(context, false),
                      ),
                      const Spacer(),
                      const _SecureBadge(),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ভালো আলোতে, ফোন চোখ বরাবর ধরুন',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _FaceViewport(
                      size: viewport,
                      camera: _camera,
                      phase: _phase,
                      progress: _progress,
                      spin: _spin,
                    ),
                  ),
                ),
                _HintCard(phase: _phase, hint: _hint, detail: _failure),
                const SizedBox(height: 18),
                _Steps(current: _stepIndex),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _phase == _Phase.failed
                        ? FilledButton.icon(
                            key: const ValueKey('retry'),
                            onPressed: _cameraError ? _start : _retry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('আবার চেষ্টা করুন'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primaryDark,
                            ),
                          )
                        : Row(
                            key: const ValueKey('note'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline_rounded,
                                  size: 15,
                                  color: Colors.white.withValues(alpha: 0.5)),
                              const SizedBox(width: 6),
                              Text(
                                'ফেস ডেটা শুধু এই ফোনেই সংরক্ষিত থাকে',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecureBadge extends StatelessWidget {
  const _SecureBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_rounded, size: 15, color: AppColors.success),
          SizedBox(width: 6),
          Text('সুরক্ষিত স্ক্যান',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// The round camera window with the Face ID–style tick ring, a sweeping scan
/// line, and success/failure overlays.
class _FaceViewport extends StatelessWidget {
  final double size;
  final CameraController? camera;
  final _Phase phase;
  final double progress;
  final Animation<double> spin;

  const _FaceViewport({
    required this.size,
    required this.camera,
    required this.phase,
    required this.progress,
    required this.spin,
  });

  @override
  Widget build(BuildContext context) {
    final ring = size + 56;
    final scanning = phase == _Phase.position ||
        phase == _Phase.blink ||
        phase == _Phase.capture;
    final camera = this.camera;
    final ready = camera != null && camera.value.isInitialized;

    return SizedBox.square(
      dimension: ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft glow behind the window.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: switch (phase) {
                    _Phase.success => AppColors.success,
                    _Phase.failed => AppColors.danger,
                    _ => AppColors.primary,
                  }
                      .withValues(alpha: 0.45),
                  blurRadius: 60,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => AnimatedBuilder(
              animation: spin,
              builder: (context, _) => CustomPaint(
                size: Size.square(ring),
                painter: _TickRingPainter(
                  progress: value,
                  spin: spin.value,
                  searching: phase == _Phase.starting ||
                      (phase == _Phase.position && progress == 0),
                  tint: switch (phase) {
                    _Phase.success => AppColors.success,
                    _Phase.failed => AppColors.danger,
                    _ => null,
                  },
                ),
              ),
            ),
          ),
          ClipOval(
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (ready)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: size,
                        height: size * camera.value.aspectRatio,
                        child: CameraPreview(camera),
                      ),
                    )
                  else
                    Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: Icon(Icons.face_rounded,
                          size: size * 0.45,
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                  if (scanning && ready) _ScanLine(spin: spin, size: size),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: switch (phase) {
                      _Phase.processing => _Overlay(
                          key: const ValueKey('processing'),
                          color: AppColors.primaryDark,
                          child: const SizedBox.square(
                            dimension: 46,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3.5),
                          ),
                        ),
                      _Phase.success => const _Overlay(
                          key: ValueKey('success'),
                          color: AppColors.success,
                          child: _PopIcon(Icons.check_rounded),
                        ),
                      _Phase.failed => const _Overlay(
                          key: ValueKey('failed'),
                          color: AppColors.danger,
                          child: _PopIcon(Icons.close_rounded),
                        ),
                      _ => const SizedBox.shrink(key: ValueKey('none')),
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  final Color color;
  final Widget child;

  const _Overlay({super.key, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Icon that pops in with a little overshoot.
class _PopIcon extends StatelessWidget {
  final IconData icon;

  const _PopIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: Container(
        width: 84,
        height: 84,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 52, color: AppColors.text),
      ),
    );
  }
}

/// A glowing band sweeping up and down over the camera.
class _ScanLine extends StatelessWidget {
  final Animation<double> spin;
  final double size;

  const _ScanLine({required this.spin, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: spin,
      builder: (context, _) {
        // 0→1→0 over one spin turn, eased at the ends.
        final t = 0.5 - 0.5 * math.cos(spin.value * 2 * math.pi);
        return Align(
          alignment: Alignment(0, -1 + 2 * t),
          child: Container(
            height: size * 0.22,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.brandGreen.withValues(alpha: 0),
                  AppColors.brandGreen.withValues(alpha: 0.28),
                  AppColors.brandGreen.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ring of ticks around the camera that light up with progress, magenta to
/// green; a comet sweeps around while searching for a face.
class _TickRingPainter extends CustomPainter {
  final double progress;
  final double spin;
  final bool searching;
  final Color? tint;

  _TickRingPainter({
    required this.progress,
    required this.spin,
    required this.searching,
    required this.tint,
  });

  static const _ticks = 72;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2 - 4;
    final inner = outer - 14;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    final band = outer - inner;
    for (var i = 0; i < _ticks; i++) {
      final f = i / _ticks;
      final angle = -math.pi / 2 + f * 2 * math.pi;
      // Lit ticks are full length; idle ones shorter.
      var length = 0.6;
      if (tint != null) {
        paint.color = tint!;
        length = 1;
      } else if (f < progress) {
        paint.color = Color.lerp(AppColors.primary, AppColors.brandGreen, f)!;
        length = 1;
      } else if (searching) {
        // Comet: ticks just behind the spinning head glow and grow.
        final behind = (spin - f) % 1;
        final glow = behind < 0.25 ? 1 - behind / 0.25 : 0.0;
        paint.color = Colors.white.withValues(alpha: 0.12 + 0.6 * glow);
        length = 0.6 + 0.4 * glow;
      } else {
        paint.color = Colors.white.withValues(alpha: 0.14);
      }
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
          center + dir * (outer - band * length), center + dir * outer, paint);
    }
  }

  @override
  bool shouldRepaint(_TickRingPainter old) =>
      old.progress != progress ||
      old.spin != spin ||
      old.searching != searching ||
      old.tint != tint;
}

/// The latest hint, big, with a status icon; plus an optional detail line.
class _HintCard extends StatelessWidget {
  final _Phase phase;
  final String hint;
  final String? detail;

  const _HintCard({required this.phase, required this.hint, this.detail});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (phase) {
      _Phase.success => (Icons.check_circle_rounded, AppColors.success),
      _Phase.failed => (Icons.error_rounded, AppColors.danger),
      _Phase.blink => (Icons.remove_red_eye_rounded, Colors.white),
      _Phase.capture ||
      _Phase.processing =>
        (Icons.center_focus_strong_rounded, AppColors.brandGreen),
      _ => (Icons.face_retouching_natural_rounded, Colors.white),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                .animate(animation),
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey('$phase$hint$detail'),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The three scan steps; done ones turn green, the current one glows.
class _Steps extends StatelessWidget {
  /// Index of the current step; 3 when all are done, -1 on failure.
  final int current;

  const _Steps({required this.current});

  static const _steps = [
    (Icons.face_rounded, 'মুখ সোজা'),
    (Icons.remove_red_eye_rounded, 'পলক'),
    (Icons.document_scanner_rounded, 'স্ক্যান'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 18,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: i <= current
                    ? AppColors.success
                    : Colors.white.withValues(alpha: 0.2),
              ),
            Flexible(child: _StepPill(
              icon: _steps[i].$1,
              label: _steps[i].$2,
              done: i < current,
              active: i == current,
            )),
          ],
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;
  final bool active;

  const _StepPill({
    required this.icon,
    required this.label,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: done
            ? AppColors.success.withValues(alpha: 0.18)
            : active
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: done
              ? AppColors.success
              : active
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_rounded : icon,
              size: 15,
              color: done
                  ? AppColors.success
                  : Colors.white.withValues(alpha: active ? 1 : 0.45)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: done || active ? 1 : 0.45),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
