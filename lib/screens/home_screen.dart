import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/url_service.dart';
import '../widgets/account_button.dart';
import 'setlist_screen.dart';
import 'venue_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _navigatingFromSuggestion = false;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _handleOAuthReturn();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        // Delay so a suggestion tap (pointer-up) fires before the list disappears
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_focusNode.hasFocus) setState(() => _showSuggestions = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      _debounce?.cancel();
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _debounce?.cancel();
    // Slightly longer debounce for single-char queries to avoid rapid-fire requests
    final delay = query.length == 1 ? const Duration(milliseconds: 500) : const Duration(milliseconds: 350);
    _debounce = Timer(delay, () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    try {
      final (:results, :approximate) = await ApiService.searchArtists(query);
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _suggestions = results.cast<Map<String, dynamic>>();
        _showSuggestions = _suggestions.isNotEmpty && _focusNode.hasFocus;
      });
    } catch (_) {
      // Silently ignore suggestion errors — user can still hit the button
    }
  }

  Future<void> _handleOAuthReturn() async {
    final uri = UrlService.currentUri();

    if (uri.queryParameters['auth_error'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign-in session expired — please try again.')),
          );
        }
      });
      return;
    }

    // JWT from Google OAuth callback
    final jwt = uri.queryParameters['jwt'];
    if (jwt != null && jwt.isNotEmpty) {
      AuthService.setJwt(jwt);
      UrlService.replaceUrl('/');
    }

    // Spotify token from Spotify OAuth callback
    final spotifyTokenParam = uri.queryParameters['spotify_token'];
    if (spotifyTokenParam != null && spotifyTokenParam.isNotEmpty) {
      spotifyToken = spotifyTokenParam;
    }

    // Load user from stored JWT (covers both fresh OAuth and returning sessions)
    final user = await AuthService.fetchMe();
    if (user != null) {
      // If account has a stored Spotify token, use it
      if (user.spotifyToken != null && spotifyToken == null) {
        spotifyToken = user.spotifyToken;
      }
      if (mounted) setState(() {});
    }

    // Restore setlist screen if returning from OAuth
    final saved = StorageService.get('oauth_return');
    if (saved != null) {
      StorageService.remove('oauth_return');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final data = jsonDecode(saved) as Map<String, dynamic>;
          final rawSongs = data['songs'] as List?;
          final songs = rawSongs?.map((s) => Map<String, dynamic>.from(s as Map)).toList();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SetlistScreen(
                artist: data['artist'] as String,
                mbid: data['mbid'] as String,
                tour: data['tour'] as String?,
                imageUrl: data['imageUrl'] as String?,
                venueName: data['venueName'] as String?,
                venueCity: data['venueCity'] as String?,
                showNotListed: data['showNotListed'] as bool? ?? false,
                initialSongs: songs,
                initialMinFrequency: data['minFrequency'] as int? ?? 1,
                pendingAction: data['pendingAction'] as String?,
              ),
            ),
          );
        });
      }
    }
  }

  Future<void> _search() async {
    if (_navigatingFromSuggestion) return;
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() => _loading = true);
    try {
      final (:results, :approximate) = await ApiService.searchArtists(query);
      if (!mounted) return;

      if (results.length == 1 && !approximate) {
        _goToSetlist(results[0]['name'], results[0]['mbid'], results[0]['image_url'] as String?);
        return;
      }

      final picked = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => SimpleDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(approximate ? 'Did you mean…' : 'Select artist', style: const TextStyle(color: Colors.white)),
          children: results.map<Widget>((a) {
            final disambiguation = (a['disambiguation'] as String?) ?? '';
            final imageUrl = a['image_url'] as String?;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, a),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: ClipOval(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              color: const Color(0xFF2A2A2A),
                              child: const Icon(Icons.person, color: Colors.grey),
                            ),
                            if (imageUrl != null)
                              Image.network(
                                ApiService.artistImageProxyUrl(imageUrl),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a['name'] as String? ?? '',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (disambiguation.isNotEmpty)
                            Text(
                              disambiguation,
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );

      if (picked != null && mounted) {
        _goToSetlist(picked['name'], picked['mbid'], picked['image_url'] as String?);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg == 'No artists found' ? 'No artists found for that search.' : msg)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _suggestionPlaceholder() => Container(
    color: const Color(0xFF2A2A2A),
    child: const Icon(Icons.person, color: Colors.grey, size: 20),
  );

  Future<void> _goToSetlist(String name, String mbid, String? imageUrl) async {
    _navigatingFromSuggestion = true;
    _debounce?.cancel();
    setState(() { _showSuggestions = false; _suggestions = []; });
    _focusNode.unfocus();

    // Deezer-only results have no mbid — resolve it via a full search first
    String resolvedMbid = mbid;
    String resolvedName = name;
    String? resolvedImage = imageUrl;
    if (mbid.isEmpty) {
      try {
        final (:results, :approximate) = await ApiService.searchArtists(name);
        if (results.isNotEmpty) {
          final match = results.firstWhere(
            (r) => (r['name'] as String).toLowerCase() == name.toLowerCase(),
            orElse: () => results[0],
          );
          resolvedMbid = match['mbid'] as String? ?? '';
          resolvedName = match['name'] as String? ?? name;
          resolvedImage = match['image_url'] as String? ?? imageUrl;
        }
      } catch (_) {}
    }

    _navigatingFromSuggestion = false;
    if (!mounted || resolvedMbid.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VenueScreen(artist: resolvedName, mbid: resolvedMbid, imageUrl: resolvedImage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const SizedBox(height: 48),
                  const Text(
                    'Who are you seeing?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !_loading,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Artist name',
                      prefixIcon: Icon(Icons.search, color: Colors.grey),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _loading ? null : (_) => _search(),
                    onTap: () {
                      if (_suggestions.isNotEmpty) setState(() => _showSuggestions = true);
                    },
                  ),
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A2A2A)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _suggestions.take(5).toList().asMap().entries.map((entry) {
                          final i = entry.key;
                          final a = entry.value;
                          final imageUrl = a['image_url'] as String?;
                          final disambiguation = (a['disambiguation'] as String?) ?? '';
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (i > 0) const Divider(height: 1, color: Color(0xFF2A2A2A)),
                              InkWell(
                                borderRadius: i == 0
                                    ? const BorderRadius.vertical(top: Radius.circular(12))
                                    : i == _suggestions.length - 1
                                        ? const BorderRadius.vertical(bottom: Radius.circular(12))
                                        : BorderRadius.zero,
                                onTap: () => _goToSetlist(
                                  a['name'] as String? ?? '',
                                  (a['mbid'] as String?) ?? '',
                                  imageUrl,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      ClipOval(
                                        child: SizedBox(
                                          width: 36, height: 36,
                                          child: imageUrl != null
                                              ? Image.network(
                                                  ApiService.artistImageProxyUrl(imageUrl),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => _suggestionPlaceholder(),
                                                )
                                              : _suggestionPlaceholder(),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(a['name'] as String? ?? '',
                                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                                overflow: TextOverflow.ellipsis),
                                            if (disambiguation.isNotEmpty)
                                              Text(disambiguation,
                                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                                  overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _search,
                    child: _loading
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('Predict Setlist', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  const Text(
                    '© Setwise 2026',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: AccountButton(),
            ),
          ],
        ),
      ),
    );
  }
}
