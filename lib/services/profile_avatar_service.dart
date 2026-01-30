import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class ProfileAvatarService {
  static String _keyForPeer(String peerId) =>
      'peerreal.profile_avatar_b64.$peerId';

  static Future<Uint8List?> loadForPeer(String peerId) async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString(_keyForPeer(peerId));
    if (b64 == null || b64.isEmpty) return null;

    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveForPeer(String peerId, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForPeer(peerId), base64Encode(bytes));
  }

  static Future<void> clearForPeer(String peerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForPeer(peerId));
  }
}
