part of '../ditto_service.dart';

mixin _DittoReactionsMixin on _DittoServiceBase {
  // ---------------- REACTIONS (with toggle and user tracking) ----------------

  // reactionType: 1 for thumbs up, 0 for thumbs down
  Future<void> toggleReactionOnPost({
    required String postId,
    required int reactionType, // 1 = thumbs up, 0 = thumbs down
  }) async {
    final d = _ditto;
    if (d == null) throw StateError('Ditto not initialized');

    final userId = activeUserId;

    try {
      // Get current post data
      final res = await d.store.execute(
        '''
        SELECT thumbsUp, thumbsDown, thumbsUpUsers, thumbsDownUsers FROM reals
        WHERE _id = :id
        LIMIT 1
        ''',
        arguments: {'id': postId},
      );

      if (res.items.isEmpty) {
        logger.w('Post $postId not found');
        return;
      }

      final doc = res.items.first.value;
      int currentThumbsUp = doc['thumbsUp'] as int? ?? 0;
      int currentThumbsDown = doc['thumbsDown'] as int? ?? 0;

      // Get user lists (stored as comma-separated strings)
      String thumbsUpUsers = doc['thumbsUpUsers'] as String? ?? '';
      String thumbsDownUsers = doc['thumbsDownUsers'] as String? ?? '';

      List<String> thumbsUpList =
          thumbsUpUsers.isEmpty ? [] : thumbsUpUsers.split(',');
      List<String> thumbsDownList =
          thumbsDownUsers.isEmpty ? [] : thumbsDownUsers.split(',');

      if (reactionType == 1) {
        // Thumbs Up
        if (thumbsUpList.contains(userId)) {
          // User already gave thumbs up -> toggle off
          currentThumbsUp = (currentThumbsUp - 1).clamp(0, 999999);
          thumbsUpList.remove(userId);
        } else {
          // User hasn't given thumbs up yet
          currentThumbsUp++;
          thumbsUpList.add(userId);

          // If user had thumbs down, remove it
          if (thumbsDownList.contains(userId)) {
            currentThumbsDown = (currentThumbsDown - 1).clamp(0, 999999);
            thumbsDownList.remove(userId);
          }
        }

        await d.store.execute(
          '''
          UPDATE reals
          SET thumbsUp = :up,
              thumbsDown = :down,
              thumbsUpUsers = :upUsers,
              thumbsDownUsers = :downUsers
          WHERE _id = :id
          ''',
          arguments: {
            'up': currentThumbsUp,
            'down': currentThumbsDown,
            'upUsers': thumbsUpList.join(','),
            'downUsers': thumbsDownList.join(','),
            'id': postId,
          },
        );
      } else if (reactionType == 0) {
        // Thumbs Down
        if (thumbsDownList.contains(userId)) {
          // User already gave thumbs down -> toggle off
          currentThumbsDown = (currentThumbsDown - 1).clamp(0, 999999);
          thumbsDownList.remove(userId);
        } else {
          // User hasn't given thumbs down yet
          currentThumbsDown++;
          thumbsDownList.add(userId);

          // If user had thumbs up, remove it
          if (thumbsUpList.contains(userId)) {
            currentThumbsUp = (currentThumbsUp - 1).clamp(0, 999999);
            thumbsUpList.remove(userId);
          }
        }

        await d.store.execute(
          '''
          UPDATE reals
          SET thumbsUp = :up,
              thumbsDown = :down,
              thumbsUpUsers = :upUsers,
              thumbsDownUsers = :downUsers
          WHERE _id = :id
          ''',
          arguments: {
            'up': currentThumbsUp,
            'down': currentThumbsDown,
            'upUsers': thumbsUpList.join(','),
            'downUsers': thumbsDownList.join(','),
            'id': postId,
          },
        );
      }
    } catch (e) {
      logger.e('Error toggling reaction: $e');
      rethrow;
    }
  }

  /// Gets reaction counts for a post from the reals document
  /// Returns a map: {thumbsUp: count, thumbsDown: count, userHasThumbsUp: bool, userHasThumbsDown: bool}
  Map<String, dynamic> getReactionCountsFromDoc(Map<String, dynamic> doc) {
    final thumbsUp = doc['thumbsUp'] as int? ?? 0;
    final thumbsDown = doc['thumbsDown'] as int? ?? 0;

    final userId = activeUserId;
    final thumbsUpUsers = doc['thumbsUpUsers'] as String? ?? '';
    final thumbsDownUsers = doc['thumbsDownUsers'] as String? ?? '';

    final thumbsUpList =
        thumbsUpUsers.isEmpty ? <String>[] : thumbsUpUsers.split(',');
    final thumbsDownList =
        thumbsDownUsers.isEmpty ? <String>[] : thumbsDownUsers.split(',');

    return {
      'thumbsUp': thumbsUp,
      'thumbsDown': thumbsDown,
      'userHasThumbsUp': thumbsUpList.contains(userId),
      'userHasThumbsDown': thumbsDownList.contains(userId),
    };
  }
}
