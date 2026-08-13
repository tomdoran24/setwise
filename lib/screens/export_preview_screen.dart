import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

enum ExportPlatform { youtube, youtubeMusic, spotify }

class ExportTrack {
  final String song;
  final String? coverArtist; // non-null = this song is a cover
  String? id; // video_id for YouTube, uri for Spotify
  String? title;
  String? thumbnailUrl;
  String? artistName; // Spotify only

  ExportTrack({
    required this.song,
    this.coverArtist,
    this.id,
    this.title,
    this.thumbnailUrl,
    this.artistName,
  });

  bool get found => id != null;
  bool get isCover => coverArtist != null;

  factory ExportTrack.fromYoutube(Map<String, dynamic> data) => ExportTrack(
        song: data['song'] as String,
        id: data['video_id'] as String?,
        title: data['title'] as String?,
        thumbnailUrl: data['thumbnail'] as String?,
      );

  factory ExportTrack.fromSpotify(Map<String, dynamic> data) => ExportTrack(
        song: data['song'] as String,
        id: data['uri'] as String?,
        title: data['title'] as String?,
        thumbnailUrl: data['album_art'] as String?,
        artistName: data['artist'] as String?,
      );
}

class ExportPreviewScreen extends StatefulWidget {
  final String artist;
  final ExportPlatform platform;
  final List<ExportTrack> tracks;
  final VoidCallback? onNeedsSpotifyAuth;
  final String? setLabel;

  const ExportPreviewScreen({
    super.key,
    required this.artist,
    required this.platform,
    required this.tracks,
    this.onNeedsSpotifyAuth,
    this.setLabel,
  });

  @override
  State<ExportPreviewScreen> createState() => _ExportPreviewScreenState();
}

