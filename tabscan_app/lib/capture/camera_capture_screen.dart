import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// What [CameraCaptureScreen] returns: the pages taken (empty when
/// cancelled), or [chooseInstead] when there's no camera and the user
/// asked for photos instead.
class CameraCaptureResult {
  const CameraCaptureResult(this.pages, {this.chooseInstead = false});

  final List<Uint8List> pages;
  final bool chooseInstead;
}

/// Scan where there's no system document scanner (the web): the device's
/// camera through the browser (`camera`, getUserMedia), with a live
/// preview and a shutter, several pages in a row, then Done. Pages are
/// kept as taken, uncropped.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key, this.cameras = availableCameras});

  /// The cameras there are; tests pass their own.
  final Future<List<CameraDescription>> Function() cameras;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _camera = 0;
  String? _error;
  bool _busy = false;
  final List<Uint8List> _pages = [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await widget.cameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found.');
        return;
      }
      // The back camera first, as for a document.
      final back = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _cameras = cameras;
      await _open(back < 0 ? 0 : back);
    } on Object catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  Future<void> _open(int index) async {
    final old = _controller;
    setState(() {
      _controller = null;
      _camera = index;
      _error = null;
    });
    await old?.dispose();
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );
    try {
      await controller.initialize();
    } on Object catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = _describe(e));
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  static String _describe(Object e) => switch (e) {
    CameraException(:final code)
        when code.contains('ermission') || code.contains('ccess') =>
      'The camera isn\'t allowed: let TabScan use it in the browser\'s '
          'site settings.',
    CameraException(:final description?) => 'The camera failed: $description',
    _ => 'The camera failed: $e',
  };

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      if (mounted) setState(() => _pages.add(bytes));
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t take the picture: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_pages.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Discard ${_pages.length} '
            '${_pages.length == 1 ? 'page' : 'pages'}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep scanning'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context, const CameraCaptureResult([]));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final count = _pages.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
          title: Text(
            count == 0 ? 'Scan' : '$count ${count == 1 ? 'page' : 'pages'}',
          ),
          actions: [
            if (_cameras.length > 1 && controller != null)
              IconButton(
                tooltip: 'Flip camera',
                icon: const Icon(Icons.cameraswitch),
                onPressed: () => _open((_camera + 1) % _cameras.length),
              ),
            TextButton(
              onPressed: count == 0
                  ? null
                  : () => Navigator.pop(context, CameraCaptureResult(_pages)),
              child: const Text('Done'),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: switch ((_error, controller)) {
                  (final error?, _) => _NoCamera(
                    message: error,
                    onChoose: () => Navigator.pop(
                      context,
                      const CameraCaptureResult([], chooseInstead: true),
                    ),
                  ),
                  (_, final controller?) => CameraPreview(controller),
                  _ => const CircularProgressIndicator(),
                },
              ),
            ),
            if (count > 0)
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final page in _pages)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Image.memory(
                          page,
                          height: 64,
                          // A picture that won't decode still counts.
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 48,
                            height: 64,
                            child: Icon(
                              Icons.image_outlined,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _Shutter(
                  onPressed: controller == null || _busy ? null : _shoot,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round shutter button.
class _Shutter extends StatelessWidget {
  const _Shutter({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Take a picture',
    child: Tooltip(
      message: 'Take a picture',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onPressed == null ? Colors.white24 : Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Why there's no camera, and photos instead.
class _NoCamera extends StatelessWidget {
  const _NoCamera({required this.message, required this.onChoose});

  final String message;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.no_photography_outlined,
          color: Colors.white70,
          size: 56,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onChoose,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose photos instead'),
        ),
      ],
    ),
  );
}
