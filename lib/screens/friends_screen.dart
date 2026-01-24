import 'package:PeerReal/screens/friend_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:ditto_live/ditto_live.dart';
import '../services/dql_builder_service.dart';
import '../services/ditto_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  int _tabIndex = 0; // 0 = Friends, 1 = Requests
  String _searchTerm = '';

  @override
  Widget build(BuildContext context) {
    final ditto = DittoService.instance.ditto;
    final me = DittoService.instance.activeUserId;

    return Scaffold(
      backgroundColor: const Color(0xFF05050A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05050A),
        elevation: 0,
        title: const Text('Friends'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FriendsTabButton(
                label: 'Friends',
                selected: _tabIndex == 0,
                onTap: () => setState(() => _tabIndex = 0),
              ),
              const SizedBox(width: 8),
              _FriendsTabButton(
                label: 'Requests',
                selected: _tabIndex == 1,
                onTap: () => setState(() => _tabIndex = 1),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _tabIndex == 0
                    ? 'Search for friends or users'
                    : 'Search in requests',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF11111A),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchTerm = value.trim().toLowerCase();
                });
              },
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: _tabIndex == 0
                ? (_searchTerm.isEmpty
                      ? _buildFriendsList(ditto, me)
                      : _buildProfileSearchResults(ditto, me))
                : _buildRequestsList(ditto, me),
          ),
        ],
      ),
    );
  }

  String _otherPeerId(Map<String, dynamic> friendship, String me) {
    final from = friendship['fromPeerId'] as String?;
    final to = friendship['toPeerId'] as String?;
    if (from == null || to == null) return 'Unknown';
    return from == me ? to : from;
  }

  Widget _buildFriendsList(Ditto ditto, String me) {
    return DqlBuilderService(
      ditto: ditto,
      query: '''
        SELECT * FROM friendships
        WHERE status = 'accepted'
          AND (fromPeerId = :me OR toPeerId = :me)
        ORDER BY updatedAt DESC
      ''',
      queryArgs: {'me': me},
      builder: (context, result) {
        final friends = result.items
            .map((item) => Map<String, dynamic>.from(item.value))
            .toList();

        if (friends.isEmpty) {
          return const Center(
            child: Text(
              'No friends added yet.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return ListView.separated(
          itemCount: friends.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Colors.white10, height: 1),
          itemBuilder: (context, index) {
            final friendship = friends[index];
            final otherId = _otherPeerId(friendship, me);

            return FutureBuilder<String>(
              future: DittoService.instance.getDisplayNameForPeer(otherId),
              builder: (context, snap) {
                final displayName = snap.data ?? otherId;

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.white12,
                    child: Icon(Icons.person, color: Colors.white70),
                  ),
                  title: Text(
                    displayName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Tap to view profile',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FriendProfileScreen(
                          peerId: otherId,
                          initialDisplayName: displayName,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildProfileSearchResults(Ditto ditto, String me) {
    return DqlBuilderService(
      ditto: ditto,
      query: '''
      SELECT * FROM profiles
      ORDER BY displayName ASC
    ''',
      builder: (context, result) {
        var profiles = result.items
            .map((item) => Map<String, dynamic>.from(item.value))
            .toList();

        profiles.removeWhere((p) => p['peerId'] == me || p['_id'] == me);

        if (_searchTerm.isNotEmpty) {
          profiles = profiles.where((p) {
            final name = (p['displayName'] as String? ?? '').toLowerCase();
            return name.contains(_searchTerm);
          }).toList();
        }

        if (profiles.isEmpty) {
          return const Center(
            child: Text(
              'No users found.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return ListView.separated(
          itemCount: profiles.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Colors.white10, height: 1),
          itemBuilder: (context, index) {
            final p = profiles[index];

            final peerId =
                (p['peerId'] as String?) ?? (p['_id'] as String?) ?? '';
            final name = p['displayName'] as String? ?? peerId;

            return FutureBuilder<String>(
              future: DittoService.instance.getFriendshipStatusWith(peerId),
              builder: (context, snap) {
                final status = snap.data;

                Widget trailing;
                VoidCallback? onPressed;

                if (status == null) {
                  trailing = const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white54),
                    ),
                  );
                } else if (status == 'accepted') {
                  trailing = const Text(
                    'Friends',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                } else if (status == 'pending') {
                  trailing = const Text(
                    'Requested',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                } else {
                  trailing = const Icon(
                    Icons.person_add_alt_1,
                    color: Colors.greenAccent,
                  );
                  onPressed = () async {
                    await DittoService.instance.sendFriendRequest(peerId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Friend request sent to $name')),
                      );
                    }
                    setState(() {});
                  };
                }

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.white12,
                    child: Icon(Icons.person, color: Colors.white70),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    peerId,
                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: trailing is Icon
                        ? trailing
                        : const Icon(Icons.person),
                    onPressed: onPressed,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FriendProfileScreen(
                          peerId: peerId,
                          initialDisplayName: name,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsList(Ditto ditto, String me) {
    return DqlBuilderService(
      ditto: ditto,
      query: '''
      SELECT * FROM friendships
      WHERE toPeerId = :me AND status = 'pending'
      ORDER BY createdAt DESC
    ''',
      queryArgs: {'me': me},
      builder: (context, result) {
        var requests = result.items
            .map((item) => Map<String, dynamic>.from(item.value))
            .toList();

        if (requests.isEmpty) {
          return const Center(
            child: Text(
              'No requests received.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return ListView.separated(
          itemCount: requests.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Colors.white10, height: 1),
          itemBuilder: (context, index) {
            final req = requests[index];
            final fromPeerId = req['fromPeerId'] as String? ?? 'Unknown';
            final friendshipId = req['_id'] as String?;

            return FutureBuilder<String>(
              future: DittoService.instance.getDisplayNameForPeer(fromPeerId),
              builder: (context, snap) {
                final name = snap.data ?? fromPeerId;

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.white12,
                    child: Icon(Icons.person_add, color: Colors.white70),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'sent you a friend request',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Decline
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.redAccent),
                        onPressed: friendshipId == null
                            ? null
                            : () async {
                                await DittoService.instance
                                    .declineFriendRequest(friendshipId);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Declined request from $name',
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                      // Accept
                      IconButton(
                        icon: const Icon(
                          Icons.check,
                          color: Colors.greenAccent,
                        ),
                        onPressed: friendshipId == null
                            ? null
                            : () async {
                                await DittoService.instance.acceptFriendRequest(
                                  friendshipId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'You are now friends with $name',
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FriendsTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FriendsTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = selected ? Colors.white : const Color(0xFF11111A);
    final textColor = selected ? Colors.black : Colors.white70;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}