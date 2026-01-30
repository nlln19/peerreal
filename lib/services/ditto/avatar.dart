part of '../ditto_service.dart';

mixin _DittoAvatarMixin
    on _DittoServiceBase, _DittoProfilesMixin, _DittoAttachmentsMixin {
  Future<void> setCurrentUserAvatar(Uint8List avatarBytes) async {
    final d = _ditto;
    if (d == null) {
      throw StateError('DittoService not initialized. Call init() first.');
    }
    final userId = _currentUserId;
    if (userId == null) {
      throw StateError('Not logged in');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Create attachment (store bytes in Ditto blob store, replicate token in document)
    final metadata = AttachmentMetadata({
      'name': 'avatar_$now.jpg',
      'mime_type': 'image/jpeg',
      'purpose': 'profile_avatar',
    });
    final attachment = await d.store.newAttachment(avatarBytes, metadata);

    // Update existing primary profile doc, or create one if missing.
    final docId = await _primaryProfileDocIdForUser(userId);
    if (docId == null) {
      await d.store.execute(
        '''
        INSERT INTO COLLECTION profiles (avatar ATTACHMENT)
        DOCUMENTS (:doc)
        ''',
        arguments: {
          'doc': {
            '_id': userId,
            'peerId': userId,
            'displayName': _displayName ?? userId,
            'createdAt': now,
            'avatar': attachment,
            'avatarUpdatedAt': now,
          },
        },
      );
    } else {
      await d.store.execute(
        '''
        UPDATE COLLECTION profiles (avatar ATTACHMENT)
        SET avatar = :avatar, avatarUpdatedAt = :ts
        WHERE _id = :id
        ''',
        arguments: {'avatar': attachment, 'ts': now, 'id': docId},
      );
    }
    _avatarCache.remove(userId);
  }

  Future<void> deleteCurrentUserAvatar() async {
    final d = _ditto;
    if (d == null) {
      throw StateError('DittoService not initialized. Call init() first.');
    }
    final userId = _currentUserId;
    if (userId == null) {
      throw StateError('Not logged in');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final docId = await _primaryProfileDocIdForUser(userId);
    if (docId == null) {
      // Nothing to delete, but ensure local cache is cleared.
      _avatarCache.remove(userId);
      return;
    }

    await d.store.execute(
      '''
  UPDATE COLLECTION profiles (avatar ATTACHMENT)
  UNSET avatar
  WHERE _id = :id
  ''',
      arguments: {'id': docId},
    );

    await d.store.execute(
      '''
  UPDATE profiles
  SET avatarUpdatedAt = :ts
  WHERE _id = :id
  ''',
      arguments: {'ts': now, 'id': docId},
    );

    _avatarCache.remove(userId);
  }

  Future<Uint8List?> getAvatarBytesForPeer(String peerId) async {
    final d = _ditto;
    if (d == null) return null;

    try {
      final res = await d.store.execute(
        '''
        SELECT avatar FROM profiles
        WHERE peerId = :id
        ORDER BY createdAt DESC
        LIMIT 1
        ''',
        arguments: {'id': peerId},
      );

      if (res.items.isEmpty) return null;

      final any = res.items.first.value['avatar'];
      if (any == null || any is! Map) return null;

      final token = Map<String, dynamic>.from(any);
      final tokenId = token['id'] as String?;
      if (tokenId == null || tokenId.isEmpty) return null;

      final cached = _avatarCache[peerId];
      if (cached != null && cached.tokenId == tokenId) {
        return cached.bytes;
      }

      final bytes = await _loadAttachmentFromToken(token);
      if (bytes == null) return null;

      _avatarCache[peerId] = _AvatarCacheEntry(tokenId, bytes);
      return bytes;
    } catch (e) {
      logger.e('Error in getAvatarBytesForPeer: $e');
      return null;
    }
  }
}
