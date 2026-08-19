import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../widgets/account_button.dart';
import 'export_preview_screen.dart';


class SetlistScreen extends StatefulWidget {
  final String artist;
  final String mbid;
  final String? tour;
  final String? imageUrl;
  final String? venueName;
  final String? venueCity;
  final bool showNotListed;
  final List<Map<String, dynamic>>? initialSongs;
  final int initialMinFrequency;
  final String? pendingAction;
  const SetlistScreen({super.key, required this.artist, required this.mbid, this.tour, this.imageUrl, this.venueName, this.venueCity, this.showNotListed = false, this.initialSongs, this.initialMinFrequency = 1, this.pendingAction});

  @override
  State<SetlistScreen> createState() => _SetlistScreenState();
}

bool _isLiveVersion(String name) {
  return RegExp(r'[\(\[\-,/]\s*live\s*[\)\]]?\s*$', caseSensitive: false).hasMatch(name);
}

class _SetlistScreenState extends State<SetlistScreen> {
  late Future<Map<String, dynamic>> _setlistFuture;
  bool _creatingPlaylist = false;
  bool _creatingYtMusicPlaylist = false;
  bool _creatingSpotifyPlaylist = false;

  bool get _anyExporting => _creatingPlaylist || _creatingYtMusicPlaylist || _creatingSpotifyPlaylist;
  bool _editing = false;
  bool _saving = false;
  bool _saved = false;
  bool _tracking = false;
  bool _tracked = false;
  int _minPct = 70;
  bool _staleDialogShown = false;
  List<Map<String, dynamic>>? _songs;
  Map<String, dynamic>? _dualSetlist;
  String? _dateRange;
  // 0 = set A, 1 = set B, -1 = combined
  int _activeSet = -1;

  @override
  void initState() {
    super.initState();
    _minPct = widget.initialMinFrequency > 1 ? widget.initialMinFrequency : 70;
    if (widget.initialSongs != null) {
      _songs = widget.initialSongs;
      _staleDialogShown = true; // don't re-show stale dialog on restore
      _setlistFuture = Future.value({'predicted_set': _songs, 'is_stale': false, 'most_recent_date': null});
      if (widget.pendingAction == 'spotify') {
        WidgetsBinding.instance.addPostFrameCallback((_) => _createSpotifyPlaylist());
      }
    } else {
      _setlistFuture = ApiService.getPredictedSet(widget.artist, widget.mbid, tour: widget.tour);
    }
  }

  void _saveStateForOAuth({String? pendingAction}) {
    StorageService.set('oauth_return', jsonEncode({
      'artist': widget.artist,
      'mbid': widget.mbid,
      'tour': widget.tour,
      'imageUrl': widget.imageUrl,
      'venueName': widget.venueName,
      'venueCity': widget.venueCity,
      'showNotListed': widget.showNotListed,
      'songs': _songs,
      'minFrequency': _minPct,
      if (pendingAction != null) 'pendingAction': pendingAction,
    }));
  }

  List<Map<String, dynamic>> get _activeSongs {
    if (_dualSetlist != null && _activeSet >= 0) {
      final key = _activeSet == 0 ? 'set_a' : 'set_b';
      return (_dualSetlist![key]['songs'] as List).cast<Map<String, dynamic>>();
    }
    if (_dualSetlist != null && _activeSet == -1) {
      // Combined: union of Set A and Set B, deduped by song name.
      // Frequencies are re-expressed relative to the total show pool so that
      // a song played in 2/2 Set-A shows doesn't show 99% when Set B had 8 shows.
      final showCountA = (_dualSetlist!['set_a']['show_count'] as int? ?? 0);
      final showCountB = (_dualSetlist!['set_b']['show_count'] as int? ?? 0);
      final totalShows = showCountA + showCountB;
      final setA = (_dualSetlist!['set_a']['songs'] as List).cast<Map<String, dynamic>>();
      final setB = (_dualSetlist!['set_b']['songs'] as List).cast<Map<String, dynamic>>();
      final byName = <String, Map<String, dynamic>>{};
      for (final s in setA) {
        byName[s['song'] as String] = {...s, 'frequency': s['frequency'] as int, 'out_of': totalShows};
      }
      for (final s in setB) {
        final name = s['song'] as String;
        if (byName.containsKey(name)) {
          // Appears in both sets — sum the frequencies
          byName[name] = {...byName[name]!, 'frequency': (byName[name]!['frequency'] as int) + (s['frequency'] as int), 'out_of': totalShows};
        } else {
          byName[name] = {...s, 'frequency': s['frequency'] as int, 'out_of': totalShows};
        }
      }
      return byName.values.toList();
    }
    return _songs ?? [];
  }

