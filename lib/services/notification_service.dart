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

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

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

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android != null) {
      const channel = AndroidNotificationChannel(
        'daily_reminder',
        'Daily Reminder',
        description: 'Daily reminder to capture your moment',
        importance: Importance.high,
      );
      await android.createNotificationChannel(channel);

      await android.requestNotificationsPermission();
    }

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    logger.i('🔔 Notification permissions requested (handled in init)');
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

  /// Schedule a daily reminder notification at a FIXED time (same for everyone)
  /// This is called once when the app starts or when user enables notifications
  Future<void> scheduleDailyPostReminder() async {
    try {
      // Check if we already have a scheduled notification
      final prefs = await SharedPreferences.getInstance();
      final existingTimestamp = prefs.getInt('scheduled_notification_time');

      if (existingTimestamp != null) {
        final existingTime = DateTime.fromMillisecondsSinceEpoch(
          existingTimestamp,
        );
        final now = DateTime.now();

        // If the existing scheduled time is in the future, don't reschedule
        if (existingTime.isAfter(now)) {
          logger.i(
            '🔔 Already scheduled for ${existingTime.hour}:${existingTime.minute.toString().padLeft(2, '0')} - keeping it!',
          );
          return;
        }
      }

      // Cancel any existing daily reminder
      await _notifications.cancel(999);

      // FIXED TIME: Always schedule for 10:00 tomorrow
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);

      final scheduledTime = DateTime(now.year, now.month, now.day, 15, 0);

      /*final scheduledTime = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        10, // Fixed hour: 10 AM
        0, // Fixed minute: 00
      );*/

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
        'WAKEY WAKEY TIME TO PEER REAL',
        'Capture your moment now mf 🗣️🗣️🗣️',
        tzScheduledTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents:
            DateTimeComponents.time, // Repeat daily at this time
      );

      // Save the scheduled time
      await prefs.setInt(
        'scheduled_notification_time',
        scheduledTime.millisecondsSinceEpoch,
      );

      logger.i(
        '🔔 Daily reminder scheduled for ${scheduledTime.hour}:${scheduledTime.minute.toString().padLeft(2, '0')} (fixed time for all users)',
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
