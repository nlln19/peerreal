import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'peer_real.dart';
import 'package:PeerReal/services/notification_service.dart';
import 'package:PeerReal/services/ditto_service.dart';
import 'package:PeerReal/services/permission_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();

  await DittoService.instance.init();

  await PermissionService.requestP2PPermissions();
  runApp(const PeerReal());
}
