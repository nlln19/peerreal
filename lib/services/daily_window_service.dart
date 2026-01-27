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
    if (scheduledTime == null) {
      logger.i('📅 No scheduled time found');
      return false;
    }

    final now = DateTime.now();
    logger.i('📅 Checking: now=$now, scheduled=$scheduledTime');

    // Check if the scheduled time has passed
    if (now.isAfter(scheduledTime)) {
      final prefs = await SharedPreferences.getInstance();
      final lastWindowStart = prefs.getInt('last_window_start');

      logger.i(
        '📅 Scheduled time passed! Last window start: $lastWindowStart, scheduled: ${scheduledTime.millisecondsSinceEpoch}',
      );

      // If we haven't started a new window since the scheduled time
      if (lastWindowStart == null ||
          lastWindowStart < scheduledTime.millisecondsSinceEpoch) {
        logger.i('📅 ✅ Should start new window!');
        return true;
      } else {
        logger.i('📅 ⏸️ Already started window after scheduled time');
      }
    } else {
      logger.i('📅 ⏸️ Scheduled time not yet passed');
    }

    return false;
  }

  /// Start a new daily window
  Future<void> startNewWindow() async {
    logger.i('🔄 Starting new window...');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'last_window_start',
      DateTime.now().millisecondsSinceEpoch,
    );

    // Update Ditto's window tracking (date-based, automatic)
    await DittoService.instance.checkAndUpdateDailyWindow();

    // Schedule the next notification
    await NotificationService.instance.scheduleDailyPostReminder();

    logger.i('🔄 ✅ New daily window started!');
  }

  /// Get the current window ID
  Future<String> getCurrentWindowId() async {
    return await DittoService.instance.getCurrentDailyWindowId();
  }

  /// Check and start new window if needed (call this when app opens)
  Future<void> checkAndStartNewWindowIfNeeded() async {
    logger.i('📅 Checking if new window needed...');
    if (await shouldStartNewWindow()) {
      await startNewWindow();
    } else {
      logger.i('📅 No new window needed');
    }
  }
}
