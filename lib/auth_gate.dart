import 'package:PeerReal/screens/auth_screen.dart';
import 'package:PeerReal/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:PeerReal/services/ditto_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<void> _load = DittoService.instance.loadSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: SizedBox.shrink());
        }
        return DittoService.instance.isLoggedIn
            ? const HomeScreen()
            : AuthScreen(onAuthenticated: () => setState(() {}));
      },
    );
  }
}
