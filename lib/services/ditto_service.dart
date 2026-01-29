import 'dart:async';

import 'package:PeerReal/services/password_hasher.dart';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/logger_service.dart';
import 'notification_service.dart';

part 'ditto/account.dart';
part 'ditto/attachments.dart';
part 'ditto/avatar.dart';
part 'ditto/auth.dart';
part 'ditto/daily_window.dart';
part 'ditto/friendships.dart';
part 'ditto/init.dart';
part 'ditto/posts.dart';
part 'ditto/profiles.dart';
part 'ditto/reactions.dart';
part 'ditto/session.dart';

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

class _AvatarCacheEntry {
  final String tokenId;
  final Uint8List bytes;
  const _AvatarCacheEntry(this.tokenId, this.bytes);
}

/// Main facade for Ditto access.
///
/// The public API stays on this class, but the implementation is split into
/// focused mixins (see the `part` files under `services/ditto/`).
abstract class _DittoServiceBase {
  Ditto? _ditto;

  Ditto get ditto {
    final d = _ditto;
    if (d == null) {
      throw StateError('DittoService not initialized. Call init() first.');
    }
    return d;
  }

  // Local device identity
  late final String localPeerId;
  bool _localPeerIdInitialized = false;

  // Account/session
  String? _currentUserId; // = profiles.peerId (Account-Id)
  String? get currentUserId => _currentUserId;
  bool get isLoggedIn => _currentUserId != null;

  String get activeUserId => _currentUserId ?? localPeerId;

  String? _displayName;
  String? get displayName => _displayName;

  // Simple in-memory caches
  final Map<String, String> _profileNameCache = {}; // peerId -> displayName
  final Map<String, _AvatarCacheEntry> _avatarCache = {}; // peerId -> avatar

  // Notification tracking
  StoreObserver? _postObserver;
  final Set<String> _seenPostIds = {};

  // Daily window tracking
  String _currentDailyWindowId = '';

  // ---- Public API implemented by mixins ----
  // Declared here so other mixins can call them without relying on mixin
  // application order.
  Future<bool> isDisplayNameAvailable(String displayName);
  Future<bool> setDisplayName(String displayName);
  Future<String> getDisplayNameForPeer(String peerId);
  Future<String> getFriendshipStatusWith(String otherPeerId);
}

class DittoService extends _DittoServiceBase
    with
        _DittoSessionMixin,
        _DittoInitMixin,
        _DittoDailyWindowMixin,
        _DittoProfilesMixin,
        _DittoAttachmentsMixin,
        _DittoAuthMixin,
        _DittoAvatarMixin,
        _DittoPostsMixin,
        _DittoReactionsMixin,
        _DittoFriendshipsMixin,
        _DittoAccountMixin {
  static final DittoService instance = DittoService._internal();

  DittoService._internal();
}
