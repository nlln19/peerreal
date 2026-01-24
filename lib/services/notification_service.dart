import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // Initialize timezone
    tz.initializeTimeZones();

    // Android initialization
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    logger.i('🔔 Notification service initialized');
  }

  Future<void> requestPermissions() async {
    // iOS permissions
    final iosPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    // Android 13+ permissions
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();

    logger.i('🔔 Notification permissions requested');
  }

  void _onNotificationTapped(NotificationResponse response) {
    logger.i('🔔 Notification tapped: ${response.payload}');
    // You can navigate to specific screens here based on payload
  }

  /// Get the scheduled notification time (or null if not scheduled)
  Future<DateTime?> getScheduledNotificationTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('scheduled_notification_time');
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Schedule a daily reminder notification at a random time (BeReal style)
  /// This is called once when the app starts or when user enables notifications
  Future<void> scheduleDailyPostReminder() async {
    try {
      // Cancel any existing daily reminder
      await _notifications.cancel(999);

      // Calculate random time for tomorrow
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final randomHour = 9 + Random().nextInt(12); // Between 9am-9pm
      final randomMinute = Random().nextInt(60);

      final scheduledTime = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        randomHour,
        randomMinute,
      );

      final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

      const androidDetails = AndroidNotificationDetails(
        'daily_reminder',
        'Daily Reminder',
        channelDescription: 'Daily reminder to capture your moment',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.zonedSchedule(
        999, // Fixed ID for daily reminder
        'WAKEY WAKEY PEER REAL RESET',
        'Capture your moment now mf 🗣️🗣️🗣️🗣️',
        tzScheduledTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time, // Repeat daily
      );

      // Save the scheduled time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'scheduled_notification_time',
        scheduledTime.millisecondsSinceEpoch,
      );

      logger.i(
        '🔔 Daily reminder scheduled for ${scheduledTime.hour}:${scheduledTime.minute.toString().padLeft(2, '0')}',
      );
    } catch (e) {
      logger.e('❌ Error scheduling daily reminder: $e');
    }
  }

  /// Cancel the daily reminder
  Future<void> cancelDailyReminder() async {
    await _notifications.cancel(999);

    // Clear the saved time
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('scheduled_notification_time');

    logger.i('🔔 Daily reminder cancelled');
  }

  /// Send an immediate test notification (for debugging only)
  Future<void> sendTestNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'test',
      'Test Notifications',
      channelDescription: 'Test notifications for debugging',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      0,
      'Test Notification',
      'This is a test notification from PeerReal',
      details,
    );

    logger.i('🔔 Test notification sent');
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    logger.i('🔔 All notifications cancelled');
  }
}