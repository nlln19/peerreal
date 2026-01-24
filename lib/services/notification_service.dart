import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
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

  Future<void> showNewPostNotification({
    required String authorName,
    required String authorId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'new_posts',
      'New Posts',
      channelDescription: 'Notifications for new PeerReal posts',
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
      authorId.hashCode, // Unique ID per author
      '📸 New moment from $authorName',
      'Tap to view their latest post',
      details,
      payload: 'post:$authorId',
    );

    logger.i('🔔 Sent notification for post by $authorName');
  }

  Future<void> showFriendRequestNotification({
    required String fromName,
    required String fromId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'friend_requests',
      'Friend Requests',
      channelDescription: 'Notifications for friend requests',
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
      fromId.hashCode,
      '👋 Friend request from $fromName',
      'Tap to accept or decline',
      details,
      payload: 'friend_request:$fromId',
    );

    logger.i('🔔 Sent friend request notification from $fromName');
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}