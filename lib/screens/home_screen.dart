import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/cupertino.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/dql_builder_service.dart';
import '../services/ditto_service.dart';
import '../services/permission_service.dart';
import '../screens/camera_screen.dart';
import '../widgets/peer_real_post_card.dart';
import '../screens/profile_screen.dart';
import '../screens/friends_screen.dart';
import '../services/logger_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Ditto? _ditto;
  final ScrollController _scrollController = ScrollController();
  int _feedFilter = 0; // 0 = All, 1 = Friends

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await PermissionService.requestP2PPermissions();
    final ditto = await DittoService.instance.init();
    if (!mounted) return;
    setState(() {
      _ditto = ditto;
    });
  }

  Future<void> _openCamera() async {
    logger.i('📸 Opening Camera Screen');
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );

    if (result == null) return;

    // main + selfie
    if (result is Map &&
        result['main'] is Uint8List &&
        result['selfie'] is Uint8List) {
      final mainBytes = result['main'] as Uint8List;
      final selfieBytes = result['selfie'] as Uint8List;
      await DittoService.instance.addDualImageFromBytes(mainBytes, selfieBytes);
    } else if (result is Uint8List) {
      await DittoService.instance.addImageFromBytes(result);
    }
  }

  Color _segmentTextColor(int value) {
    if (_feedFilter == value) {
      return Colors.black;
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_ditto == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    final me = DittoService.instance.activeUserId;

    return Scaffold(
      backgroundColor: const Color(0xFF05050A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05050A),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'PeerReal.',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              );
            },
          ),
        ],
      ),

      // Camera-Button
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        onPressed: _openCamera,
        child: const Icon(Icons.camera_alt),
      ),

      // Bottom-Bar
      bottomNavigationBar: BottomAppBar(
        color: const Color(0xFF0C0C15),
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.home_outlined,
                label: 'Feed',
                selected: true,
                onTap: () {
                  logger.i('🏠 Home tapped');
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
              const SizedBox(width: 40),
              _BottomNavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                selected: false,
                onTap: () {
                  logger.i('👤 Profile tapped');
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: CupertinoSlidingSegmentedControl<int>(
              backgroundColor: const Color(0xFF11111A),
              thumbColor: Colors.white,
              groupValue: _feedFilter,
              children: {
                0: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  child: Text(
                    'All',
                    style: TextStyle(fontSize: 13, color: _segmentTextColor(0)),
                  ),
                ),
                1: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  child: Text(
                    'Friends',
                    style: TextStyle(fontSize: 13, color: _segmentTextColor(1)),
                  ),
                ),
              },
              onValueChanged: (value) {
                if (value == null) return;
                setState(() {
                  _feedFilter = value;
                });
              },
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: DqlBuilderService(
              ditto: _ditto!,
              query: '''
                SELECT * FROM friendships
                WHERE status = 'accepted'
                  AND (fromPeerId = :me OR toPeerId = :me)
              ''',
              queryArgs: {'me': me},
              builder: (context, friendsResult) {
                final friendDocs = friendsResult.items
                    .map((item) => Map<String, dynamic>.from(item.value))
                    .toList();

                final friendIds = <String>{};
                for (final f in friendDocs) {
                  final from = f['fromPeerId'] as String?;
                  final to = f['toPeerId'] as String?;
                  if (from != null && from != me) friendIds.add(from);
                  if (to != null && to != me) friendIds.add(to);
                }

                return DqlBuilderService(
                  ditto: _ditto!,
                  query: '''
                    SELECT * FROM reals
                    ORDER BY createdAt DESC
                  ''',
                  builder: (context, realsResult) {
                    var reals = realsResult.items
                        .map((item) => Map<String, dynamic>.from(item.value))
                        .toList();

                    if (_feedFilter == 1) {
                      reals = reals.where((doc) {
                        final author = doc['author'] as String?;
                        if (author == null) return false;
                        return author == me || friendIds.contains(author);
                      }).toList();
                    }

                    if (reals.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 40.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                size: 72,
                                color: Colors.white24,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Share your first PeerReal Moment',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Tap the camera button to take your PeerReal moment!😜',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: reals.length,
                      itemBuilder: (context, index) {
                        final doc = reals[index];
                        return PeerRealPostCard(
                          key: ValueKey(doc['createdAt']),
                          doc: doc,
                          showAuthorHeader: true,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

// Widget for Bottom-Navigation-Items (Helper class)
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Colors.white54;
    final fontWeight = selected ? FontWeight.w600 : FontWeight.w400;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: fontWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
