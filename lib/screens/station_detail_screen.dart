part of 'transport_data.dart';

class StationDetailScreen extends StatelessWidget {
  final Station station;
  const StationDetailScreen({super.key, required this.station});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        toolbarHeight: 116,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              station.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: station.lines.map(LineBadge.new).toList(),
            ),
          ],
        ),
        bottom: const TabBar(
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: 'Information'),
            Tab(text: 'Timetable'),
            Tab(text: 'Facilities'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _InformationTab(station: station),
          _TimetableTab(station: station),
          _FacilitiesTab(station: station),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: station.latitude == 0
                ? null
                : () async {
              try {
                await openGoogleMaps(station);
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Open in Google Maps'),
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size.fromHeight(54)),
              backgroundColor: WidgetStatePropertyAll(_blue),
              foregroundColor: WidgetStatePropertyAll(Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}

class _InformationTab extends StatelessWidget {
  final Station station;
  const _InformationTab({required this.station});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      FutureBuilder<String?>(
        future: AddressService.resolve(station),
        builder: (context, snapshot) => _InfoCard(
          Icons.location_on_outlined,
          'Nearby address',
          snapshot.connectionState == ConnectionState.waiting
              ? 'Finding address...'
              : snapshot.data ?? 'Address is not available in this dataset',
          const Color(0xFFEF4444),
          detail: station.latitude == 0
              ? null
              : '${station.latitude.toStringAsFixed(6)}, '
              '${station.longitude.toStringAsFixed(6)}',
        ),
      ),
      _InfoCard(
        Icons.flag_outlined,
        'Transport Type',
        station.type,
        const Color(0xFF7C3AED),
      ),
      _InfoCard(
        Icons.train_outlined,
        'Lines',
        station.lines.join(', '),
        const Color(0xFF2563EB),
      ),
      _InfoCard(
        Icons.storage_outlined,
        'Data source',
        station.sources
            .map((source) => 'data.gov.my GTFS ${source.replaceAll('_', ' ')}')
            .join('\n'),
        const Color(0xFF475569),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text(
          'Address is resolved from OpenStreetMap only when this page is '
              'opened. Coordinates remain the navigation destination.',
          style: TextStyle(color: Color(0xFF64748B), height: 1.4),
        ),
      ),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? detail;
  const _InfoCard(this.icon, this.label, this.value, this.color, {this.detail});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    elevation: 1,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SoftIcon(icon, color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: _ink, fontSize: 16)),
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    detail!,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimetableTab extends StatelessWidget {
  final Station station;
  const _TimetableTab({required this.station});

  @override
  Widget build(BuildContext context) => FutureBuilder<ScheduleResult>(
    future: StaticScheduleService.loadDepartures(station),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load the supplied GTFS timetable: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      final result =
          snapshot.data ?? const ScheduleResult(groups: [], notices: []);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'NEXT PUBLISHED DEPARTURES',
                  style: TextStyle(
                    color: Color(0xFF71839E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                avatar: Icon(Icons.calendar_today_outlined, size: 16),
                label: Text('Today'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...result.notices.map(
                (notice) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MessageCard(
                icon: Icons.update_outlined,
                color: Colors.orange,
                message: notice,
              ),
            ),
          ),
          if (result.groups.isEmpty)
            const _MessageCard(
              icon: Icons.event_busy_outlined,
              color: Color(0xFF64748B),
              message:
              'No upcoming timetable is available for this stop '
                  'today. This can mean the feed has expired, the stop has no '
                  'scheduled service today, or the operator did not publish '
                  'stop times for it.',
            )
          else
            ...result.groups.map((group) => _DepartureCard(group: group)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Times marked “Est.” are calculated from the official '
                        'GTFS frequency windows. They are scheduled estimates, '
                        'not live arrival predictions. The government realtime '
                        'feed currently supplies vehicle positions only.',
                    style: TextStyle(color: _blue, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _DepartureCard extends StatelessWidget {
  final DepartureGroup group;
  const _DepartureCard({required this.group});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              group.route,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.destination,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (group.frequencyNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...group.frequencyNotes
                      .take(3)
                      .map(
                        (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule_outlined,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              note,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: group.times.map((time) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        time,
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FacilitiesTab extends StatelessWidget {
  final Station station;
  const _FacilitiesTab({required this.station});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'AVAILABLE',
        style: TextStyle(color: Color(0xFF71839E), fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: station.accessible == null
              ? const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No verified facility data',
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This GTFS stop does not include facility fields. '
                    'Parking, lift, escalator and toilet availability are '
                    'shown as unknown instead of being guessed.',
                style: TextStyle(color: Color(0xFF64748B), height: 1.4),
              ),
            ],
          )
              : ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _SoftIcon(
              station.accessible! ? Icons.accessible : Icons.help_outline,
              station.accessible!
                  ? const Color(0xFF059669)
                  : Colors.orange,
            ),
            title: Text(
              station.accessible!
                  ? 'OKU accessible'
                  : 'Not marked as OKU accessible',
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              station.accessible!
                  ? 'Verified by the supplied rail station dataset'
                  : 'Unknown status; it does not prove that access is unavailable',
            ),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDBEAFE)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: _blue),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Facility availability is subject to change. Contact station management for the most current information.',
                style: TextStyle(color: _blue, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
