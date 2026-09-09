import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A simple local fallback for secure storage on Linux systems without a Secret Service.
/// This uses a machine-derived key to encrypt values before storing them in SharedPreferences.
///
/// WARNING: This is a best-effort security measure for local development.
/// For production, a system-level keyring is always preferred.
class LocalSecureStore {
  LocalSecureStore._();

  static const _storagePrefix = 'ls_enc_';

  /// Derives a stable key based on the environment.
  /// In a production app, this would combine multiple hardware IDs.
  static String _getMachineKey() {
    // We use a stable string combined with the host name as a basic machine identifier.
    // This ensures the key is persistent across restarts but different across machines.
    final host = Platform.localHostname;
    final salt = 'cerebrum_local_secret_salt_2026';
    final bytes = utf8.encode('$host$salt');
    return sha256.convert(bytes).toString();
  }

  /// Simple XOR-based "encryption" for the fallback.
  /// Since we are already in a 'fallback' scenario for dev/minimalist setups,
  /// we use a basic symmetric transformation to avoid adding heavy native dependencies
  /// while still preventing plaintext visibility.
  static String _transform(String data, String key) {
    final dataBytes = utf8.encode(data);
    final keyBytes = utf8.encode(key);
    final result = List<int>.filled(dataBytes.length, 0);

    for (int i = 0; i < dataBytes.length; i++) {
      result[i] = dataBytes[i] ^ keyBytes[i % keyBytes.length];
    }

    return base64.encode(result);
  }

  static String _untransform(String encoded, String key) {
    final decoded = base64.decode(encoded);
    final keyBytes = utf8.encode(key);
    final result = List<int>.filled(decoded.length, 0);

    for (int i = 0; i < decoded.length; i++) {
      result[i] = decoded[i] ^ keyBytes[i % keyBytes.length];
    }

    return utf8.decode(result);
  }

  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedValue = prefs.getString('$_storagePrefix$key');
    if (encryptedValue == null) return null;

    try {
      return _untransform(encryptedValue, _getMachineKey());
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('$_storagePrefix$key');
      return;
    }

    final encryptedValue = _transform(value, _getMachineKey());
    await prefs.setString('$_storagePrefix$key', encryptedValue);
  }
}
