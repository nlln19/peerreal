import 'dart:async';

import 'package:PeerReal/services/password_hasher.dart';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/logger_service.dart';
import 'notification_service.dart';

/// Returned by [DittoService.lookupUserByDisplayName].
class UserLookup {
  final String docId; // profiles._id
  final String userId; // profiles.peerId
  final String displayName;
  final bool hasPassword;

  UserLookup({
    required this.docId,
    required this.userId,
    required this.displayName,
    required this.hasPassword,
  });
}

class DittoService {
  static final DittoService instance = DittoService._internal();
  Ditto? _ditto;

  DittoService._internal();

  Ditto get ditto {
    final d = _ditto;
    if (d == null) {
      throw StateError('DittoService not initialized. Call init() first.');
    }
    return d;
  }

  late final String localPeerId;
  bool _localPeerIdInitialized = false;

  // Account/session
  String? _currentUserId; // = profiles.peerId (Account-Id)
  String? get currentUserId => _currentUserId;
  bool get isLoggedIn => _currentUserId != null;

  /// Use this everywhere for authored content (posts/friends/etc.).
  /// If logged out, falls back to device id.
  String get activeUserId => _currentUserId ?? localPeerId;

  String? _displayName;
  String? get displayName => _displayName;

  final Map<String, String> _profileNameCache = {}; // peerId -> displayName

  // Notification tracking
  StoreObserver? _postObserver;
  final Set<String> _seenPostIds = {};

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

