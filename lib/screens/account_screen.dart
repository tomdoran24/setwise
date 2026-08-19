import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<dynamic> _upcomingShows = [];
  List<dynamic> _trackedArtists = [];
  bool _loadingShows = true;
  bool _loadingArtists = true;
  bool _preferClean = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!AuthService.isLoggedIn) return;

    try {
      final me = await ApiService.getMe();
      if (mounted) setState(() => _preferClean = me['prefer_clean'] as bool? ?? false);
    } catch (_) {}

    try {
      final today = DateTime.now();
      final shows = await ApiService.getMyUpcomingShows();
      // Filter out past shows client-side
      final upcoming = shows.where((s) {
        try {
          return DateTime.parse(s['date'] as String).isAfter(today.subtract(const Duration(days: 1)));
        } catch (_) { return true; }
      }).toList();
      if (mounted) setState(() { _upcomingShows = upcoming; _loadingShows = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingShows = false);
    }

    try {
      final artists = await ApiService.getTrackedArtists();
      if (mounted) setState(() { _trackedArtists = artists; _loadingArtists = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingArtists = false);
    }
  }

  Future<void> _deleteShow(String id) async {
    try {
      await ApiService.deleteUpcomingShow(id);
      setState(() => _upcomingShows.removeWhere((s) => s['id'] == id));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove show')),
      );
    }
  }

  Future<void> _untrackArtist(String mbid) async {
    try {
      await ApiService.untrackArtist(mbid);
      setState(() => _trackedArtists.removeWhere((a) => a['mbid'] == mbid));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to untrack artist')),
      );
    }
  }

  void _signIn() {
    // Open in same tab so the OAuth redirect returns us to the app
    launchUrl(Uri.parse(ApiService.authUrl), webOnlyWindowName: '_self');
  }

  Future<void> _disconnectYoutube() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Disconnect YouTube?', style: TextStyle(color: Colors.white)),
        content: const Text('Your YouTube account will be unlinked. You can reconnect at any time.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Disconnect')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.disconnectPlatform('google');
      await AuthService.fetchMe();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to disconnect YouTube')));
    }
  }

  Future<void> _disconnectSpotify() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Disconnect Spotify?', style: TextStyle(color: Colors.white)),
        content: const Text('Your Spotify account will be unlinked. You can reconnect at any time.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Disconnect')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.disconnectPlatform('spotify');
      spotifyToken = null;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to disconnect Spotify')));
    }
  }

  void _signOut() {
    AuthService.signOut();
    spotifyToken = null;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: const Color(0xFF0A0A0A),
        foregroundColor: Colors.white,
      ),
      body: user == null ? _buildSignedOut() : _buildSignedIn(user),
    );
  }

  Widget _buildSignedOut() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Sign in to save setlists, track artists,\nand keep your YouTube & Spotify connected.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _signIn,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedIn(UserModel user) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Profile header
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFF4FC3F7),
              child: Text(user.initials,
                  style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(user.email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Connected platforms
        _SectionHeader(title: 'Connected Platforms'),
        _PlatformTile(
          icon: FontAwesomeIcons.youtube,
          label: 'YouTube',
          color: const Color(0xFFFF0000),
          connected: user.youtubeConnected,
          onConnect: _signIn,
          onDisconnect: user.youtubeConnected ? _disconnectYoutube : null,
        ),
        _PlatformTile(
          icon: FontAwesomeIcons.spotify,
          label: 'Spotify',
          color: const Color(0xFF1DB954),
          connected: spotifyToken != null,
          onConnect: () => launchUrl(Uri.parse(ApiService.spotifyAuthUrl)),
          onDisconnect: spotifyToken != null ? _disconnectSpotify : null,
        ),

        const SizedBox(height: 24),

        // Upcoming shows
        _SectionHeader(title: 'Upcoming Shows (${_upcomingShows.length})'),
        if (_loadingShows)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7))),
          )
        else if (_upcomingShows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No upcoming shows saved.\nSelect a show from the setlist screen.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          ..._upcomingShows.map((s) => _UpcomingShowTile(
                show: s as Map<String, dynamic>,
                onDelete: () => _deleteShow(s['id'] as String),
              )),

        const SizedBox(height: 24),

        // Tracked artists
        _SectionHeader(title: 'Tracked Artists (${_trackedArtists.length})'),
        if (_loadingArtists)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7))),
          )
        else if (_trackedArtists.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No tracked artists yet.\nTrack one from the setlist screen.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          ..._trackedArtists.map((a) => _TrackedArtistTile(
                artist: a as Map<String, dynamic>,
                onUntrack: () => _untrackArtist(a['mbid'] as String),
              )),

        const SizedBox(height: 24),

        _SectionHeader(title: 'Preferences'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Prefer clean versions', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Prefer non-explicit tracks when exporting to Spotify',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          value: _preferClean,
          activeColor: const Color(0xFF4FC3F7),
          onChanged: (val) async {
            setState(() => _preferClean = val);
            try {
              await ApiService.updatePreferences(preferClean: val);
            } catch (_) {
              if (mounted) setState(() => _preferClean = !val);
            }
          },
        ),

        const SizedBox(height: 32),

        OutlinedButton(
          onPressed: _signOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
          ),
          child: const Text('Sign Out'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
      );
}

class _PlatformTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback? onDisconnect;

  const _PlatformTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.connected,
    required this.onConnect,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: FaIcon(icon, color: color, size: 22),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing: connected
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_circle, color: Color(0xFF1DB954), size: 18),
                const SizedBox(width: 4),
                const Text('Connected', style: TextStyle(color: Color(0xFF1DB954), fontSize: 13)),
                if (onDisconnect != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onDisconnect,
                    style: TextButton.styleFrom(foregroundColor: Colors.grey, padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                    child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ])
            : TextButton(
                onPressed: onConnect,
                child: const Text('Connect'),
              ),
      );
}

class _UpcomingShowTile extends StatelessWidget {
  final Map<String, dynamic> show;
  final VoidCallback onDelete;

  const _UpcomingShowTile({required this.show, required this.onDelete});

  String _formatDate(String raw) {
    try {
      final parts = raw.split('-');
      final day = int.parse(parts[2]);
      final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final suffix = (day >= 11 && day <= 13) ? 'th'
          : switch (day % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
      return '$day$suffix ${months[int.parse(parts[1])]} ${parts[0]}';
    } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final venue = show['venue'] as String? ?? '';
    final city = show['city'] as String? ?? '';
    final date = _formatDate(show['date'] as String? ?? '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(show['artist_name'] as String,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text('$venue · $city · $date',
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
        onPressed: onDelete,
      ),
    );
  }
}

class _TrackedArtistTile extends StatelessWidget {
  final Map<String, dynamic> artist;
  final VoidCallback onUntrack;

  const _TrackedArtistTile({required this.artist, required this.onUntrack});

  @override
  Widget build(BuildContext context) {
    final imageUrl = artist['image_url'] as String?;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipOval(
        child: imageUrl != null
            ? Image.network(imageUrl, width: 40, height: 40, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder())
            : _placeholder(),
      ),
      title: Text(artist['artist_name'] as String,
          style: const TextStyle(color: Colors.white)),
      trailing: IconButton(
        icon: const Icon(Icons.close, color: Colors.grey, size: 20),
        tooltip: 'Untrack',
        onPressed: onUntrack,
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 40, height: 40,
        color: const Color(0xFF2A2A2A),
        child: const Icon(Icons.person, color: Colors.grey, size: 20),
      );
}
