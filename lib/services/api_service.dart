import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Runs [fn] and converts any network-level exception into a friendly message.
Future<T> _call<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } on SocketException {
    throw Exception('No internet connection — please check your network and try again.');
  } on http.ClientException {
    throw Exception('No internet connection — please check your network and try again.');
  }
}

const String _baseUrl = 'https://web-production-f6e8b.up.railway.app';

// In-memory Spotify token — populated after OAuth callback or loaded from account
String? spotifyToken;

class ApiService {
  static Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ...AuthService.authHeaders,
      };

  static Future<({List<dynamic> results, bool approximate})> searchArtists(String artist) => _call(() async {
    final uri = Uri.parse('$_baseUrl/setlists/search/${Uri.encodeComponent(artist)}');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (results: body['results'] as List<dynamic>, approximate: body['approximate'] as bool? ?? false);
    }
    if (response.statusCode == 503) throw Exception('Search service temporarily unavailable — please try again.');
    if (response.statusCode == 404) throw Exception('No artists found');
    throw Exception('Search failed');
  });

  static Future<List<dynamic>> getUpcomingShows(String mbid) => _call(() async {
    final uri = Uri.parse('$_baseUrl/setlists/upcoming/$mbid');
    final response = await http.get(uri);
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to fetch upcoming shows');
  });

  static Future<Map<String, dynamic>> getPopularSongs(String artist) => _call(() async {
    final uri = Uri.parse('$_baseUrl/predicted-set/popular/${Uri.encodeComponent(artist)}');
    final response = await http.get(uri);
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to fetch popular songs');
  });

  static Future<Map<String, dynamic>> getPredictedSet(String artist, String mbid, {String? tour}) => _call(() async {
    final params = {'mbid': mbid, if (tour != null) 'tour': tour};
    final uri = Uri.parse('$_baseUrl/predicted-set/${Uri.encodeComponent(artist)}').replace(queryParameters: params);
    final response = await http.get(uri);
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 404) throw Exception('No setlists found');
    throw Exception('Failed to fetch setlist');
  });

  // ── YouTube ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> previewYoutubePlaylist(String artist, List<String> songs) => _call(() async {
    final uri = Uri.parse('$_baseUrl/preview-youtube/${Uri.encodeComponent(artist)}');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({'songs': songs}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('not_authenticated');
    throw Exception('Failed to preview playlist');
  });

  static Future<List<dynamic>> searchYoutubeAlternatives(String q) => _call(() async {
    final uri = Uri.parse('$_baseUrl/search-youtube').replace(queryParameters: {'q': q});
    final response = await http.get(uri);
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Search failed');
  });

  static Future<Map<String, dynamic>> createPlaylist(String artist, List<String> videoIds, {String? setLabel}) => _call(() async {
    final uri = Uri.parse('$_baseUrl/create-playlist/${Uri.encodeComponent(artist)}');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({'video_ids': videoIds, if (setLabel != null) 'set_label': setLabel}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('not_authenticated');
    final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'] ?? 'Failed to create playlist';
    throw Exception(detail);
  });

  static Future<Map<String, dynamic>> createYoutubeMusicPlaylist(String artist, List<String> videoIds, {String? setLabel}) => _call(() async {
    final uri = Uri.parse('$_baseUrl/create-ytmusic-playlist/${Uri.encodeComponent(artist)}');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({'video_ids': videoIds, if (setLabel != null) 'set_label': setLabel}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('not_authenticated');
    final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'] ?? 'Failed to create playlist';
    throw Exception(detail);
  });

  // ── Spotify ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> previewSpotifyPlaylist(String artist, List<String> songs, {bool preferClean = false}) => _call(() async {
    final uri = Uri.parse('$_baseUrl/preview-spotify/${Uri.encodeComponent(artist)}');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({'songs': songs, if (spotifyToken != null) 'spotify_token': spotifyToken, 'prefer_clean': preferClean}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('not_authenticated_spotify');
    throw Exception('Failed to preview Spotify playlist');
  });

  static Future<List<dynamic>> searchSpotifyAlternatives(String q) => _call(() async {
    final params = {
      'q': q,
      if (spotifyToken != null) 'spotify_token': spotifyToken!,
    };
    final uri = Uri.parse('$_baseUrl/search-spotify').replace(queryParameters: params);
    final response = await http.get(uri, headers: AuthService.authHeaders);
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Search failed');
  });

  static Future<Map<String, dynamic>> createSpotifyPlaylist(String artist, List<String> uris, {String? setLabel}) => _call(() async {
    final uri = Uri.parse('$_baseUrl/create-spotify-playlist/${Uri.encodeComponent(artist)}');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({'uris': uris, if (setLabel != null) 'set_label': setLabel}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) {
      final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'] ?? '';
      throw Exception(detail.isNotEmpty ? detail : 'not_authenticated_spotify');
    }
    final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'] ?? 'Failed to create Spotify playlist';
    throw Exception(detail);
  });

  // ── Saved setlists ────────────────────────────────────────────────────────

  static Future<void> saveSetlist(String artistName, String mbid, List<Map<String, dynamic>> songs) => _call(() async {
    final uri = Uri.parse('$_baseUrl/setlists/saved');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({'artist_name': artistName, 'mbid': mbid, 'songs': songs}),
    );
    if (response.statusCode != 200) throw Exception('Failed to save setlist');
  });

  static Future<List<dynamic>> getSavedSetlists() => _call(() async {
    final uri = Uri.parse('$_baseUrl/setlists/saved');
    final response = await http.get(uri, headers: AuthService.authHeaders);
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('not_authenticated');
    throw Exception('Failed to load saved setlists');
  });

  static Future<void> deleteSavedSetlist(String id) => _call(() async {
    final uri = Uri.parse('$_baseUrl/setlists/saved/$id');
    final response = await http.delete(uri, headers: AuthService.authHeaders);
    if (response.statusCode != 200) throw Exception('Failed to delete setlist');
  });

  // ── Tracked artists ───────────────────────────────────────────────────────

  static Future<bool> trackArtist(String artistName, String mbid, {String? imageUrl}) => _call(() async {
    final uri = Uri.parse('$_baseUrl/artists/track');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({'artist_name': artistName, 'mbid': mbid, if (imageUrl != null) 'image_url': imageUrl}),
    );
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as Map)['already_tracked'] as bool? ?? false;
    }
    if (response.statusCode == 401) throw Exception('not_authenticated');
    throw Exception('Failed to track artist');
  });

  static Future<List<dynamic>> getTrackedArtists() => _call(() async {
    final uri = Uri.parse('$_baseUrl/artists/tracked');
    final response = await http.get(uri, headers: AuthService.authHeaders);
    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('not_authenticated');
    throw Exception('Failed to load tracked artists');
  });

  static Future<void> untrackArtist(String mbid) => _call(() async {
    final uri = Uri.parse('$_baseUrl/artists/track/$mbid');
    final response = await http.delete(uri, headers: AuthService.authHeaders);
    if (response.statusCode != 200) throw Exception('Failed to untrack artist');
  });

  // ── Upcoming shows ────────────────────────────────────────────────────────

  static Future<void> saveUpcomingShow({
    required String artistName,
    required String mbid,
    required String date,
    String? venue,
    String? city,
    String? country,
    String? tour,
  }) => _call(() async {
    final uri = Uri.parse('$_baseUrl/shows/upcoming');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'artist_name': artistName,
        'mbid': mbid,
        'date': date,
        if (venue != null) 'venue': venue,
        if (city != null) 'city': city,
        if (country != null) 'country': country,
        if (tour != null) 'tour': tour,
      }),
    );
    if (response.statusCode == 401) throw Exception('not_authenticated');
    if (response.statusCode != 200) throw Exception('Failed to save upcoming show');
  });

  static Future<List<Map<String, dynamic>>> getMyUpcomingShows() => _call(() async {
    final uri = Uri.parse('$_baseUrl/shows/upcoming');
    final response = await http.get(uri, headers: AuthService.authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.cast<Map<String, dynamic>>();
    }
    if (response.statusCode == 401) throw Exception('not_authenticated');
    throw Exception('Failed to load upcoming shows');
  });

  static Future<void> deleteUpcomingShow(String showId) => _call(() async {
    final uri = Uri.parse('$_baseUrl/shows/upcoming/$showId');
    final response = await http.delete(uri, headers: AuthService.authHeaders);
    if (response.statusCode != 200) throw Exception('Failed to delete upcoming show');
  });

  // ── Auth URLs ─────────────────────────────────────────────────────────────

  static String get authUrl => '$_baseUrl/auth/google';

  static String get spotifyAuthUrl {
    final jwt = AuthService.jwt;
    if (jwt != null) {
      return '$_baseUrl/auth/spotify?jwt=${Uri.encodeComponent(jwt)}';
    }
    return '$_baseUrl/auth/spotify';
  }

  static Future<Map<String, dynamic>> getMe() => _call(() async {
    final uri = Uri.parse('$_baseUrl/auth/me');
    final response = await http.get(uri, headers: AuthService.authHeaders);
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('not_authenticated');
  });

  static Future<void> updatePreferences({bool? preferClean}) => _call(() async {
    final uri = Uri.parse('$_baseUrl/auth/me/preferences');
    final response = await http.patch(uri,
      headers: _jsonHeaders,
      body: jsonEncode({if (preferClean != null) 'prefer_clean': preferClean}),
    );
    if (response.statusCode != 200) throw Exception('Failed to update preferences');
  });

  static Future<Map<String, dynamic>?> computeAccuracy({
    required String mbid,
    required String artistName,
    required String showDate,
    required List<String> predictedSongs,
    String? venue,
    String? city,
  }) => _call(() async {
    final uri = Uri.parse('$_baseUrl/accuracy/compute');
    final response = await http.post(uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'mbid': mbid,
        'artist_name': artistName,
        'show_date': showDate,
        'predicted_songs': predictedSongs,
        if (venue != null) 'venue': venue,
        if (city != null) 'city': city,
      }),
    );
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    return null;
  });

  static Future<List<dynamic>> getAccuracy(String mbid) => _call(() async {
    final uri = Uri.parse('$_baseUrl/accuracy/$mbid');
    final response = await http.get(uri, headers: AuthService.authHeaders);
    if (response.statusCode == 200) return jsonDecode(response.body) as List;
    return [];
  });

  static Future<void> disconnectPlatform(String platform) => _call(() async {
    final uri = Uri.parse('$_baseUrl/auth/connections/$platform');
    final response = await http.delete(uri, headers: AuthService.authHeaders);
    if (response.statusCode != 200) throw Exception('Failed to disconnect');
  });

  static String artistImageProxyUrl(String imageUrl) =>
      '$_baseUrl/setlists/image?url=${Uri.encodeComponent(imageUrl)}';
}