    // Cleanup: remove legacy device-only profile docs that were created by old code.
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
        // Ignore (older DQL versions might not support IS NULL, etc.)
      }
    }
  }

  // ---------------- Init ----------------

  Future<Ditto> init() async {
    if (_ditto != null) return _ditto!;

    await _initLocalPeerId();
    await loadSession();
    await Ditto.init();

    final appId = dotenv.env['DITTO_APP_ID']!;
    final token = dotenv.env['DITTO_PLAYGROUND_TOKEN']!;
    final authUrl = dotenv.env['DITTO_AUTH_URL']!;
    final websocketUrl = dotenv.env['DITTO_WEBSOCKET_URL']!;

    final identity = OnlinePlaygroundIdentity(
      appID: appId,
      token: token,
      customAuthUrl: authUrl,
      enableDittoCloudSync: false,
    );

    final ditto = await Ditto.open(identity: identity);
    logger.i('✅ Ditto opened with appId=$appId');

    ditto.updateTransportConfig((config) {
      config.connect.webSocketUrls.add(websocketUrl);
      if (!kIsWeb) {
        config.setAllPeerToPeerEnabled(true);
      }
    });

    await ditto.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = false");

    ditto.startSync();
    logger.i('🚀 Ditto sync started');

    ditto.sync.registerSubscription('SELECT * FROM reals');
    ditto.sync.registerSubscription('SELECT * FROM profiles');
    ditto.sync.registerSubscription('SELECT * FROM friendships');

    _ditto = ditto;

    // Only load own displayName if logged in (prevents device-profile pollution).
    if (isLoggedIn) {
      unawaited(_loadOwnProfileDisplayName());
    }

    // Cleanup old device-profile docs once per app start (best effort).
    unawaited(_cleanupLegacyDeviceProfiles());

    _startPostNotificationListener();
    return ditto;
  }

  Future<void> _cleanupLegacyDeviceProfiles() async {
    final d = _ditto;
    if (d == null) return;

    try {
      await d.store.execute(
        '''
        DELETE FROM COLLECTION profiles
        WHERE peerId = :id AND password IS NULL
        ''',
        arguments: {'id': localPeerId},
      );
    } catch (_) {
      // ignore
    }
  }

  void _startPostNotificationListener() {
    final d = _ditto;
    if (d == null) return;

    d.store
        .execute('SELECT _id FROM reals', arguments: {})
        .then((result) {
          for (final item in result.items) {
            final docId = item.value['_id'] as String;
            _seenPostIds.add(docId);
          }
          logger.i(
            '👂 Loaded ${_seenPostIds.length} existing posts to skip notifications',
          );
        })
        .catchError((e) {
          logger.e('❌ Error loading existing posts: $e');
        });

    _postObserver = d.store.registerObserver(
      'SELECT * FROM reals ORDER BY createdAt DESC',
      arguments: {},
    );

    _postObserver?.changes.listen((result) async {
      for (final item in result.items) {
        final doc = item.value;
        final postId = doc['_id'] as String;
        final author = doc['author'] as String?;

        if (author == null ||
            author == activeUserId ||
            _seenPostIds.contains(postId)) {
          continue;
        }

        final friendshipStatus = await getFriendshipStatusWith(author);

        if (friendshipStatus == 'accepted') {
          final authorName = await getDisplayNameForPeer(author);
          try {
            await NotificationService.instance.showNewPostNotification(
              authorName: authorName,
              authorId: author,
            );
            logger.i('🔔 Notified about post from $authorName');
          } catch (e) {
            logger.e('❌ Error showing notification: $e');
          }
        }

        _seenPostIds.add(postId);
      }
    });

    logger.i('👂 Started listening for new posts');
  }

  Future<void> _loadOwnProfileDisplayName() async {
    final d = _ditto;
    if (d == null) return;
    if (!isLoggedIn) return;

    try {
      final res = await d.store.execute(
        '''
        SELECT displayName FROM profiles
        WHERE peerId = :id
        ORDER BY createdAt DESC
        LIMIT 1
        ''',
        arguments: {"id": activeUserId},
      );

      if (res.items.isNotEmpty) {
        final name = res.items.first.value['displayName'] as String?;
        if (name != null && name.isNotEmpty) {
          _displayName = name;
          _profileNameCache[activeUserId] = name;
          logger.i('👤 Loaded existing profile name: $name');
        }
      }
    } catch (e) {
      logger.e('❌ Error loading own profile: $e');
    }
  }

  // ---------------- PROFILE / USERNAME ----------------

  Future<void> _initLocalPeerId() async {
    if (_localPeerIdInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('localPeerId');

    if (existing != null) {
      localPeerId = existing;
    } else {
      final newId = const Uuid().v4();
      localPeerId = newId;
      await prefs.setString('localPeerId', newId);
    }

    _localPeerIdInitialized = true;
    logger.i('🆔 localPeerId = $localPeerId');
  }

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
      logger.i('🔎 Name "$trimmed" available: $available');
      return available;
    } catch (e) {
      logger.e('❌ Error in isDisplayNameAvailable: $e');
      return false;
    }
  }

  /// IMPORTANT: This must not create new profiles with peerId == localPeerId (old bug source).
  /// It only updates the logged-in user's profile displayName.
  Future<bool> setDisplayName(String displayName) async {
    final d = _ditto;
    if (d == null) return false;

    final userId = _currentUserId;
    if (userId == null) return false; // must be logged in

    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return false;

    if (!await isDisplayNameAvailable(trimmed)) {
      logger.w('🚫 DisplayName "$trimmed" already taken');
      return false;
    }

    await ensureProfile(displayName: trimmed);

    _displayName = trimmed;
    _profileNameCache[userId] = trimmed;
    await _saveSession(userId: userId, displayName: trimmed);

    logger.i('✅ DisplayName set to "$trimmed" for $userId');
    return true;
  }

  /// Ensures the logged-in account has a profile doc and updates its displayName.
  /// (No more device profiles.)
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
      logger.e('❌ Error in getDisplayNameForPeer: $e');
      return peerId;
    }
  }

  // ---------------- AUTH ----------------

  Future<String?> _primaryProfileDocIdForUser(String userId) async {
    final d = _ditto;
    if (d == null) return null;

    // prefer the profile doc that has a password
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

  // ---------------- POSTS / IMAGES ----------------

  Future<void> addImageFromBytes(
    Uint8List imageBytes, {
    String? fileName,
  }) async {
    final d = _ditto;
    if (d == null) {
      logger.e('❌ Ditto is null in addImageFromBytes');
      return;
    }

    try {
      logger.i('📸 Saving image: ${imageBytes.length} bytes');

      final attachment = await d.store.newAttachment(imageBytes);
      logger.i(
        '✅ Attachment created. id=${attachment.id}, len=${attachment.len}',
      );

      final newDocument = {
        "name":
            fileName ?? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
        "createdAt": DateTime.now().millisecondsSinceEpoch,
        "attachment": attachment,
        "author": activeUserId,
        "size": imageBytes.length,
      };

      await d.store.execute(
        '''
        INSERT INTO COLLECTION reals (attachment ATTACHMENT)
        VALUES (:newDocument)
        ''',
        arguments: {"newDocument": newDocument},
      );

      logger.i('✅ Document saved to Ditto');
    } catch (e) {
      logger.e('❌ Error saving image: $e');
    }
  }

  Future<void> addDualImageFromBytes(
    Uint8List mainBytes,
    Uint8List selfieBytes, {
    String? fileName,
  }) async {
    final d = _ditto;
    if (d == null) {
      logger.e('❌ Ditto ist null in addDualImageFromBytes');
      return;
    }

    try {
      logger.i(
        '📸 Saving dual image: main=${mainBytes.length}, selfie=${selfieBytes.length} bytes',
      );

      final mainAttachment = await d.store.newAttachment(mainBytes);
      final selfieAttachment = await d.store.newAttachment(selfieBytes);

      logger.i(
        '✅ Attachments created: main=${mainAttachment.id}, selfie=${selfieAttachment.id}',
      );

      final newDocument = {
        "name":
            fileName ?? 'peerreal_${DateTime.now().millisecondsSinceEpoch}.jpg',
        "createdAt": DateTime.now().millisecondsSinceEpoch,
        "attachment": mainAttachment,
        "selfieAttachment": selfieAttachment,
        "author": activeUserId,
        "mainSize": mainBytes.length,
        "selfieSize": selfieBytes.length,
      };

      await d.store.execute(
        '''
        INSERT INTO COLLECTION reals (attachment ATTACHMENT, selfieAttachment ATTACHMENT)
        VALUES (:newDocument)
        ''',
        arguments: {"newDocument": newDocument},
      );

      logger.i('✅ Dual Image saved to Ditto');
    } catch (e) {
      logger.e('❌ Error saving dual image: $e');
    }
  }

  Future<Uint8List?> _loadAttachmentFromToken(
    Map<String, dynamic>? attachmentToken,
  ) async {
    try {
      final d = _ditto;
      if (d == null) {
        logger.e('❌ Ditto is null in _loadAttachmentFromToken');
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
      logger.e('❌ Error in _loadAttachmentFromToken: $e');
      return null;
    }
  }

  Future<Uint8List?> getAttachmentData(Map<String, dynamic> doc) async {
    return _loadAttachmentFromToken(doc['attachment']);
  }

  Future<Uint8List?> getSelfieAttachmentData(Map<String, dynamic> doc) async {
    return _loadAttachmentFromToken(doc['selfieAttachment']);
  }

  // ---------------- FRIENDSHIPS ----------------

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
      logger.e('❌ Error in getFriendshipStatusWith: $e');
      return 'none';
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
      logger.e('❌ Error in countRealsForPeer: $e');
      return 0;
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
      logger.e('❌ Error in countFriendsForPeer: $e');
      return 0;
    }
  }

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

      logger.i('🗑️ Account & data deleted for $id');
      return true;
    } catch (e) {
      logger.e('❌ Error in deleteAccountAndData: $e');
      return false;
    }
  }

  void dispose() {
    _postObserver?.cancel();
    _ditto?.stopSync();
    _ditto?.close();
    _ditto = null;
  }
}
