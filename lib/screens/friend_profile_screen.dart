import 'dart:async';
import 'dart:typed_data';

import 'package:PeerReal/services/dql_builder_service.dart';
import 'package:PeerReal/widgets/peer_real_post_card.dart';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

import '../services/ditto_service.dart';

class FriendProfileScreen extends StatefulWidget {
  final String peerId;
  final String? initialDisplayName;

  const FriendProfileScreen({
    super.key,
    required this.peerId,
    this.initialDisplayName,
  });

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  String? _displayName;
  int? _momentsCount;
  int? _friendsCount;

  Uint8List? _avatarBytes;
  StoreObserver? _avatarObserver;
  StreamSubscription? _avatarObserverSub;

  @override
  void initState() {
    super.initState();
    _displayName = widget.initialDisplayName;
    _loadProfile();
    _loadAvatar();
    _startAvatarObserver();
  }

  Future<void> _loadProfile() async {
    final service = DittoService.instance;

    final name = await service.getDisplayNameForPeer(widget.peerId);
    final moments = await service.countRealsForPeer(widget.peerId);
    final friends = await service.countFriendsForPeer(widget.peerId);

    if (!mounted) return;
    setState(() {
      _displayName = name;
      _momentsCount = moments;
      _friendsCount = friends;
    });
  }

  Future<void> _loadAvatar() async {
    final bytes = await DittoService.instance.getAvatarBytesForPeer(widget.peerId);
    if (!mounted) return;
    setState(() => _avatarBytes = bytes);
  }

  void _startAvatarObserver() {
    // Refresh when the profile doc changes (avatar token update / unset).
    try {
      _avatarObserver = DittoService.instance.ditto.store.registerObserver(
        '''
        SELECT avatar, avatarUpdatedAt, createdAt FROM profiles
        WHERE peerId = :id
        ORDER BY createdAt DESC
        LIMIT 1
        ''',
        arguments: {'id': widget.peerId},
      );

      _avatarObserverSub = _avatarObserver?.changes.listen((_) => _loadAvatar());
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _avatarObserverSub?.cancel();
    _avatarObserver?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName ?? 'Loading…';
    final short = widget.peerId.length >= 8 ? widget.peerId.substring(0, 8) : widget.peerId;
    final handle = '@$short';

    return Scaffold(
      backgroundColor: const Color(0xFF05050A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05050A),
        elevation: 0,
        title: Text("$name's Profile"),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white12,
                  backgroundImage:
                      _avatarBytes != null ? MemoryImage(_avatarBytes!) : null,
                  child: _avatarBytes == null
                      ? const Icon(Icons.person,
                          size: 32, color: Colors.white70)
                      : null,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      handle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ProfileStat(
                  label: 'Moments',
                  value: _momentsCount?.toString() ?? '–',
                ),
                _ProfileStat(
                  label: 'Friends',
                  value: _friendsCount?.toString() ?? '–',
                ),
                const _ProfileStat(label: 'Streak', value: '0'), // TODO:
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Latest moments',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DqlBuilderService(
                ditto: DittoService.instance.ditto,
                query: '''
                  SELECT * FROM reals
                  WHERE author = :peerId
                  ORDER BY createdAt DESC
                ''',
                queryArgs: {'peerId': widget.peerId},
                builder: (context, result) {
                  final docs = result.items
                      .map((item) => Map<String, dynamic>.from(item.value))
                      .toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        "$name has no PeerReal moments yet😔",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      return PeerRealPostCard(
                        key: ValueKey(doc['_id'] ?? doc['createdAt']),
                        doc: doc,
                        showAuthorHeader: false,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}
