import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'camera_screen_mobile.dart';
import 'camera_screen_web.dart';

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web-Version (Browser)
      return const WebCameraScreen();
    } else {
      // Mobile Version (Android, iOS, macOS, Windows)
      return const MobileCameraScreen();
    }
  }
}
