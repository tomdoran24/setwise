import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/account_button.dart';
import 'setlist_screen.dart';

class VenueScreen extends StatefulWidget {
  final String artist;
  final String mbid;
  final String? imageUrl;

  const VenueScreen({super.key, required this.artist, required this.mbid, this.imageUrl});

  @override
  State<VenueScreen> createState() => _VenueScreenState();
}

class _VenueScreenState extends State<VenueScreen> {
  late Future<List<dynamic>> _showsFuture;

  @override
  void initState() {
    super.initState();
    _showsFuture = ApiService.getUpcomingShows(widget.mbid);
  }

  Future<void> _pickShowDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      helpText: 'When are you seeing ${widget.artist}?',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4FC3F7),
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';

    // Try to find the show on TM by date
    Map<String, dynamic>? matchedShow;
    try {
      final shows = await ApiService.getUpcomingShows(widget.mbid);
      matchedShow = shows.cast<Map<String, dynamic>>().firstWhere(
        (s) => s['date'] == dateStr,
        orElse: () => <String, dynamic>{},
      );
      if (matchedShow.isEmpty) matchedShow = null;
    } catch (_) {}

    _goToSetlist(
      tour: matchedShow?['tour'] as String?,
      venueName: matchedShow?['venue'] as String?,
      venueCity: matchedShow?['city'] as String?,
      show: matchedShow ?? {'date': dateStr, 'venue': null, 'city': null, 'country': null, 'tour': null},
      showNotListed: matchedShow == null,
    );
  }

  void _goToSetlist({String? tour, String? venueName, String? venueCity, bool showNotListed = false, Map<String, dynamic>? show}) {
    if (show != null) {
      ApiService.saveUpcomingShow(
        artistName: widget.artist,
        mbid: widget.mbid,
        date: show['date'] as String,
        venue: show['venue'] as String?,
        city: show['city'] as String?,
        country: show['country'] as String?,
        tour: show['tour'] as String?,
      ).catchError((_) {}); // fire-and-forget, don't block navigation
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SetlistScreen(
          artist: widget.artist,
          mbid: widget.mbid,
          tour: tour,
          imageUrl: widget.imageUrl,
          venueName: venueName,
          venueCity: venueCity,
          showNotListed: showNotListed,
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final parts = raw.split('-');
      int day, month;
      String year;
      if (parts[0].length == 4) {
        // ISO format: YYYY-MM-DD (Ticketmaster)
        year = parts[0];
        month = int.parse(parts[1]);
        day = int.parse(parts[2]);
      } else {
        // DD-MM-YYYY (Setlist.fm)
        day = int.parse(parts[0]);
        month = int.parse(parts[1]);
        year = parts[2];
      }
      const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final suffix = (day >= 11 && day <= 13) ? 'th'
          : switch (day % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
      return '$day$suffix ${months[month]} $year';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: const [AccountButton(), SizedBox(width: 8)]),
      body: FutureBuilder<List<dynamic>>(
        future: _showsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Searching for upcoming shows...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final shows = snapshot.data ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.imageUrl != null)
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    image: DecorationImage(
                      image: NetworkImage(
                        ApiService.artistImageProxyUrl(widget.imageUrl!),
                      ),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xFF0A0A0A)],
                      ),
                    ),
                    alignment: Alignment.bottomLeft,
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      widget.artist,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              Container(
                color: const Color(0xFF0A0A0A),
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Where are you seeing ${widget.artist}?',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select your show to get a more accurate prediction',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Container(
                color: const Color(0xFF0A0A0A),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _pickShowDate(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: const BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('My show isn\'t listed'),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (shows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No upcoming shows found', style: TextStyle(color: Colors.grey)),
                      ),
                    ...shows.map((show) {
                      final venue = show['venue'] ?? '';
                      final city = show['city'] ?? '';
                      final country = show['country'] ?? '';
                      final date = _formatDate(show['date'] ?? '');
                      final tour = show['tour'] as String?;
                      final isFestival = show['festival'] == true;
                      final festivalName = (show['festival_name'] ?? show['event_name']) as String?;
                      final displayTitle = isFestival && festivalName != null ? festivalName : venue;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          onTap: () => _goToSetlist(tour: tour, venueName: venue, venueCity: city, show: show),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Text(
                            displayTitle,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text('$city, $country', style: const TextStyle(color: Colors.grey)),
                              if (isFestival || tour != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 6,
                                    children: [
                                      if (isFestival)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFB300).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Festival',
                                            style: TextStyle(color: Color(0xFFFFB300), fontSize: 11),
                                          ),
                                        ),
                                      if (tour != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF4FC3F7).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            tour,
                                            style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          trailing: Text(date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
