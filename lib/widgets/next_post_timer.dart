import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NextPostTimer extends StatefulWidget {
  /// If `compact` is true, renders a small inline version suitable for an AppBar
  /// (timer icon + remaining time). Otherwise renders the pill used in the feed.
  final bool compact;

  /// Only used when `compact == false`.
  final bool showBackground;

  const NextPostTimer({
    super.key,
    this.compact = false,
    this.showBackground = true,
  });

  @override
  State<NextPostTimer> createState() => _NextPostTimerState();
}

class _NextPostTimerState extends State<NextPostTimer> {
  DateTime? _scheduledTime;
  Timer? _timer;
  Duration? _timeRemaining;

  @override
  void initState() {
    super.initState();
    _loadScheduledTime();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_scheduledTime != null) {
        final now = DateTime.now();
        if (_scheduledTime!.isAfter(now)) {
          setState(() {
            _timeRemaining = _scheduledTime!.difference(now);
          });
        } else {
          setState(() {
            _timeRemaining = null;
          });
        }
      }
    });
  }

  Future<void> _loadScheduledTime() async {
    final time = await NotificationService.instance
        .getScheduledNotificationTime();
    if (mounted) {
      setState(() {
        _scheduledTime = time;
        // Compute remaining immediately so the UI can show without waiting for
        // the first timer tick.
        final now = DateTime.now();
        _timeRemaining = (time != null && time.isAfter(now))
            ? time.difference(now)
            : null;
      });
    }
  }

  String _formatTimeRemaining(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_scheduledTime == null || _timeRemaining == null) {
      return const SizedBox.shrink();
    }

    if (widget.compact) {
      // Inline version for AppBar: icon + time only.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
          const SizedBox(width: 4),
          Text(
            _formatTimeRemaining(_timeRemaining!),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          // Gap to the title (only present when the timer is visible).
          const SizedBox(width: 8),
        ],
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Text(
          "New window in ${_formatTimeRemaining(_timeRemaining!)}",
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );

    if (!widget.showBackground) {
      return content;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: content,
    );
  }
}
