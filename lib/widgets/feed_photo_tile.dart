import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:PeerReal/services/ditto_service.dart';
import '../services/logger_service.dart';

class FeedPhotoTile extends StatefulWidget {
  final Map<String, dynamic> doc;

  const FeedPhotoTile({super.key, required this.doc});

  @override
  State<FeedPhotoTile> createState() => _FeedPhotoTileState();
}

class _FeedPhotoTileState extends State<FeedPhotoTile> {
  Uint8List? _imageData;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final imageData = await DittoService.instance.getAttachmentData(
        widget.doc,
      );

      if (mounted) {
        setState(() {
          _imageData = imageData;
        });
      }
    } catch (e) {
      logger.e('Error in _loadImage: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _imageData != null ? Colors.green : Colors.red,
      child: _imageData != null && _imageData!.isNotEmpty
          ? Image.memory(
              _imageData!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                logger.e('Image decode error: $error');
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white),
                      Text(
                        'Decode error',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                );
              },
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.white),
                  Text(
                    'No Image',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
    );
  }
}
