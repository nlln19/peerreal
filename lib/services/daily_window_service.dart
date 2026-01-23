import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'ditto_service.dart';
import 'logger_service.dart';

class DailyWindowService {
  static final DailyWindowService instance = DailyWindowService._internal();
  DailyWindowService._internal();

  /// Check if we've passed the notification time and should start a new window
  Future<bool> shouldStartNewWindow() async {
    final scheduledTime = await NotificationService.instance
        .getScheduledNotificationTime();
    if (scheduledTime == null) return false;

    final now = DateTime.now();

    // Check if the scheduled time has passed
    if (now.isAfter(scheduledTime)) {
      final prefs = await SharedPreferences.getInstance();
      final lastWindowStart = prefs.getInt('last_window_start');

      // If we haven't started a new window since the scheduled time
      if (lastWindowStart == null ||
          lastWindowStart < scheduledTime.millisecondsSinceEpoch) {
        return true;
      }
    }

    return false;
  }

  /// Start a new daily window
  Future<void> startNewWindow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'last_window_start',
      DateTime.now().millisecondsSinceEpoch,
    );

    // Update Ditto's current window
    await DittoService.instance.checkAndUpdateDailyWindow();

    // Schedule the next notification
    await NotificationService.instance.scheduleDailyPostReminder();

    logger.i('🔄 New daily window started!');
  }

  /// Get the current window ID (YYYY-MM-DD format)
  Future<String> getCurrentWindowId() async {
    return await DittoService.instance.getCurrentDailyWindowId();
  }

  /// Check and start new window if needed (call this when app opens)
  Future<void> checkAndStartNewWindowIfNeeded() async {
    if (await shouldStartNewWindow()) {
      await startNewWindow();
    }
  }
}
