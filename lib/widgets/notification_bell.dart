import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../screens/account_screen.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _past = [];
  bool _loaded = false;
  bool _wasLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _wasLoggedIn = AuthService.isLoggedIn;
    _load();
  }

  @override
  void didUpdateWidget(covariant NotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nowLoggedIn = AuthService.isLoggedIn;
    if (nowLoggedIn != _wasLoggedIn) {
      _wasLoggedIn = nowLoggedIn;
      _upcoming = [];
      _past = [];
      _loaded = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (!AuthService.isLoggedIn) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final shows = await ApiService.getMyUpcomingShows();
      final now = DateTime.now();
      final upcoming = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];
      for (final s in shows.cast<Map<String, dynamic>>()) {
        try {
          final d = DateTime.parse(s['date'] as String);
          if (d.isAfter(now.subtract(const Duration(days: 1)))) {
            upcoming.add(s);
          } else if (d.isAfter(now.subtract(const Duration(days: 30)))) {
            past.add(s);
          }
        } catch (_) {}
      }
      if (mounted) setState(() { _upcoming = upcoming; _past = past; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _showNotifications() {
    if (!AuthService.isLoggedIn) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen()));
      return;
    }
    if (_upcoming.isEmpty && _past.isEmpty) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none, color: Colors.grey, size: 40),
              SizedBox(height: 12),
              Text('No upcoming shows saved', style: TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _NotificationsSheet(upcoming: _upcoming, past: _past),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _upcoming.length;
    return IconButton(
      tooltip: !AuthService.isLoggedIn
          ? 'Sign in for notifications'
          : (count > 0 ? '$count upcoming show${count == 1 ? '' : 's'}' : 'Upcoming shows'),
      onPressed: _showNotifications,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            count > 0 ? Icons.notifications : Icons.notifications_none,
            color: count > 0 ? const Color(0xFF4FC3F7) : Colors.grey,
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Color(0xFF4FC3F7), shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> upcoming;
  final List<Map<String, dynamic>> past;
  const _NotificationsSheet({required this.upcoming, required this.past});

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  // mbid+date → accuracy result map
  final Map<String, Map<String, dynamic>?> _accuracy = {};

  @override
  void initState() {
    super.initState();
    _fetchAccuracy();
  }

  Future<void> _fetchAccuracy() async {
    for (final s in widget.past) {
      final mbid = s['mbid'] as String? ?? '';
      final date = s['date'] as String? ?? '';
      if (mbid.isEmpty || date.isEmpty) continue;
      final key = '$mbid|$date';
      try {
        final rows = await ApiService.getAccuracy(mbid);
        final match = rows.cast<Map<String, dynamic>>().where((r) => r['show_date'] == date).firstOrNull;
        if (mounted) setState(() => _accuracy[key] = match);
        // If not yet computed, trigger computation (no predicted songs available here — skips)
      } catch (_) {}
    }
  }

  String _formatDate(String raw) {
    try {
      final parts = raw.split('-');
      final day = int.parse(parts[2]);
      final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final suffix = (day >= 11 && day <= 13) ? 'th' : switch (day % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
      return '$day$suffix ${months[int.parse(parts[1])]}';
    } catch (_) { return raw; }
  }

  int _daysUntil(String raw) {
    try { return DateTime.parse(raw).difference(DateTime.now()).inDays; } catch (_) { return 999; }
  }

  Widget _badge(String label, Color color, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                if (widget.upcoming.isNotEmpty) ...[
                  _SectionLabel(text: 'Upcoming (${widget.upcoming.length})'),
                  ...widget.upcoming.map((s) {
                    final daysUntil = _daysUntil(s['date'] as String? ?? '');
                    final venue = s['venue'] as String? ?? '';
                    final city = s['city'] as String? ?? '';
                    final label = daysUntil == 0 ? 'Today!' : daysUntil == 1 ? 'Tomorrow' : 'In ${daysUntil}d';
                    final isClose = daysUntil <= 7;
                    return ListTile(
                      leading: const Icon(Icons.event, color: Color(0xFF4FC3F7), size: 20),
                      title: Text(s['artist_name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      subtitle: Text('${[venue, city].where((x) => x.isNotEmpty).join(' · ')} · ${_formatDate(s['date'] as String? ?? '')}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing: _badge(label,
                        isClose ? const Color(0xFF4FC3F7) : Colors.grey,
                        isClose ? const Color(0xFF4FC3F7).withOpacity(0.15) : const Color(0xFF2A2A2A),
                      ),
                    );
                  }),
                ],
                if (widget.past.isNotEmpty) ...[
                  _SectionLabel(text: 'Recent shows'),
                  ...widget.past.map((s) {
                    final mbid = s['mbid'] as String? ?? '';
                    final date = s['date'] as String? ?? '';
                    final key = '$mbid|$date';
                    final acc = _accuracy[key];
                    final venue = s['venue'] as String? ?? '';
                    final city = s['city'] as String? ?? '';
                    Widget trailing;
                    if (!_accuracy.containsKey(key)) {
                      trailing = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey));
                    } else if (acc == null) {
                      trailing = _badge('No data', Colors.grey, const Color(0xFF2A2A2A));
                    } else {
                      final recall = ((acc['recall'] as num) * 100).round();
                      final color = recall >= 70 ? const Color(0xFF4CAF50) : recall >= 40 ? const Color(0xFFFFB74D) : Colors.redAccent;
                      trailing = _badge('$recall% accuracy', color, color.withOpacity(0.15));
                    }
                    return ListTile(
                      leading: const Icon(Icons.check_circle_outline, color: Colors.grey, size: 20),
                      title: Text(s['artist_name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      subtitle: Text('${[venue, city].where((x) => x.isNotEmpty).join(' · ')} · ${_formatDate(date)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing: trailing,
                    );
                  }),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
  );
}
