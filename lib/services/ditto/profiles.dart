part of '../ditto_service.dart';

mixin _DittoProfilesMixin on _DittoServiceBase, _DittoSessionMixin {
  Future<String?> _primaryProfileDocIdForUser(String userId) async {
    final d = _ditto;
    if (d == null) return null;

    // Prefer the profile doc that has a password.
    final withPw = await d.store.execute(
      '''
      SELECT _id FROM profiles
      WHERE peerId = :id AND password IS NOT NULL
      ORDER BY createdAt DESC
      LIMIT 1
      ''',
      arguments: {"id": userId},
    );
    if (withPw.items.isNotEmpty) {
      return withPw.items.first.value['_id'] as String;
    }

    // Otherwise use latest.
    final any = await d.store.execute(
      '''
      SELECT _id FROM profiles
      WHERE peerId = :id
      ORDER BY createdAt DESC
      LIMIT 1
      ''',
      arguments: {"id": userId},
    );
    if (any.items.isNotEmpty) {
      return any.items.first.value['_id'] as String;
    }

    return null;
  }

  @override
  Future<bool> isDisplayNameAvailable(String displayName) async {
    final d = _ditto;
    if (d == null) return false;

    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return false;

    try {
      final me = _currentUserId;
      final res = await d.store.execute(
        '''
        SELECT _id FROM profiles
        WHERE lower(displayName) = lower(:name)
        ${me != null ? "AND peerId != :me" : ""}
        LIMIT 1
        ''',
        arguments: {"name": trimmed, if (me != null) "me": me},
      );

      final available = res.items.isEmpty;
      logger.i('Name "$trimmed" available: $available');
      return available;
    } catch (e) {
      logger.e('Error in isDisplayNameAvailable: $e');
      return false;
    }
  }

  @override
  Future<bool> setDisplayName(String displayName) async {
    final d = _ditto;
    if (d == null) return false;

    final userId = _currentUserId;
    if (userId == null) return false;

    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return false;

    if (!await isDisplayNameAvailable(trimmed)) {
      logger.w('DisplayName "$trimmed" already taken');
      return false;
    }

    await ensureProfile(displayName: trimmed);

    _displayName = trimmed;
    _profileNameCache[userId] = trimmed;
    await _saveSession(userId: userId, displayName: trimmed);

    logger.i('DisplayName set to "$trimmed" for $userId');
    return true;
  }

  Future<void> ensureProfile({required String displayName}) async {
    final d = _ditto;
    if (d == null) return;

    final userId = _currentUserId;
    if (userId == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final docId = await _primaryProfileDocIdForUser(userId);

    if (docId == null) {
      await d.store.execute(
        '''
        INSERT INTO COLLECTION profiles
        DOCUMENTS (:doc)
        ''',
        arguments: {
          "doc": {
            "_id": userId,
            "peerId": userId,
            "displayName": displayName,
            "createdAt": now,
          },
        },
      );
    } else {
      await d.store.execute(
        '''
        UPDATE profiles
        SET displayName = :name
        WHERE _id = :id
        ''',
        arguments: {"name": displayName, "id": docId},
      );
    }
  }

  @override
  Future<String> getDisplayNameForPeer(String peerId) async {
    if (_profileNameCache.containsKey(peerId)) {
      return _profileNameCache[peerId]!;
    }

    final d = _ditto;
    if (d == null) return peerId;

    try {
      final res = await d.store.execute(
        '''
        SELECT displayName FROM profiles
        WHERE peerId = :id
        ORDER BY createdAt DESC
        LIMIT 1
        ''',
        arguments: {"id": peerId},
      );

      if (res.items.isNotEmpty) {
        final name = res.items.first.value['displayName'] as String?;
        if (name != null && name.isNotEmpty) {
          _profileNameCache[peerId] = name;
          return name;
        }
      }
      return peerId;
    } catch (e) {
      logger.e('Error in getDisplayNameForPeer: $e');
      return peerId;
    }
  }
}
