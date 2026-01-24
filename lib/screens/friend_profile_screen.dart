import 'package:PeerReal/services/dql_builder_service.dart';
import 'package:PeerReal/widgets/peer_real_post_card.dart';
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

  @override
  void initState() {
    super.initState();
    _displayName = widget.initialDisplayName;
    _loadProfile();
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

  @override
  Widget build(BuildContext context) {
    final name = _displayName ?? 'Loading…';
    final handle = '@${widget.peerId.substring(0, 8)}';

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
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white12,
                  child: Icon(Icons.person, size: 32, color: Colors.white70),
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