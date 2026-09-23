import 'package:flutter/services.dart';

class SecureTokenBridge {
  SecureTokenBridge._();

  static const _channel = MethodChannel('notes.ecosystem/secure');

  static Future<void> saveGitHubToken(String token) =>
      _channel.invokeMethod<void>('saveGitHubToken', token);

  static Future<String?> readGitHubToken() =>
      _channel.invokeMethod<String>('readGitHubToken');

  static Future<void> deleteGitHubToken() =>
      _channel.invokeMethod<void>('deleteGitHubToken');
}
