import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'peer_real.dart';
import 'package:PeerReal/services/notification_service.dart';
import 'package:PeerReal/services/ditto_service.dart';
import 'package:PeerReal/services/permission_service.dart';
import 'package:PeerReal/services/daily_window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();

  // Initialize Ditto
  await DittoService.instance.init();

  // Check if we should start a new daily window
  await DailyWindowService.instance.checkAndStartNewWindowIfNeeded();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown
  ]);

  await PermissionService.requestP2PPermissions();

  runApp(const PeerReal());
}