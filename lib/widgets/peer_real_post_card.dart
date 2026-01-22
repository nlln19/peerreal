import 'dart:typed_data';

import 'package:PeerReal/screens/friend_profile_screen.dart';
import 'package:PeerReal/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:PeerReal/services/ditto_service.dart';
import '../services/logger_service.dart';

class PeerRealPostCard extends StatefulWidget {
  final Map<String, dynamic> doc;

  final bool showAuthorHeader; // Feed = true, Profil / FriendProfile = false

  const PeerRealPostCard({
    super.key,
    required this.doc,
    this.showAuthorHeader = true,
  });

  @override
  State<PeerRealPostCard> createState() => _PeerRealPostCardState();
}

class _PeerRealPostCardState extends State<PeerRealPostCard> {
  Uint8List? _imageData;
  Uint8List? _selfieData;

  late final String _authorId;
  late final bool _isMe;
  String? _authorName;

  // Track which image is currently in the main position
  bool _showMainAsLarge = true;

  @override
  void initState() {
    super.initState();
    _authorId = widget.doc['author'] as String? ?? '';
    _isMe =
        _authorId.isNotEmpty && _authorId == DittoService.instance.localPeerId;

    _loadAuthorName();
    _loadImage();
  }

  Future<void> _loadAuthorName() async {
    if (_authorId.isEmpty) return;
    try {
      final name = await DittoService.instance.getDisplayNameForPeer(_authorId);
      if (!mounted) return;
      setState(() {
        _authorName = name;
      });
    } catch (e) {
      logger.e('❌ Error loading author name: $e');
    }
  }

  Future<void> _loadImage() async {
    try {
      final main = await DittoService.instance.getAttachmentData(widget.doc);
      final selfie = await DittoService.instance.getSelfieAttachmentData(
        widget.doc,
      );

      if (!mounted) return;
      setState(() {
        _imageData = main;
        _selfieData = selfie;
      });
    } catch (e) {
      logger.e('❌ Error loading images in PeerRealPostCard: $e');
    }
  }

  void _openProfile() {
    if (_authorId.isEmpty) return;

    if (_isMe) {
      // own Profil
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
    } else {
      // Friends-Profile
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FriendProfileScreen(
            peerId: _authorId,
            initialDisplayName: _authorName,
          ),
        ),
      );
    }
  }

  void _swapImages() {
    if (_selfieData != null) {
      setState(() {
        _showMainAsLarge = !_showMainAsLarge;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdAtMs = widget.doc['createdAt'] as int?;
    final createdAt = createdAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(createdAtMs).toLocal()
        : null;

    final timeLabel = createdAt != null
        ? "${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}"
        : "";

    final displayName =
        _authorName ??
        (_isMe
            ? 'You'
            : (_authorId.isNotEmpty ? _authorId.substring(0, 8) : 'Unknown'));

    // Determine which image to show where
    final largeImage = _showMainAsLarge ? _imageData : _selfieData;
    final smallImage = _showMainAsLarge ? _selfieData : _imageData;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showAuthorHeader) ...[
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _openProfile,
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white12,
                    child: Icon(Icons.person, size: 18, color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (timeLabel.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '• $timeLabel',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    color: Colors.black26,
                    child: _imageData == null
                        ? const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              // Main/large image - make it clickable
                              GestureDetector(
                                onTap: _swapImages,
                                child: Image.memory(
                                  largeImage!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    logger.e(
                                      '❌ Main image decode error: $error',
                                    );
                                    return const Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        color: Colors.white70,
                                      ),
                                    );
                                  },
                                ),
                              ),

                              // Small image in top right corner - make it clickable
                              if (smallImage != null)
                                Positioned(
                                  right: 12,
                                  top: 12,
                                  child: GestureDetector(
                                    onTap: _swapImages,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: 90,
                                        height: 120,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Image.memory(
                                          smallImage,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                logger.e(
                                                  '❌ Selfie decode error: $error',
                                                );
                                                return const ColoredBox(
                                                  color: Colors.black54,
                                                  child: Icon(
                                                    Icons.broken_image,
                                                    color: Colors.white70,
                                                    size: 20,
                                                  ),
                                                );
                                              },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
