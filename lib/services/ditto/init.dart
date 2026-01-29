part of '../ditto_service.dart';

mixin _DittoInitMixin on _DittoServiceBase, _DittoSessionMixin {
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
    logger.i('Ditto opened with appId=$appId');

    ditto.updateTransportConfig((config) {
      config.connect.webSocketUrls.add(websocketUrl);
      if (!kIsWeb) {
        config.setAllPeerToPeerEnabled(true);
      }
    });

    await ditto.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = false");

    ditto.startSync();

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
        })
        .catchError((e) {
          logger.e('Error loading existing posts: $e');
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
            final ns = NotificationService.instance;
            try {
              await (ns as dynamic).showNewPostNotification(
                authorName: authorName,
                authorId: author,
              );
            } catch (_) {
              // NotificationService may not expose this method on all platforms.
            }
          } catch (e) {
            logger.e('Error showing notification: $e');
          }
        }

        _seenPostIds.add(postId);
      }
    });
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
          logger.i('Loaded existing profile name: $name');
        }
      }
    } catch (e) {
      logger.e('Error loading own profile: $e');
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
    logger.i('localPeerId = $localPeerId');
  }

  void dispose() {
    _postObserver?.cancel();
    _ditto?.stopSync();
    _ditto?.close();
    _ditto = null;
  }
}
