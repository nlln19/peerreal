import 'package:PeerReal/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:PeerReal/services/ditto_service.dart';
import 'package:PeerReal/services/profile_avatar_service.dart';

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
          title: const Text('Choose your name.'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter a unique name.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel.'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save.'),
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
          ok ? 'Name set to "$newName"' : '"$newName" is already taken. Try another.',
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    await DittoService.instance.init();

    final oldC = TextEditingController();
    final newC = TextEditingController();
    final new2C = TextEditingController();

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        bool busy = false;
        bool show = false;
        String? error;

        Future<void> submit(StateSetter setModalState) async {
          void safeSet(VoidCallback fn) {
            if (dialogContext.mounted) setModalState(fn);
          }

          final oldPw = oldC.text;
          final newPw = newC.text;
          final newPw2 = new2C.text;

          if (newPw != newPw2) {
            safeSet(() => error = 'New passwords do not match.');
            return;
          }
          if (newPw.length < 6) {
            safeSet(() => error = 'Password must be at least 6 characters.');
            return;
          }

          safeSet(() {
            busy = true;
            error = null;
          });

          try {
            await DittoService.instance.changePassword(
              oldPassword: oldPw,
              newPassword: newPw,
            );

            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          } catch (e) {
            final msg = e.toString();
            safeSet(() {
              if (msg.contains('WRONG_PASSWORD')) {
                error = 'Old password is incorrect';
              } else if (msg.contains('NO_PASSWORD_SET')) {
                error = 'This account has no password set yet';
              } else if (msg.contains('NOT_LOGGED_IN')) {
                error = 'You are not logged in';
              } else if (msg.contains('WEAK_PASSWORD')) {
                error = 'Password must be at least 6 characters';
              } else {
                error = 'Failed to change password: $e';
              }
            });
          } finally {
            safeSet(() => busy = false);
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Change password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: oldC,
                      obscureText: !show,
                      decoration: const InputDecoration(
                        labelText: 'Old password',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newC,
                      obscureText: !show,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: new2C,
                      obscureText: !show,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: show,
                          onChanged: busy
                              ? null
                              : (v) => setModalState(() => show = v ?? false),
                        ),
                        const Text('Show'),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel.'),
                ),
                TextButton(
                  onPressed: busy ? null : () => submit(setModalState),
                  child: busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save.'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldC.dispose();
      newC.dispose();
      new2C.dispose();
    });

    if (changed == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete account'),
          content: const Text(
            'This will delete your Profile, Friendships and all your Reals.\n\n'
            'Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel.'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete.'),
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
          ok ? 'Account deleted' : 'Failed to delete account',
        ),
      ),
    );

    if (ok) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
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
              child: const Text('Cancel.'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout.'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await DittoService.instance.logout();
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }


  Future<void> _confirmDeleteProfilePicture() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete profile picture?'),
        content: const Text(
          'This will remove your profile picture.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel.'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete.'),
            ),
        ],
      ),
    );

    if (confirmed != true) return;

    final service = DittoService.instance;
    final me = service.activeUserId;

    // Always clear local cache so UI updates immediately on this device.
    await ProfileAvatarService.clearForPeer(me);

    // If logged in, also propagate deletion via Ditto.
    if (service.isLoggedIn) {
      await service.deleteCurrentUserAvatar();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          service.isLoggedIn
              ? 'Profile picture deleted'
              : 'Profile picture removed',
        ),
      ),
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
        title: Text(
          "Settings",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
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

          // Profile picture
          ListTile(
            leading: const Icon(Icons.image_outlined, color: Colors.white),
            title: const Text(
              'Delete profile picture',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Remove your avatar.',
              style: TextStyle(color: Colors.white54),
            ),
            onTap: _confirmDeleteProfilePicture,
          ),


          // Change password
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Colors.white),
            title: const Text(
              'Change password',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Set a new password for your account.',
              style: TextStyle(color: Colors.white54),
            ),
            onTap: _changePassword,
          ),

          const Divider(color: Colors.white12),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white),
            title: const Text('Logout', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Logout from this device.',
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
              'Remove your Profile, Friendships and Reals.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }
}