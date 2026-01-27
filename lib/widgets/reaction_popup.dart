import 'package:flutter/material.dart';
import 'dart:ui';

class ReactionPopup extends StatefulWidget {
  final Offset position;
  final Function(int) onReactionSelected; // 1 = thumbs up, 0 = thumbs down

  const ReactionPopup({
    super.key,
    required this.position,
    required this.onReactionSelected,
  });

  @override
  State<ReactionPopup> createState() => _ReactionPopupState();
}

class _ReactionPopupState extends State<ReactionPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  int? _hoveredReaction;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Blur background
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),

        // Reaction popup
        Positioned(
          left: widget.position.dx - 100,
          top: widget.position.dy - 80,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C28),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ReactionButton(
                    emoji: '👍',
                    reactionType: 1,
                    isHovered: _hoveredReaction == 1,
                    onTap: () {
                      widget.onReactionSelected(1);
                      Navigator.of(context).pop();
                    },
                    onHover: (hovering) {
                      setState(() {
                        _hoveredReaction = hovering ? 1 : null;
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  _ReactionButton(
                    emoji: '👎',
                    reactionType: 0,
                    isHovered: _hoveredReaction == 0,
                    onTap: () {
                      widget.onReactionSelected(0);
                      Navigator.of(context).pop();
                    },
                    onHover: (hovering) {
                      setState(() {
                        _hoveredReaction = hovering ? 0 : null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionButton extends StatefulWidget {
  final String emoji;
  final int reactionType;
  final bool isHovered;
  final VoidCallback onTap;
  final Function(bool) onHover;

  const _ReactionButton({
    required this.emoji,
    required this.reactionType,
    required this.isHovered,
    required this.onTap,
    required this.onHover,
  });

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.isHovered ? 1.3 : 1.0;

    return GestureDetector(
      onTapDown: (_) => _bounceController.forward(),
      onTapUp: (_) {
        _bounceController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _bounceController.reverse(),
      child: MouseRegion(
        onEnter: (_) => widget.onHover(true),
        onExit: (_) => widget.onHover(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Transform.scale(
            scale: scale,
            child: Center(
              child: Text(
                widget.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}