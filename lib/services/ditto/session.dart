part of '../ditto_service.dart';

mixin _DittoSessionMixin on _DittoServiceBase {
  // ---------------- Session ----------------

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getString('currentUserId');
    _displayName = prefs.getString('currentDisplayName');

    if (_currentUserId != null &&
        _displayName != null &&
        _displayName!.isNotEmpty) {
      _profileNameCache[_currentUserId!] = _displayName!;
    }
  }

  Future<void> _saveSession({
    required String userId,
    required String displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentUserId', userId);
    await prefs.setString('currentDisplayName', displayName);

    _currentUserId = userId;
    _displayName = displayName;
    _profileNameCache[userId] = displayName;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    // last user merken (für Re-Login nach Logout / Repair-Fallback)
    if (_currentUserId != null) {
      await prefs.setString('lastUserId', _currentUserId!);
    }
    if (_displayName != null) {
      await prefs.setString('lastDisplayName', _displayName!);
    }

    await prefs.remove('currentUserId');
    await prefs.remove('currentDisplayName');

    _currentUserId = null;
    _displayName = null;

    final d = _ditto;
    if (d != null) {
      try {
        await d.store.execute(
          '''
          DELETE FROM COLLECTION profiles
          WHERE peerId = :id AND password IS NULL
          ''',
          arguments: {'id': localPeerId},
        );
      } catch (_) {
        // Ignore
      }
    }
  }
}
