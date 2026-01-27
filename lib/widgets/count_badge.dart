import 'package:flutter/material.dart';

class CountBadge extends StatelessWidget {
  final int count;

  const CountBadge({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF05050A), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}