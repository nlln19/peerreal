import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

// Logger Singleton
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: true,
  ),
  level: kDebugMode ? Level.debug : Level.warning,
);