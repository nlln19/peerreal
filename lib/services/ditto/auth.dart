part of '../ditto_service.dart';

mixin _DittoAuthMixin
    on _DittoServiceBase, _DittoSessionMixin, _DittoProfilesMixin {
  Future<Map<String, dynamic>?> _getPasswordMapByDocId(String docId) async {
    final d = _ditto;
    if (d == null) return null;

    final res = await d.store.execute(
      '''
      SELECT password FROM profiles
      WHERE _id = :id
      LIMIT 1
      ''',
      arguments: {"id": docId},
    );

    if (res.items.isEmpty) return null;
    final pw = res.items.first.value['password'];
    if (pw == null) return null;
    return Map<String, dynamic>.from(pw as Map);
  }

  /// Robust lookup:
  /// 1) Prefer profiles with password for the given name.
  /// 2) If only "no password" docs exist for that name, ignore legacy device-docs (peerId==localPeerId).
  /// 3) If still ambiguous, and the user just logged out, use lastUserId fallback (fixes the reported bug).
  Future<UserLookup?> lookupUserByDisplayName(String displayName) async {
    final d = _ditto;
    if (d == null) return null;

    final name = displayName.trim();
    if (name.isEmpty) return null;

    // 1) Prefer any profile with password for this displayName
    final withPw = await d.store.execute(
      '''
      SELECT _id, peerId, displayName FROM profiles
      WHERE lower(displayName) = lower(:name)
        AND password IS NOT NULL
      ORDER BY createdAt DESC
      LIMIT 1
      ''',
      arguments: {"name": name},
    );

    if (withPw.items.isNotEmpty) {
      final v = withPw.items.first.value;
      return UserLookup(
        docId: v['_id'] as String,
        userId: v['peerId'] as String,
        displayName: v['displayName'] as String,
        hasPassword: true,
      );
    }

    // 2) Otherwise: get matches and skip legacy device-only docs
    final any = await d.store.execute(
      '''
      SELECT _id, peerId, displayName, password, createdAt FROM profiles
      WHERE lower(displayName) = lower(:name)
      ORDER BY createdAt DESC
      LIMIT 20
      ''',
      arguments: {"name": name},
    );

    UserLookup? bestNonDevice;
    UserLookup? bestDevice;

    for (final item in any.items) {
      final v = item.value;
      final peerId = v['peerId'] as String?;
      if (peerId == null) continue;

      final hasPw = v['password'] != null;

      final candidate = UserLookup(
        docId: v['_id'] as String,
        userId: peerId,
        displayName: v['displayName'] as String? ?? name,
        hasPassword: hasPw,
      );

      if (peerId == localPeerId) {
        bestDevice ??= candidate;
      } else {
        bestNonDevice ??= candidate;
        break;
      }
    }

    // 3) Critical bug fix: after logout -> login with same user
    if (bestNonDevice == null || !bestNonDevice.hasPassword) {
      final prefs = await SharedPreferences.getInstance();
      final lastUserId = prefs.getString('lastUserId');
      final lastName = prefs.getString('lastDisplayName');

      if (lastUserId != null &&
          lastName != null &&
          lastName.toLowerCase() == name.toLowerCase()) {
        final docId = await _primaryProfileDocIdForUser(lastUserId);
        if (docId != null) {
          final pw = await _getPasswordMapByDocId(docId);
          if (pw != null) {
            return UserLookup(
              docId: docId,
              userId: lastUserId,
              displayName: name,
              hasPassword: true,
            );
          }
        }
      }
    }

    return bestNonDevice ?? bestDevice;
  }

  Future<void> signupNewUser({
    required String displayName,
    required String password,
  }) async {
    final d = _ditto;
    if (d == null) throw StateError('Ditto not initialized');

    final name = displayName.trim();
    if (name.isEmpty) throw StateError('USERNAME_EMPTY');

    if (!await isDisplayNameAvailable(name)) {
      throw StateError('NAME_TAKEN');
    }

    final userId = const Uuid().v4();
    final pw = await PasswordHasher.hashPassword(password);
    final now = DateTime.now().millisecondsSinceEpoch;

    await d.store.execute(
      '''
      INSERT INTO COLLECTION profiles
      DOCUMENTS (:doc)
      ''',
      arguments: {
        'doc': {
          '_id': userId,
          'peerId': userId,
          'displayName': name,
          'createdAt': now,
          'password': pw,
        },
      },
    );

    await _saveSession(userId: userId, displayName: name);
  }

  Future<void> setPasswordForExistingUser({
    required String docId,
    required String userId,
    required String displayName,
    required String password,
  }) async {
    final d = _ditto;
    if (d == null) throw StateError('Ditto not initialized');

    final pw = await PasswordHasher.hashPassword(password);

    await d.store.execute(
      '''
      UPDATE profiles
      SET password = :pw
      WHERE _id = :id
      ''',
      arguments: {'pw': pw, 'id': docId},
    );

    await _saveSession(userId: userId, displayName: displayName);
  }

  Future<void> loginUser({
    required String displayName,
    required String password,
  }) async {
    final hit = await lookupUserByDisplayName(displayName);
    if (hit == null) throw StateError('NO_USER');
    if (!hit.hasPassword) throw StateError('NO_PASSWORD_SET');

    final stored = await _getPasswordMapByDocId(hit.docId);
    if (stored == null) throw StateError('NO_PASSWORD_SET');

    final ok = await PasswordHasher.verifyPassword(password, stored);
    if (!ok) throw StateError('WRONG_PASSWORD');

    await _saveSession(userId: hit.userId, displayName: hit.displayName);
  }

  /// Change password for the currently logged in user.
  /// Requires confirming the old password.
  ///
  /// Throws StateError with:
  /// - NOT_LOGGED_IN
  /// - DITTO_NOT_READY
  /// - NO_PASSWORD_SET
  /// - WRONG_PASSWORD
  /// - WEAK_PASSWORD
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final d = _ditto;
    if (d == null) throw StateError('DITTO_NOT_READY');

    final userId = _currentUserId;
    if (userId == null) throw StateError('NOT_LOGGED_IN');

    final newPw = newPassword;
    if (newPw.length < 6) throw StateError('WEAK_PASSWORD');

    final res = await d.store.execute(
      '''
      SELECT _id, password
      FROM profiles
      WHERE peerId = :id AND password IS NOT NULL
      ORDER BY createdAt DESC
      LIMIT 1
      ''',
      arguments: {'id': userId},
    );

    if (res.items.isEmpty) throw StateError('NO_PASSWORD_SET');

    final storedAny = res.items.first.value['password'];
    if (storedAny == null) throw StateError('NO_PASSWORD_SET');

    final stored = Map<String, dynamic>.from(storedAny as Map);

    final ok = await PasswordHasher.verifyPassword(oldPassword, stored);
    if (!ok) throw StateError('WRONG_PASSWORD');

    final pw = await PasswordHasher.hashPassword(newPw);

    // Update all password-bearing profile docs for this user (handles duplicates).
    await d.store.execute(
      '''
      UPDATE profiles
      SET password = :pw
      WHERE peerId = :id AND password IS NOT NULL
      ''',
      arguments: {'pw': pw, 'id': userId},
    );
  }
}
