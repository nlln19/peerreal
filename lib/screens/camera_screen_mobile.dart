// ignore_for_file: unused_field

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';

class MobileCameraScreen extends StatefulWidget {
  const MobileCameraScreen({super.key});

  @override
  State<MobileCameraScreen> createState() => _MobileCameraScreenState();
}

class _MobileCameraScreenState extends State<MobileCameraScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  bool _initializing = true;
  String? _errorMessage;

  int _step = 1; // 1 = Main, 2 = Selfie
  Uint8List? _mainImage;

  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _currentZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    _setupCamerasAndInit();
  }

  Future<void> _setupCamerasAndInit() async {
    setState(() {
      _initializing = true;
      _errorMessage = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _errorMessage = 'Camera not found.';
          _initializing = false;
        });
        return;
      }

      await _initForStep1();
    } catch (e) {
      logger.e('Error with Camera-Setup: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Camera could not be initialized.\nError: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _initForStep1() async {
    final CameraDescription camera = _cameras.first;
    await _initController(camera);
    if (!mounted) return;
    setState(() {
      _step = 1;
      _initializing = false;
    });
  }

  Future<void> _initForStep2() async {
    CameraDescription camera;
    try {
      camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
    } catch (_) {
      camera = _cameras.first;
    }

    await _initController(camera);
    if (!mounted) return;
    setState(() {
      _step = 2;
      _initializing = false;
    });
  }

  Future<void> _initController(CameraDescription camera) async {
    _controller?.dispose();

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    final initializeFuture = controller.initialize();
    setState(() {
      _controller = controller;
      _initializeControllerFuture = initializeFuture;
    });

    await initializeFuture;
    await initializeFuture;

    // Fixiert Kamera ausrichtung
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (e) {
      logger.e('lockCaptureOrientation failed: $e');
    }

    // Zoom
    try {
      _minZoomLevel = await controller.getMinZoomLevel();
      _maxZoomLevel = await controller.getMaxZoomLevel();
      _currentZoomLevel = _minZoomLevel;
      await controller.setZoomLevel(_currentZoomLevel);
      logger.i('Zoom range: $_minZoomLevel - $_maxZoomLevel');
    } catch (e) {
      logger.e('Error reading zoom levels: $e');
    }
  }

  Future<void> _onCapturePressed() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      await _initializeControllerFuture;

      final XFile file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      logger.i('Step $_step captured ${bytes.length} bytes');

      if (!mounted) return;

      if (_step == 1) {
        setState(() {
          _mainImage = bytes;
          _initializing = true;
        });
        await _initForStep2();
      } else {
        if (_mainImage == null) {
          Navigator.pop(context, {'main': bytes, 'selfie': bytes});
        } else {
          Navigator.pop(context, {'main': _mainImage!, 'selfie': bytes});
        }
      }
    } catch (e) {
      logger.e('Error taking picture: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isStep1 = _step == 1;

    return Scaffold(
      backgroundColor: const Color(0xFF05050A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05050A),
        title: Text(
          isStep1 ? 'Capture the moment' : 'Take a selfie',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      // safes from Notch
      body: SafeArea(
        child: Column(
          children: [
            // Camera-Preview
            Expanded(
              child: FutureBuilder(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final controller = _controller!;
                  final previewSize = controller.value.previewSize;
                  if (previewSize == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      final screenHeight = constraints.maxHeight;

                      final screenRatio = screenWidth / screenHeight;
                      final previewRatio =
                          previewSize.height / previewSize.width;
                      final scale = previewRatio / screenRatio;

                      return GestureDetector(
                        onScaleStart: (details) {
                          _baseZoomLevel = _currentZoomLevel;
                        },
                        onScaleUpdate: (details) async {
                          // only zoom with two fingers
                          if (details.pointerCount < 2) return;

                          final newZoom = (_baseZoomLevel * details.scale)
                              .clamp(_minZoomLevel, _maxZoomLevel);

                          // ignore small zoom changes
                          if ((newZoom - _currentZoomLevel).abs() < 0.01) {
                            return;
                          }

                          _currentZoomLevel = newZoom;
                          try {
                            await controller.setZoomLevel(_currentZoomLevel);
                          } catch (e) {
                            logger.e('Error setting zoom level: $e');
                          }
                        },
                        child: Transform.scale(
                          scale: scale,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: previewRatio,
                              child: CameraPreview(controller),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              child: FloatingActionButton(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                onPressed: _onCapturePressed,
                child: const Icon(Icons.camera_alt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CameraPreviewPlaceholder extends StatelessWidget {
  const CameraPreviewPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