  List<Map<String, dynamic>> get _visibleSongs =>
      _activeSongs
          .where((s) => ((s['frequency'] as int) / (s['out_of'] as int) * 100) >= _minPct)
          .toList();

  List<String> get _visibleSongNames => _visibleSongs.map((s) => s['song'] as String).toList();

  /// Build an ordered track list from search results, flagging covers distinctly.
  List<ExportTrack> _mergeCoversIntoTracks(List<Map<String, dynamic>> results, ExportTrack Function(Map<String, dynamic>) fromResult) {
    final songs = _visibleSongs;
    final resultMap = {for (final r in results) r['song'] as String: r};
    return songs.map((s) {
      final name = s['song'] as String;
      final coverArtist = s['cover'] as String?;
      if (coverArtist != null) return ExportTrack(song: name, coverArtist: coverArtist);
      final r = resultMap[name];
      return r != null ? fromResult(r) : ExportTrack(song: name);
    }).toList();
  }

  Future<void> _createPlaylist() async {
    setState(() => _creatingPlaylist = true);
    try {
      final searchNames = _visibleSongs.where((s) => s['cover'] == null).map((s) => s['song'] as String).toList();
      final raw = await ApiService.previewYoutubePlaylist(widget.artist, searchNames);
      if (!mounted) return;
      final tracks = _mergeCoversIntoTracks(raw.cast<Map<String, dynamic>>(), ExportTrack.fromYoutube);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ExportPreviewScreen(artist: widget.artist, platform: ExportPlatform.youtube, tracks: tracks, setLabel: _dualSetlist != null && _activeSet >= 0 ? (_activeSet == 0 ? 'Set A' : 'Set B') : null),
      ));
    } on Exception catch (e) {
      if (!mounted) return;
      if (e.toString().contains('not_authenticated')) {
        _showAuthDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingPlaylist = false);
    }
  }

  Future<void> _createYtMusicPlaylist() async {
    setState(() => _creatingYtMusicPlaylist = true);
    try {
      final searchNames = _visibleSongs.where((s) => s['cover'] == null).map((s) => s['song'] as String).toList();
      final raw = await ApiService.previewYoutubePlaylist(widget.artist, searchNames);
      if (!mounted) return;
      final tracks = _mergeCoversIntoTracks(raw.cast<Map<String, dynamic>>(), ExportTrack.fromYoutube);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ExportPreviewScreen(artist: widget.artist, platform: ExportPlatform.youtubeMusic, tracks: tracks),
      ));
    } on Exception catch (e) {
      if (!mounted) return;
      if (e.toString().contains('not_authenticated')) {
        _showAuthDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingYtMusicPlaylist = false);
    }
  }

  Future<void> _createSpotifyPlaylist() async {
    setState(() => _creatingSpotifyPlaylist = true);
    try {
      final searchNames = _visibleSongs.where((s) => s['cover'] == null).map((s) => s['song'] as String).toList();
      bool preferClean = false;
      if (AuthService.isLoggedIn) {
        try {
          final me = await ApiService.getMe();
          preferClean = me['prefer_clean'] as bool? ?? false;
        } catch (_) {}
      }
      final raw = await ApiService.previewSpotifyPlaylist(widget.artist, searchNames, preferClean: preferClean);
      if (!mounted) return;
      final tracks = _mergeCoversIntoTracks(raw.cast<Map<String, dynamic>>(), ExportTrack.fromSpotify);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ExportPreviewScreen(
          artist: widget.artist,
          platform: ExportPlatform.spotify,
          tracks: tracks,
          setLabel: _dualSetlist != null && _activeSet >= 0 ? (_activeSet == 0 ? 'Set A' : 'Set B') : null,
          onNeedsSpotifyAuth: () {
            _saveStateForOAuth(pendingAction: 'spotify');
            launchUrl(Uri.parse(ApiService.spotifyAuthUrl), webOnlyWindowName: '_self');
          },
        ),
      ));
    } on Exception catch (e) {
      if (!mounted) return;
      if (e.toString().contains('not_authenticated_spotify')) {
        _saveStateForOAuth(pendingAction: 'spotify');
        await launchUrl(Uri.parse(ApiService.spotifyAuthUrl), webOnlyWindowName: '_self');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingSpotifyPlaylist = false);
    }
  }

  Future<void> _saveSetlist() async {
    if (!AuthService.isLoggedIn) {
      _showAccountPrompt('Sign in to save setlists.');
      return;
    }
    if (_songs == null || _songs!.isEmpty) return;
    setState(() => _saving = true);
    try {
      final visible = _songs!.where((s) => ((s['frequency'] as int) / (s['out_of'] as int) * 100) >= _minPct).toList();
      await ApiService.saveSetlist(widget.artist, widget.mbid, visible);
      if (mounted) setState(() { _saving = false; _saved = true; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Setlist saved!')),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save setlist')),
      );
    }
  }

  Future<void> _trackArtist() async {
    if (!AuthService.isLoggedIn) {
      _showAccountPrompt('Sign in to track artists and get notified about shows.');
      return;
    }
    setState(() => _tracking = true);
    try {
      final alreadyTracked = await ApiService.trackArtist(widget.artist, widget.mbid, imageUrl: widget.imageUrl);
      if (mounted) setState(() { _tracking = false; _tracked = true; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(alreadyTracked ? 'Already tracking ${widget.artist}' : '${widget.artist} tracked!')),
      );
    } catch (_) {
      if (mounted) setState(() => _tracking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to track artist')),
      );
    }
  }

  void _showAccountPrompt(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Sign in', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4FC3F7), foregroundColor: Colors.black),
            onPressed: () async {
              Navigator.pop(context);
              _saveStateForOAuth();
              await launchUrl(Uri.parse(ApiService.authUrl), webOnlyWindowName: '_self');
            },
            child: const Text('Sign in with Google'),
          ),
        ],
      ),
    );
  }

  void _showAuthDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign in with Google'),
        content: const Text(
          'You need to connect your Google account before creating a YouTube playlist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              _saveStateForOAuth();
              await launchUrl(
                Uri.parse(ApiService.authUrl),
                webOnlyWindowName: '_self',
              );
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          const AccountButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _setlistFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _SetlistLoadingView(artist: widget.artist, venueName: widget.venueName, venueCity: widget.venueCity, showNotListed: widget.showNotListed);
          }
          if (snapshot.hasError) {
            final msg = snapshot.error.toString().replaceFirst('Exception: ', '');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.grey, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      msg == 'No setlists found'
                          ? 'No setlist data found for ${widget.artist}.'
                          : 'Couldn\'t load the setlist. Please try again.',
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => setState(() {
                        _setlistFuture = ApiService.getPredictedSet(widget.artist, widget.mbid, tour: widget.tour);
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (_songs == null) {
            _songs = List<Map<String, dynamic>>.from(
              (snapshot.data!['predicted_set'] as List).map((s) => Map<String, dynamic>.from(s)),
            );
            final raw = snapshot.data!['dual_setlist'];
            if (raw != null) {
              _dualSetlist = Map<String, dynamic>.from(raw as Map);
              _activeSet = 0; // default to most recent era (Set A)
            }
            _dateRange = snapshot.data!['date_range'] as String?;
            // Auto-track artist silently when setlist loads
            if (AuthService.isLoggedIn) {
              ApiService.trackArtist(widget.artist, widget.mbid, imageUrl: widget.imageUrl)
                  .catchError((_) {});
            }
            WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() {}); });
          }
          final songs = _activeSongs;

          final isStale = snapshot.data!['is_stale'] as bool? ?? false;
          final mostRecentDate = snapshot.data!['most_recent_date'] as String?;

          if (isStale && !_staleDialogShown) {
            _staleDialogShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('Outdated setlist data', style: TextStyle(color: Colors.white)),
                  content: Text(
                    'The most recent ${widget.artist} setlist we have is from ${mostRecentDate ?? 'over 2 years ago'}. This prediction may not reflect their current setlist.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Use anyway', style: TextStyle(color: Colors.grey)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4FC3F7)),
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          final result = await ApiService.getPopularSongs(widget.artist);
                          setState(() {
                            _songs = List<Map<String, dynamic>>.from(
                              (result['predicted_set'] as List).map((s) => Map<String, dynamic>.from(s)),
                            );
                          });
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not load popular songs: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Show popular songs'),
                    ),
                  ],
                ),
              );
            });
          }

          return Stack(
            children: [
              AbsorbPointer(
                absorbing: _anyExporting,
                child: AnimatedOpacity(
                  opacity: _anyExporting ? 0.4 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Column(
            children: [
              if (widget.imageUrl != null)
                SizedBox(
                  width: double.infinity,
                  height: 180,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        ApiService.artistImageProxyUrl(widget.imageUrl!),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1A1A1A)),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xFF0A0A0A)],
                          ),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            widget.artist,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                color: const Color(0xFF0A0A0A),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_dualSetlist != null) ...[
                      Row(
                        children: [
                          SegmentedButton<int>(
                        style: SegmentedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A1A1A),
                          foregroundColor: Colors.grey,
                          selectedForegroundColor: Colors.white,
                          selectedBackgroundColor: const Color(0xFF2A2A2A),
                          side: const BorderSide(color: Color(0x33FFFFFF)),
                        ),
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Set A')),
                          ButtonSegment(value: 1, label: Text('Set B')),
                          ButtonSegment(value: -1, label: Text('Combined')),
                        ],
                        selected: {_activeSet},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => setState(() { _activeSet = s.first; _editing = false; }),
                      ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: '2 distinct setlists detected - export separately or combine',
                            child: const Icon(Icons.info_outline, color: Color(0xFF4FC3F7), size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    Builder(builder: (_) {
                      final count = songs.where((s) => ((s['frequency'] as int) / (s['out_of'] as int) * 100) >= _minPct).length;
                      if (_dualSetlist != null && _activeSet >= 0) {
                        final key = _activeSet == 0 ? 'set_a' : 'set_b';
                        final set = _dualSetlist![key] as Map;
                        final showCount = set['show_count'] as int? ?? 0;
                        final dateRange = set['date_range'] as String?;
                        final range = dateRange != null ? (dateRange.contains('–') ? ' between $dateRange' : ' in $dateRange') : '';
                        return Text('$count predicted songs from $showCount shows$range', style: const TextStyle(color: Colors.grey, fontSize: 12));
                      }
                      if (_dualSetlist != null && _activeSet == -1) {
                        final combinedRange = _dualSetlist!['date_range'] as String?;
                        if (combinedRange != null && combinedRange.contains('–')) {
                          final parts = combinedRange.split('–');
                          return Text('$count predicted songs from ${parts.first.trim()} to ${parts.last.trim()}', style: const TextStyle(color: Colors.grey, fontSize: 12));
                        }
                      }
                      final rangeStr = _dateRange != null ? (_dateRange!.contains('–') ? ' between $_dateRange' : ' in $_dateRange') : ' from last 10 shows';
                      return Text('$count predicted songs$rangeStr', style: const TextStyle(color: Colors.grey, fontSize: 12));
                    }),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _creatingSpotifyPlaylist ? null : _createSpotifyPlaylist,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF1DB954),
                                        overlayColor: const Color(0xFF888888),
                                        side: const BorderSide(color: Color(0x55888888)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: _creatingSpotifyPlaylist
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1DB954)))
                                          : const FaIcon(FontAwesomeIcons.spotify, size: 16, color: Color(0xFF1DB954)),
                                      label: const Text('Spotify', style: TextStyle(color: Color(0xFF888888))),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _creatingPlaylist ? null : _createPlaylist,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFFF0000),
                                        overlayColor: const Color(0xFF888888),
                                        side: const BorderSide(color: Color(0x55888888)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: _creatingPlaylist
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF0000)))
                                          : const FaIcon(FontAwesomeIcons.youtube, size: 16, color: Color(0xFFFF0000)),
                                      label: const Text('YouTube', style: TextStyle(color: Color(0xFF888888))),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _creatingYtMusicPlaylist ? null : _createYtMusicPlaylist,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFFF0000),
                                        overlayColor: const Color(0xFF888888),
                                        side: const BorderSide(color: Color(0x55888888)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: _creatingYtMusicPlaylist
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF0000)))
                                          : const FaIcon(FontAwesomeIcons.music, size: 16, color: Color(0xFFFF0000)),
                                      label: const Text('YT Music', style: TextStyle(color: Color(0xFF888888))),
                                    ),
                                    const SizedBox(width: 24),
                                  ],
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                width: 32,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [const Color(0x000A0A0A), const Color(0xFF0A0A0A)],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => setState(() => _editing = !_editing),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              overlayColor: const Color(0xFF888888),
                              side: const BorderSide(color: Color(0x55888888)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: Icon(_editing ? Icons.check : Icons.edit, size: 16, color: _editing ? const Color(0xFF4FC3F7) : const Color(0xFF888888)),
                            label: Text(_editing ? 'Done' : 'Edit', style: TextStyle(color: _editing ? const Color(0xFF4FC3F7) : const Color(0xFF888888))),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Min. probability: $_minPct%',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const Spacer(),
                        Text(
                          '${_activeSongs.where((s) => ((s['frequency'] as int) / (s['out_of'] as int) * 100) >= _minPct).length} songs',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF4FC3F7),
                        inactiveTrackColor: const Color(0xFF333333),
                        thumbColor: const Color(0xFF4FC3F7),
                        overlayColor: const Color(0x224FC3F7),
                        trackHeight: 2,
                      ),
                      child: Slider(
                        value: _minPct.toDouble(),
                        min: 10,
                        max: 100,
                        divisions: 9,
                        onChanged: (v) => setState(() => _minPct = v.round()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_editing)
                      const Padding(
                        padding: EdgeInsets.only(left: 40, right: 16),
                        child: Row(
                          children: [
                            Text('Name', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                            Spacer(),
                            Text('Probability', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Expanded(
                child: _editing
                    ? Builder(builder: (context) {
                        final visible = songs.where((s) => ((s['frequency'] as int) / (s['out_of'] as int) * 100) >= _minPct).toList();
                        return ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        buildDefaultDragHandles: false,
                        itemCount: visible.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            final item = visible.removeAt(oldIndex);
                            visible.insert(newIndex, item);
                            // Splice reordered visible songs back, filtered songs go to end
                            final hidden = songs.where((s) => ((s['frequency'] as int) / (s['out_of'] as int) * 100) < _minPct).toList();
                            _songs = [...visible, ...hidden];
                          });
                        },
                        itemBuilder: (context, index) {
                          final song = visible[index];
                          return Container(
                            key: ValueKey('${song['song']}_$index'),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle, color: Colors.grey),
                              ),
                              title: Row(
                                children: [
                                  Flexible(child: Text(song['song'], style: const TextStyle(color: Colors.white))),
                                  if (_isLiveVersion(song['song'] as String)) ...[
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'This may be a live recording version',
                                      child: const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFFB300)),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: song['cover'] != null
                                  ? Text('Cover · ${song['cover']}', style: const TextStyle(color: Colors.grey, fontSize: 12))
                                  : song['collab'] != null
                                      ? Text('${song['collab']}', style: const TextStyle(color: Colors.grey, fontSize: 12))
                                      : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Builder(builder: (_) {
                                    final freq = song['frequency'] as int;
                                    final outOf = song['out_of'] as int;
                                    final pct = ((freq / outOf) * 100).round().clamp(1, 99);
                                    final color = pct >= 70 ? const Color(0xFF4CAF50) : pct >= 40 ? const Color(0xFFFFB300) : const Color(0xFFE53935);
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text('$pct%', style: TextStyle(color: color, fontSize: 12)),
                                    );
                                  }),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                    onPressed: () => setState(() => _songs!.remove(visible[index])),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                      })
                    : Builder(builder: (context) {
                        final visible = songs.where((s) => ((s['frequency'] as int) / (s['out_of'] as int) * 100) >= _minPct).toList();
                        return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final song = visible[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Builder(builder: (_) {
                              final freq = song['frequency'] as int;
                              final outOf = song['out_of'] as int;
                              final pct2 = ((freq / outOf) * 100).round().clamp(1, 99);
                              final color = pct2 >= 70
                                  ? const Color(0xFF4CAF50)
                                  : pct2 >= 40
                                      ? const Color(0xFFFFB300)
                                      : const Color(0xFFE53935);
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: Text('${index + 1}', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(child: Text(song['song'], style: const TextStyle(color: Colors.white))),
                                              if (_isLiveVersion(song['song'] as String)) ...[
                                                const SizedBox(width: 6),
                                                Tooltip(
                                                  message: 'This may be a live recording version',
                                                  child: const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFFB300)),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (song['cover'] != null)
                                            Text('Cover · ${song['cover']}', style: const TextStyle(color: Colors.grey, fontSize: 12))
                                          else if (song['collab'] != null)
                                            Text('${song['collab']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$pct2%',
                                        style: TextStyle(color: color, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          );
                        },
                        );
                      }),
              ),
            ],
          ),   // Column
                  ),  // AnimatedOpacity
                ),  // AbsorbPointer
              if (_anyExporting)
                const Positioned.fill(
                  child: _ExportLoadingOverlay(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ExportLoadingOverlay extends StatefulWidget {
  const _ExportLoadingOverlay();

  @override
  State<_ExportLoadingOverlay> createState() => _ExportLoadingOverlayState();
}

class _ExportLoadingOverlayState extends State<_ExportLoadingOverlay> {
  static const _messages = [
    "We're just building this playlist for you…",
    "Finding your songs…",
    "Almost there…",
    "Matching tracks…",
    "Won't be long now…",
    "Just a few more seconds…",
  ];

  int _index = 0;
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      setState(() => _visible = false);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() { _index = (_index + 1) % _messages.length; _visible = true; });
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF4FC3F7)),
              const SizedBox(height: 32),
              AnimatedOpacity(
                opacity: _visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _messages[_index],
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetlistLoadingView extends StatefulWidget {
  final String artist;
  final String? venueName;
  final String? venueCity;
  final bool showNotListed;
  const _SetlistLoadingView({required this.artist, this.venueName, this.venueCity, this.showNotListed = false});

  @override
  State<_SetlistLoadingView> createState() => _SetlistLoadingViewState();
}

class _SetlistLoadingViewState extends State<_SetlistLoadingView> {
  List<String> get _messages {
    final artist = widget.artist;
    final venue = widget.venueName;
    final city = widget.venueCity;
    final String firstMessage;
    if (venue != null && !widget.showNotListed) {
      final location = city != null ? '$venue, $city' : venue;
      firstMessage = 'Nice! We can predict what $artist will play at $location based on previous setlists';
    } else {
      firstMessage = 'Nice! We can predict what $artist will play based on previous setlists';
    }
    return [
      firstMessage,
      'Digging through recent shows…',
      'Crunching the numbers…',
      'Almost there — the setlist will be ready in a second!',
      'Ranking songs by how often they play them…',
      "Won't be long now…",
    ];
  }

  int _index = 0;
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      setState(() => _visible = false);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() { _index = (_index + 1) % _messages.length; _visible = true; });
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF4FC3F7)),
            const SizedBox(height: 32),
            AnimatedOpacity(
              opacity: _visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Text(
                _messages[_index],
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
