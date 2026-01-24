import 'package:PeerReal/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:PeerReal/services/ditto_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _currentName;

  @override
  void initState() {
    super.initState();
    _currentName = DittoService.instance.displayName;
  }

  Future<void> _changeDisplayName() async {
    final controller = TextEditingController(text: _currentName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose your name'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter a unique name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty) return;

    final ok = await DittoService.instance.setDisplayName(newName);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _currentName = newName;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Name set to "$newName"' : 'Name "$newName" is already taken',
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete account'),
          content: const Text(
            'This will delete your profile, friendships and all your Reals on this device.\n\n'
            'Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => {Navigator.pop(context, true)},
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final ok = await DittoService.instance.deleteAccountAndData();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Account deleted on this device' : 'Failed to delete account',
        ),
      ),
    );

    if (ok) {
      await DittoService.instance.deleteAccountAndData();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text(
            'You will logout of this device.\n\n'
            'Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await DittoService.instance.logout();
    if (!mounted) return;

    // Clear the navigation stack and go back to the auth flow.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nameLabel = _currentName ?? 'not set yet';

    return Scaffold(
      backgroundColor: const Color(0xFF05050A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05050A),
        elevation: 0,
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // Display name
          ListTile(
            leading: const Icon(Icons.person_outline, color: Colors.white),
            title: const Text(
              'Display name',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              nameLabel,
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: const Icon(Icons.edit, color: Colors.white70),
            onTap: _changeDisplayName,
          ),

          const Divider(color: Colors.white12),

          // Delete account
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white),
            title: const Text('Logout', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Logout from this device',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: _confirmLogout,
          ),

          const Divider(color: Colors.white12),

          // Delete account
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text(
              'Delete Account',
              style: TextStyle(color: Colors.redAccent),
            ),
            subtitle: const Text(
              'Remove your profile, friendships and Reals on this device',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }
}
