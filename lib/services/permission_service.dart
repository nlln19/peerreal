import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<void> requestP2PPermissions() async {
    if (kIsWeb) return;

    if (Platform.isIOS) {
      await Permission.bluetooth.request(); // kann ohne Dialog bleiben
      return;
    }

    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.nearbyWifiDevices,
        Permission.bluetooth,
      ].request();
    }
  }
}