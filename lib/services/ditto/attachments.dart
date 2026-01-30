part of '../ditto_service.dart';

mixin _DittoAttachmentsMixin on _DittoServiceBase {
  Future<Uint8List?> _loadAttachmentFromToken(
    Map<String, dynamic>? attachmentToken,
  ) async {
    try {
      final d = _ditto;
      if (d == null) {
        logger.e('Ditto is null in _loadAttachmentFromToken');
        return null;
      }

      if (attachmentToken == null) {
        return null;
      }

      final completer = Completer<Uint8List?>();

      final fetcher = d.store.fetchAttachment(attachmentToken, (event) async {
        if (event is AttachmentFetchEventCompleted) {
          try {
            final data = await event.attachment.data;
            if (!completer.isCompleted) completer.complete(data);
          } catch (_) {
            if (!completer.isCompleted) completer.complete(null);
          }
        } else if (event is AttachmentFetchEventDeleted) {
          if (!completer.isCompleted) completer.complete(null);
        }
      });

      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          fetcher.stop();
          return null;
        },
      );

      return result;
    } catch (e) {
      logger.e('Error in _loadAttachmentFromToken: $e');
      return null;
    }
  }

  Future<Uint8List?> getAttachmentData(Map<String, dynamic> doc) async {
    return _loadAttachmentFromToken(doc['attachment']);
  }

  Future<Uint8List?> getSelfieAttachmentData(Map<String, dynamic> doc) async {
    return _loadAttachmentFromToken(doc['selfieAttachment']);
  }
}
