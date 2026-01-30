part of '../ditto_service.dart';

mixin _DittoFriendshipsMixin on _DittoServiceBase {
  Future<bool> sendFriendRequest(String toPeerId) async {
    final d = _ditto;
    if (d == null) return false;

    try {
      final me = activeUserId;

      final existing = await d.store.execute(
        '''
        SELECT status, fromPeerId, toPeerId
        FROM friendships
        WHERE (fromPeerId = :me AND toPeerId = :other)
           OR (fromPeerId = :other AND toPeerId = :me)
        ORDER BY updatedAt DESC
        LIMIT 1
        ''',
        arguments: {'me': me, 'other': toPeerId},
      );

      if (existing.items.isNotEmpty) {
        final status = existing.items.first.value['status'] as String? ?? '';
        if (status == 'accepted' || status == 'pending') {
          return false;
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await d.store.execute(
        '''
        INSERT INTO COLLECTION friendships
        DOCUMENTS (:doc)
        ''',
        arguments: {
          "doc": {
            "fromPeerId": me,
            "toPeerId": toPeerId,
            "status": 'pending',
            "createdAt": now,
            "updatedAt": now,
          },
        },
      );
      return true;
    } catch (e) {
      logger.e('Error sending friend request to $toPeerId: $e');
      return false;
    }
  }

  // ignore: strict_top_level_inference
  Future<void> acceptFriendRequest(friendshipId) async {
    final d = _ditto;
    if (d == null) return;

    await d.store.execute(
      '''
      UPDATE friendships
      SET status = 'accepted',
          updatedAt = :now
      WHERE _id = :id
      ''',
      arguments: {
        "id": friendshipId,
        "now": DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  // ignore: strict_top_level_inference
  Future<void> declineFriendRequest(friendshipId) async {
    final d = _ditto;
    if (d == null) return;

    await d.store.execute(
      '''
      UPDATE friendships
      SET status = 'declined',
          updatedAt = :now
      WHERE _id = :id
      ''',
      arguments: {
        "id": friendshipId,
        "now": DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<String> getFriendshipStatusWith(String otherPeerId) async {
    final d = _ditto;
    if (d == null) return 'none';

    try {
      final res = await d.store.execute(
        '''
        SELECT * FROM friendships
        WHERE (fromPeerId = :me AND toPeerId = :other)
           OR (fromPeerId = :other AND toPeerId = :me)
        ORDER BY createdAt DESC
        LIMIT 1
        ''',
        arguments: {'me': activeUserId, 'other': otherPeerId},
      );

      if (res.items.isEmpty) return 'none';

      return res.items.first.value['status'] as String? ?? 'pending';
    } catch (e) {
      logger.e('Error in getFriendshipStatusWith: $e');
      return 'none';
    }
  }

  Future<int> countFriendsForPeer(String peerId) async {
    final d = _ditto;
    if (d == null) return 0;

    try {
      final res = await d.store.execute(
        '''
        SELECT * FROM friendships
        WHERE status = 'accepted'
          AND (fromPeerId = :peerId OR toPeerId = :peerId)
        ''',
        arguments: {'peerId': peerId},
      );
      return res.items.length;
    } catch (e) {
      logger.e('Error in countFriendsForPeer: $e');
      return 0;
    }
  }
}
