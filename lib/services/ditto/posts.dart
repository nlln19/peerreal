part of '../ditto_service.dart';

mixin _DittoPostsMixin on _DittoServiceBase, _DittoDailyWindowMixin {
  // ---------------- POSTS / IMAGES ----------------

  Future<void> addImageFromBytes(
    Uint8List imageBytes, {
    String? fileName,
  }) async {
    final d = _ditto;
    if (d == null) {
      logger.e('Ditto is null in addImageFromBytes');
      return;
    }

    try {
      final attachment = await d.store.newAttachment(imageBytes);

      final dailyWindowId = await getCurrentDailyWindowId();

      final newDocument = {
        "name": fileName ??
            'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
        "createdAt": DateTime.now().millisecondsSinceEpoch,
        "attachment": attachment,
        "author": activeUserId,
        "size": imageBytes.length,
        "dailyWindowId": dailyWindowId,
        "thumbsUp": 0,
        "thumbsDown": 0,
        "thumbsUpUsers": "",
        "thumbsDownUsers": "",
      };

      await d.store.execute(
        '''
        INSERT INTO COLLECTION reals (attachment ATTACHMENT)
        VALUES (:newDocument)
        ''',
        arguments: {"newDocument": newDocument},
      );

      logger.i('Document saved to Ditto with window ID: $dailyWindowId');
    } catch (e) {
      logger.e('Error saving image: $e');
    }
  }

  Future<void> addDualImageFromBytes(
    Uint8List mainBytes,
    Uint8List selfieBytes, {
    String? fileName,
  }) async {
    final d = _ditto;
    if (d == null) {
      logger.e('Ditto is null in addDualImageFromBytes');
      return;
    }

    try {
      final mainAttachment = await d.store.newAttachment(mainBytes);
      final selfieAttachment = await d.store.newAttachment(selfieBytes);
      final dailyWindowId = await getCurrentDailyWindowId();

      final newDocument = {
        "name": fileName ??
            'peerreal_${DateTime.now().millisecondsSinceEpoch}.jpg',
        "createdAt": DateTime.now().millisecondsSinceEpoch,
        "attachment": mainAttachment,
        "selfieAttachment": selfieAttachment,
        "author": activeUserId,
        "mainSize": mainBytes.length,
        "dailyWindowId": dailyWindowId,
        "selfieSize": selfieBytes.length,
        "thumbsUp": 0,
        "thumbsDown": 0,
        "thumbsUpUsers": "",
        "thumbsDownUsers": "",
      };

      await d.store.execute(
        '''
        INSERT INTO COLLECTION reals (attachment ATTACHMENT, selfieAttachment ATTACHMENT)
        VALUES (:newDocument)
        ''',
        arguments: {"newDocument": newDocument},
      );

      logger.i('Dual Image saved to Ditto with window ID: $dailyWindowId');
    } catch (e) {
      logger.e('Error saving dual image: $e');
    }
  }

  Future<int> countRealsForPeer(String peerId) async {
    final d = _ditto;
    if (d == null) return 0;

    try {
      final res = await d.store.execute(
        '''
        SELECT * FROM reals
        WHERE author = :peerId
        ''',
        arguments: {'peerId': peerId},
      );
      return res.items.length;
    } catch (e) {
      logger.e('Error in countRealsForPeer: $e');
      return 0;
    }
  }
}
