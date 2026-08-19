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
  List<Map<String, dynamic>> _upcomingShows = [];
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
      _upcomingShows = [];
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
      final upcoming = shows.where((s) {
        try {
          return DateTime.parse(s['date'] as String).isAfter(now.subtract(const Duration(days: 1)));
        } catch (_) { return false; }
      }).cast<Map<String, dynamic>>().toList();
      if (mounted) setState(() { _upcomingShows = upcoming; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _showNotifications() {
    if (!AuthService.isLoggedIn) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen()));
      return;
    }
    if (_upcomingShows.isEmpty) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
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
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.notifications, color: Color(0xFF4FC3F7), size: 18),
                  const SizedBox(width: 8),
                  Text('Upcoming shows (${_upcomingShows.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: _upcomingShows.length,
                itemBuilder: (_, i) {
                  final s = _upcomingShows[i];
                  final date = _formatDate(s['date'] as String? ?? '');
                  final daysUntil = _daysUntil(s['date'] as String? ?? '');
                  final venue = s['venue'] as String? ?? '';
                  final city = s['city'] as String? ?? '';
                  return ListTile(
                    leading: const Icon(Icons.event, color: Color(0xFF4FC3F7), size: 20),
                    title: Text(s['artist_name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('${[venue, city].where((x) => x.isNotEmpty).join(' · ')} · $date', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: daysUntil <= 7 ? const Color(0xFF4FC3F7).withOpacity(0.2) : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        daysUntil == 0 ? 'Today!' : daysUntil == 1 ? 'Tomorrow' : 'In ${daysUntil}d',
                        style: TextStyle(
                          color: daysUntil <= 7 ? const Color(0xFF4FC3F7) : Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
    try {
      return DateTime.parse(raw).difference(DateTime.now()).inDays;
    } catch (_) { return 999; }
  }

  @override
  Widget build(BuildContext context) {
    final count = _upcomingShows.length;
    return IconButton(
      tooltip: !AuthService.isLoggedIn ? 'Sign in for notifications' : (count > 0 ? '$count upcoming show${count == 1 ? '' : 's'}' : 'Upcoming shows'),
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
