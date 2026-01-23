import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NextPostTimer extends StatefulWidget {
  const NextPostTimer({super.key});

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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Text(
            "New window in ${_formatTimeRemaining(_timeRemaining!)}",
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
