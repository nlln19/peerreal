part of '../ditto_service.dart';

mixin _DittoDailyWindowMixin on _DittoServiceBase {
  /// Generate a daily window id based on the local date and the configured reminder time.
  ///
  /// If "now" is before today's reminder time, the window date is considered **yesterday**
  /// (so late posts still belong to the previous round).
  String _generateDailyWindowIdAt(DateTime now, int hour, int minute) {
    final todayStart = DateTime(now.year, now.month, now.day, hour, minute);
    final windowDate = now.isBefore(todayStart)
        ? todayStart.subtract(const Duration(days: 1))
        : todayStart;

    final windowId =
        '${windowDate.year}-${windowDate.month.toString().padLeft(2, '0')}-${windowDate.day.toString().padLeft(2, '0')}';

    logger.i(
      'Generated window ID: $windowId (start: ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}, now: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')})',
    );

    return windowId;
  }

  Future<String> getCurrentDailyWindowId() async {
    final now = DateTime.now();

    // Keep window id aligned with the locally scheduled reminder time (defaults to 10:00).
    final scheduled = await NotificationService.instance
        .getScheduledNotificationTime();
    final hour = scheduled?.hour ?? 10;
    final minute = scheduled?.minute ?? 0;

    final newWindowId = _generateDailyWindowIdAt(now, hour, minute);

    if (_currentDailyWindowId != newWindowId) {
      logger.i('Window changed: $_currentDailyWindowId → $newWindowId');
      _currentDailyWindowId = newWindowId;
    }

    return _currentDailyWindowId;
  }

  Future<void> checkAndUpdateDailyWindow() async {
    final now = DateTime.now();

    final scheduled = await NotificationService.instance
        .getScheduledNotificationTime();
    final hour = scheduled?.hour ?? 10;
    final minute = scheduled?.minute ?? 0;

    final newWindowId = _generateDailyWindowIdAt(now, hour, minute);

    if (_currentDailyWindowId != newWindowId) {
      _currentDailyWindowId = newWindowId;
      logger.i('New daily window: $newWindowId');
    } else {
      logger.i('Still in same window: $_currentDailyWindowId');
    }
  }
}
