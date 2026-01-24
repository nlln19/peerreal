import 'package:PeerReal/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PeerReal extends StatelessWidget {
  const PeerReal({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "PeerReal",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.white,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: TextTheme(
          displayLarge: const TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.bold,
          ),
          titleLarge: GoogleFonts.inter(fontSize: 30),
          bodyMedium: GoogleFonts.inter(),
          bodySmall: GoogleFonts.inter(),
        ),
      ),

      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}