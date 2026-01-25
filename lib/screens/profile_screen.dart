import 'package:PeerReal/screens/settings_screen.dart';
import 'package:PeerReal/services/dql_builder_service.dart';
import 'package:PeerReal/widgets/peer_real_post_card.dart';
import 'package:ditto_live/ditto_live.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../services/profile_avatar_service.dart';
import 'package:PeerReal/services/ditto_service.dart';
import '../services/logger_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _displayName;

  Uint8List? _avatarBytes;
  final ImagePicker _imagePicker = ImagePicker();

  StoreObserver? _avatarObserver;
  StreamSubscription<QueryResult>? _avatarSub;

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
    _loadAvatar();
    _startAvatarObserver();
  }


  @override
  void dispose() {
    _avatarSub?.cancel();
    _avatarObserver?.cancel();
    super.dispose();
  }

  Future<void> _loadDisplayName() async {
    final service = DittoService.instance;

    final cached = service.displayName;
    if (cached != null && cached.trim().isNotEmpty) {
      if (!mounted) return;
      setState(() => _displayName = cached.trim());
      return;
    }

    final name = await service.getDisplayNameForPeer(service.activeUserId);
    if (!mounted) return;
    setState(() {
      _displayName = name;
    });
  }
  Future<void> _loadAvatar() async {
    final service = DittoService.instance;
    final me = service.activeUserId;

    Uint8List? bytes;

    if (service.isLoggedIn) {
      bytes = await service.getAvatarBytesForPeer(me);
      if (bytes != null) {
        await ProfileAvatarService.saveForPeer(me, bytes);
      } else {
        // Avatar removed in Ditto → prevent stale local fallback.
        await ProfileAvatarService.clearForPeer(me);
      }
    } else {
      bytes = await ProfileAvatarService.loadForPeer(me);
    }

    if (!mounted) return;
    setState(() => _avatarBytes = bytes);
  }

  Future<void> _pickAvatar() async {
    final me = DittoService.instance.activeUserId;

    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    await ProfileAvatarService.saveForPeer(me, bytes);

    try {
      if (DittoService.instance.isLoggedIn) {
        await DittoService.instance.setCurrentUserAvatar(bytes);
      }
    } catch (e) {
      logger.e('❌ Failed to sync avatar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar could not be synced')),
        );
      }
    }

    if (!mounted) return;
    setState(() => _avatarBytes = bytes);
  }

  void _startAvatarObserver() {
    final service = DittoService.instance;
    if (!service.isLoggedIn) return;

    final me = service.activeUserId;

    try {
      final obs = service.ditto.store.registerObserver(
        '''
        SELECT avatar FROM profiles
        WHERE peerId = :id
        ORDER BY createdAt DESC
        LIMIT 1
        ''',
        arguments: {'id': me},
      );

      _avatarObserver = obs;
      _avatarSub = obs.changes.listen((_) async {
        final bytes = await service.getAvatarBytesForPeer(me);
        if (bytes != null) {
          await ProfileAvatarService.saveForPeer(me, bytes);
        } else {
          await ProfileAvatarService.clearForPeer(me);
        }
        if (!mounted) return;
        setState(() => _avatarBytes = bytes);
      });
    } catch (e) {
      logger.e('❌ Failed to start avatar observer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName;
    final handle = name != null && name.isNotEmpty ? '@$name' : '@username';

    return Scaffold(
      backgroundColor: const Color(0xFF05050A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05050A),
        elevation: 0,
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + Name
            Row(
              children: [

                Stack(
                  children: [
                    InkWell(
                      onTap: _pickAvatar,
                      borderRadius: BorderRadius.circular(40),
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white12,
                        backgroundImage: _avatarBytes != null
                            ? MemoryImage(_avatarBytes!)
                            : null,
                        child: _avatarBytes == null
                            ? const Icon(
                                Icons.person,
                                size: 32,
                                color: Colors.white70,
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0C15),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? 'You',
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

            _ProfileStatsRow(),

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
                  WHERE author = :me
                  ORDER BY createdAt DESC
                ''',
                queryArgs: {'me': DittoService.instance.activeUserId},
                builder: (context, result) {
                  final docs = result.items
                      .map((item) => Map<String, dynamic>.from(item.value))
                      .toList();

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'Your PeerReal Memories will be added here later ✨',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 13),
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

class _ProfileStatsRow extends StatelessWidget {
  final Ditto ditto = DittoService.instance.ditto;

  @override
  Widget build(BuildContext context) {
    final me = DittoService.instance.activeUserId;

    return DqlBuilderService(
      ditto: ditto,
      query: '''
        SELECT * FROM reals
        WHERE author = :me
      ''',
      queryArgs: {'me': me},
      builder: (context, filesResult) {
        final momentsCount = filesResult.items.length;

        return DqlBuilderService(
          ditto: ditto,
          query: '''
            SELECT * FROM friendships
            WHERE status = 'accepted'
              AND (fromPeerId = :me OR toPeerId = :me)
          ''',
          queryArgs: {'me': me},
          builder: (context, friendsResult) {
            final friendsCount = friendsResult.items.length;

            final streakCount = 0; //TODO:

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ProfileStat(label: 'Moments', value: momentsCount.toString()),
                _ProfileStat(label: 'Friends', value: friendsCount.toString()),
                _ProfileStat(label: 'Streak', value: streakCount.toString()),
              ],
            );
          },
        );
      },
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