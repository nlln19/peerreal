import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class PasswordHasher {
  static const int _iterations = 120000;
  static const int _bits = 256;
  static const int _saltLen = 16;

  static final _rng = Random.secure();

  static List<int> _randomSalt() =>
      List<int>.generate(_saltLen, (_) => _rng.nextInt(256));

  static Future<Map<String, dynamic>> hashPassword(String password) async {
    final salt = _randomSalt();

    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: _bits,
    );

    final key = await kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final bytes = await key.extractBytes();

    return {
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _iterations,
      'bits': _bits,
      'saltB64': base64UrlEncode(salt),
      'hashB64': base64UrlEncode(bytes),
    };
  }

  static Future<bool> verifyPassword(
    String password,
    Map<String, dynamic> stored,
  ) async {
    final salt = base64Url.decode(stored['saltB64'] as String);
    final iterations = stored['iterations'] as int? ?? _iterations;
    final bits = stored['bits'] as int? ?? _bits;

    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: bits,
    );

    final key = await kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final bytes = await key.extractBytes();

    final expected = base64Url.decode(stored['hashB64'] as String);
    if (bytes.length != expected.length) return false;

    var diff = 0;
    for (var i = 0; i < bytes.length; i++) {
      diff |= bytes[i] ^ expected[i];
    }
    return diff == 0;
  }
}
