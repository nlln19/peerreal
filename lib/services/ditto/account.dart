part of '../ditto_service.dart';

mixin _DittoAccountMixin on _DittoServiceBase {
  // ---------------- DELETE ACCOUNT ----------------

  Future<bool> deleteAccountAndData() async {
    final d = _ditto;
    if (d == null) return false;

    final id = activeUserId;

    try {
      await d.store.execute(
        '''
        DELETE FROM COLLECTION reals
        WHERE author = :id
        ''',
        arguments: {"id": id},
      );

      await d.store.execute(
        '''
        DELETE FROM COLLECTION friendships
        WHERE fromPeerId = :id
           OR toPeerId   = :id
        ''',
        arguments: {"id": id},
      );

      await d.store.execute(
        '''
        DELETE FROM COLLECTION profiles
        WHERE peerId = :id
        ''',
        arguments: {"id": id},
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('currentUserId');
      await prefs.remove('currentDisplayName');
      await prefs.remove('lastUserId');
      await prefs.remove('lastDisplayName');

      _currentUserId = null;
      _displayName = null;
      _profileNameCache.clear();

      return true;
    } catch (e) {
      logger.e('Error in deleteAccountAndData: $e');
      return false;
    }
  }
}