class _ExportPreviewScreenState extends State<ExportPreviewScreen> {
  late List<ExportTrack> _tracks;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _tracks = List.from(widget.tracks);
  }

  bool get _isYoutube => widget.platform == ExportPlatform.youtube;
  bool get _isYoutubeMusic => widget.platform == ExportPlatform.youtubeMusic;

  Color get _platformColor => switch (widget.platform) {
    ExportPlatform.youtube => const Color(0xFFFF0000),
    ExportPlatform.youtubeMusic => const Color(0xFFFF0000),
    ExportPlatform.spotify => const Color(0xFF1DB954),
  };

  IconData get _platformIcon => switch (widget.platform) {
    ExportPlatform.youtube => FontAwesomeIcons.youtube,
    ExportPlatform.youtubeMusic => FontAwesomeIcons.music,
    ExportPlatform.spotify => FontAwesomeIcons.spotify,
  };

  Future<void> _showReplaceSheet(int index) async {
    final track = _tracks[index];
    final controller = TextEditingController(text: '${widget.artist} ${track.song}');
    List<ExportTrack> alternatives = [];
    bool searching = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Replace "${track.song}"',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search…',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    onSubmitted: (_) async {
                      setSheet(() => searching = true);
                      try {
                        final raw = _isYoutube
                            ? await ApiService.searchYoutubeAlternatives(controller.text.trim())
                            : await ApiService.searchSpotifyAlternatives(controller.text.trim());
                        setSheet(() {
                          alternatives = _isYoutube
                              ? raw.map((r) => ExportTrack.fromYoutube(Map<String, dynamic>.from(r as Map)..['song'] = track.song)).toList()
                              : raw.map((r) => ExportTrack.fromSpotify(Map<String, dynamic>.from(r as Map)..['song'] = track.song)).toList();
                          searching = false;
                        });
                      } catch (_) {
                        setSheet(() => searching = false);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: searching
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search, color: Colors.white),
                  onPressed: searching ? null : () async {
                    setSheet(() => searching = true);
                    try {
                      final raw = _isYoutube
                          ? await ApiService.searchYoutubeAlternatives(controller.text.trim())
                          : await ApiService.searchSpotifyAlternatives(controller.text.trim());
                      setSheet(() {
                        alternatives = _isYoutube
                            ? raw.map((r) => ExportTrack.fromYoutube(Map<String, dynamic>.from(r as Map)..['song'] = track.song)).toList()
                            : raw.map((r) => ExportTrack.fromSpotify(Map<String, dynamic>.from(r as Map)..['song'] = track.song)).toList();
                        searching = false;
                      });
                    } catch (_) {
                      setSheet(() => searching = false);
                    }
                  },
                ),
              ]),
              const SizedBox(height: 8),
              ...alternatives.map((alt) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Thumbnail(url: alt.thumbnailUrl, size: 48),
                title: Text(alt.title ?? '', style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: alt.artistName != null
                    ? Text(alt.artistName!, style: const TextStyle(color: Colors.grey, fontSize: 12))
                    : null,
                onTap: () {
                  setState(() => _tracks[index] = alt);
                  Navigator.pop(ctx);
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createPlaylist() async {
    final found = _tracks.where((t) => t.found).toList();
    final missing = _tracks.where((t) => !t.found && !t.isCover).toList();
    final covers = _tracks.where((t) => t.isCover).toList();

    if (found.isEmpty && covers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks found — try replacing them manually.')),
      );
      return;
    }

    // Show combined dialog if there are covers or missing tracks
    List<ExportTrack> confirmed = List.from(found);
    if (covers.isNotEmpty || missing.isNotEmpty) {
      final platform = (_isYoutube || _isYoutubeMusic) ? 'YouTube Music' : 'Spotify';
      final coverIncluded = {for (final c in covers) c.song: false};

      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Before you continue', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (covers.isNotEmpty) ...[
                    const Text('These songs look like covers — include the original or exclude?',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...covers.map((t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t.song} · ${t.coverArtist}',
                                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                                const Text('Original version will be added',
                                    style: TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ToggleButtons(
                            isSelected: [coverIncluded[t.song]!, !coverIncluded[t.song]!],
                            onPressed: (i) => setDialog(() => coverIncluded[t.song] = i == 0),
                            borderRadius: BorderRadius.circular(8),
                            selectedColor: Colors.black,
                            fillColor: const Color(0xFF4FC3F7),
                            color: Colors.grey,
                            borderColor: const Color(0xFF3A3A3A),
                            selectedBorderColor: const Color(0xFF4FC3F7),
                            constraints: const BoxConstraints(minHeight: 30, minWidth: 64),
                            children: const [
                              Text('Include', style: TextStyle(fontSize: 11)),
                              Text('Exclude', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    )),
                  ],
                  if (covers.isNotEmpty && missing.isNotEmpty)
                    const Divider(color: Color(0xFF2A2A2A), height: 24),
                  if (missing.isNotEmpty) ...[
                    Text(
                      '${missing.length} track${missing.length == 1 ? '' : 's'} couldn\'t be identified on $platform and will be skipped:',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    ...missing.map((t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• ${t.song}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    )),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4FC3F7), foregroundColor: Colors.black),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Continue'),
              ),
            ],
          ),
        ),
      );
      if (proceed != true) return;

      // Add included covers to the track list as not-found (user can replace manually)
      for (final t in covers) {
        if (coverIncluded[t.song] == true) confirmed.add(t);
      }
    }

    setState(() => _creating = true);
    try {
      final Map<String, dynamic> result;
      final ids = confirmed.where((t) => t.found).map((t) => t.id!).toList();
      if (ids.isEmpty) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tracks to add — use the replace button to find covers manually.')),
        );
        return;
      }
      if (_isYoutube) {
        result = await ApiService.createPlaylist(widget.artist, ids, setLabel: widget.setLabel);
      } else if (_isYoutubeMusic) {
        result = await ApiService.createYoutubeMusicPlaylist(widget.artist, ids, setLabel: widget.setLabel);
      } else {
        result = await ApiService.createSpotifyPlaylist(widget.artist, ids, setLabel: widget.setLabel);
      }

      final url = result['playlist_url'] as String;
      final added = result['songs_added'] as int;
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Row(children: [
            FaIcon(_platformIcon, size: 18, color: _platformColor),
            const SizedBox(width: 10),
            const Text('Playlist created!', style: TextStyle(color: Colors.white)),
          ]),
          content: Text('$added songs added to your ${_isYoutube ? 'YouTube' : _isYoutubeMusic ? 'YouTube Music' : 'Spotify'} playlist.',
              style: const TextStyle(color: Colors.grey)),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context); // dismiss dialog
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.grey),
              ),
              child: const Text('Done'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context); // dismiss dialog
                Navigator.popUntil(context, (route) => route.isFirst);
                launchUrl(Uri.parse(url));
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.grey),
              ),
              child: Text('Open in ${_isYoutube ? 'YouTube' : _isYoutubeMusic ? 'YouTube Music' : 'Spotify'}'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.startsWith('not_authenticated_spotify') && !msg.contains(':')) {
        Navigator.pop(context);
        widget.onNeedsSpotifyAuth?.call();
        return;
      }
      // not_authenticated_spotify with detail = Spotify rejected the request; show it
      if (msg.contains('not_authenticated_spotify')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 10),
        ));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foundCount = _tracks.where((t) => t.found || t.isCover).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: Row(children: [
          FaIcon(_platformIcon, size: 18, color: _platformColor),
          const SizedBox(width: 10),
          const Text('Review Playlist'),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: (_creating || foundCount == 0) ? null : _createPlaylist,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.black,
                minimumSize: const Size(90, 36),
              ),
              child: _creating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Create ($foundCount)'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _tracks.length,
        separatorBuilder: (_, __) => const Divider(color: Color(0xFF2A2A2A), height: 1),
        itemBuilder: (context, index) {
          final track = _tracks[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                _Thumbnail(url: track.thumbnailUrl, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.song,
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      track.found
                          ? Text(track.title ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                              maxLines: 2, overflow: TextOverflow.ellipsis)
                          : track.isCover
                              ? Text('Cover · ${track.coverArtist}',
                                  style: const TextStyle(color: Color(0xFFFFB300), fontSize: 13))
                              : const Text('Not found', style: TextStyle(color: Colors.red, fontSize: 13)),
                      if (track.artistName != null)
                        Text(track.artistName!,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, color: Colors.grey, size: 20),
                  tooltip: 'Replace',
                  onPressed: () => _showReplaceSheet(index),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  tooltip: 'Remove',
                  onPressed: () => setState(() => _tracks.removeAt(index)),
                ),
              ],
            ),
          );
        },
          ),
          if (_creating)
            AbsorbPointer(
              child: Container(
                color: const Color(0xCC0A0A0A),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF4FC3F7)),
                    const SizedBox(height: 16),
                    const Text('Creating playlist...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? url;
  final double size;

  const _Thumbnail({this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url != null
          ? Image.network(url!, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder())
          : _placeholder(),
    );
  }

  Widget _placeholder() => Container(
    width: size, height: size,
    color: const Color(0xFF2A2A2A),
    child: const Icon(Icons.music_note, color: Colors.grey, size: 24),
  );
}
