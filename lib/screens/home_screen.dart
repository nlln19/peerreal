import 'dart:async';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/cupertino.dart';
import 'dart:typed_data';

import '../services/daily_window_service.dart';
import '../widgets/next_post_timer.dart';
import 'package:flutter/material.dart';
import '../services/dql_builder_service.dart';
import '../services/ditto_service.dart';
import '../services/profile_avatar_service.dart';
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
  String? _currentWindowId;
  Uint8List? _profileAvatarBytes;
  Timer? _windowCheckTimer;

  @override
  void initState() {
    super.initState();
    logger.i('🏠 HomeScreen initState called');
    _init();
    _startWindowChecker();
  }

  void _startWindowChecker() {
    logger.i('⏰ Starting window checker timer (10 sec for testing)...');

    // Check every 10 seconds for testing (change to 1 minute for production)
    _windowCheckTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      logger.i('⏰ Timer tick #${timer.tick} - checking for window change...');

      // Check if we should start a new window
      final shouldStart = await DailyWindowService.instance
          .shouldStartNewWindow();

      if (shouldStart) {
        logger.i('🔄 Should start new window! Triggering...');
        await DailyWindowService.instance.startNewWindow();

        // Reload the window ID
        final newWindowId = await DittoService.instance
            .getCurrentDailyWindowId();
        if (mounted && newWindowId != _currentWindowId) {
          setState(() {
            _currentWindowId = newWindowId;
          });
        }
      } else {
        // Just log current window
        final currentWindowId = await DittoService.instance
            .getCurrentDailyWindowId();
        logger.i('⏸️ Window unchanged: $currentWindowId');
      }
    });

    logger.i('✅ Window checker timer started');
  }

  Future<void> _init() async {
    logger.i('🔄 HomeScreen _init started');
    await PermissionService.requestP2PPermissions();
    final ditto = await DittoService.instance.init();
    final windowId = await DittoService.instance.getCurrentDailyWindowId();
    logger.i('📅 Initial window ID: $windowId');
    if (!mounted) return;
    setState(() {
      _ditto = ditto;
      _currentWindowId = windowId;
    });
    logger.i('✅ HomeScreen _init complete');
  }

  Future<Uint8List?> _loadMyAvatar() async {
    final service = DittoService.instance;
    final me = service.activeUserId;

    Uint8List? bytes;
    if (service.isLoggedIn) {
      bytes = await service.getAvatarBytesForPeer(me);
      if (bytes != null) {
        await ProfileAvatarService.saveForPeer(me, bytes);
      }
    }

    bytes ??= await ProfileAvatarService.loadForPeer(me);
    return bytes;
  }

  void _startAvatarObserver() {
    final service = DittoService.instance;
    if (!service.isLoggedIn) return;

    final me = service.activeUserId;

    try {
      service.ditto.store.registerObserver(
        '''
        SELECT avatar FROM profiles
        WHERE peerId = :id
        ORDER BY createdAt DESC
        LIMIT 1
        ''',
        arguments: {'id': me},
      );
    } catch (e) {
      logger.e('❌ Failed to start avatar observer: $e');
    }
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

  Future<void> _openProfile() async {
    logger.i('👤 Profile tapped');
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );

    final avatar = await _loadMyAvatar();
    if (!mounted) return;
    setState(() => _profileAvatarBytes = avatar);
  }

  Widget _profileNavIcon(bool selected) {
    final borderColor = selected ? Colors.white : Colors.white54;

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: ClipOval(
        child: _profileAvatarBytes != null
            ? Image.memory(_profileAvatarBytes!, fit: BoxFit.cover)
            : Icon(Icons.person_outline, size: 16, color: borderColor),
      ),
    );
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

    if (_ditto == null || _currentWindowId == null) {
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
        automaticallyImplyLeading: false,

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

        flexibleSpace: SafeArea(
          bottom: false,
          child: SizedBox(
            height: kToolbarHeight,
            child: Stack(
              children: const [
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: NextPostTimer(compact: true, showBackground: false),
                  ),
                ),
                Center(
                  child: Text(
                    'PeerReal.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
                iconWidget: _profileNavIcon(false),
                label: 'Profile',
                selected: false,
                onTap: _openProfile,
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
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
                    WHERE dailyWindowId = :windowId
                    ORDER BY createdAt DESC
                  ''',
                  queryArgs: {'windowId': _currentWindowId!},
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
                                'No moments yet today',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Be the first to share a moment today! 📸',
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
  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _BottomNavItem({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.selected,
    this.onTap,
  }) : assert(icon != null || iconWidget != null);

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
            iconWidget ?? Icon(icon!, color: color, size: 22),
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
