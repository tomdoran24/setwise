import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

const String _baseUrl = 'https://web-production-f6e8b.up.railway.app';

class UserModel {
  final String userId;
  final String email;
  final String? name;
  final bool youtubeConnected;
  final String? spotifyToken;

  UserModel({
    required this.userId,
    required this.email,
    this.name,
    required this.youtubeConnected,
    this.spotifyToken,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        name: json['name'] as String?,
        youtubeConnected: json['youtube_connected'] as bool? ?? false,
        spotifyToken: json['spotify_token'] as String?,
      );

  String get displayName => name ?? email.split('@').first;
  String get initials {
    final parts = displayName.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return displayName.substring(0, displayName.length.clamp(0, 2)).toUpperCase();
  }
}

class AuthService {
  static const _jwtKey = 'user_jwt';

  static UserModel? currentUser;

  static String? get jwt => StorageService.get(_jwtKey);
  static bool get isLoggedIn => currentUser != null;

  static void setJwt(String token) {
    StorageService.set(_jwtKey, token);
  }

  static void signOut() {
    StorageService.remove(_jwtKey);
    currentUser = null;
  }

  /// Fetch /auth/me and populate currentUser. Returns null if not authenticated.
  static Future<UserModel?> fetchMe() async {
    final token = jwt;
    if (token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final user = UserModel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        currentUser = user;
        return user;
      }
      if (res.statusCode == 401) {
        // Token expired or invalid — clear it
        signOut();
      }
    } catch (_) {}
    return null;
  }

  static Map<String, String> get authHeaders {
    final token = jwt;
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }
}
