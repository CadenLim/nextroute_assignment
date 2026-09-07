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

enum _TimetablePeriod { allDay, morning, afternoon, evening }

class _TimetableTab extends StatefulWidget {
  final Station station;
  const _TimetableTab({required this.station});

  @override
  State<_TimetableTab> createState() => _TimetableTabState();
}

class _TimetableTabState extends State<_TimetableTab> {
  late DateTime selectedDate;
  late Future<ScheduleResult> schedule;
  _TimetablePeriod selectedPeriod = _TimetablePeriod.allDay;

  @override
  void initState() {
    super.initState();
    selectedDate = DateUtils.dateOnly(DateTime.now());
    schedule = _loadSchedule();
  }

  Future<ScheduleResult> _loadSchedule() {
    final startSeconds = switch (selectedPeriod) {
      _TimetablePeriod.allDay => null,
      _TimetablePeriod.morning => 0,
      _TimetablePeriod.afternoon => 12 * 3600,
      _TimetablePeriod.evening => 18 * 3600,
    };
    final endSeconds = switch (selectedPeriod) {
      _TimetablePeriod.morning => 12 * 3600,
      _TimetablePeriod.afternoon => 18 * 3600,
      _ => null,
    };
    return StaticScheduleService.loadDepartures(
      widget.station,
      date: selectedDate,
      startSeconds: startSeconds,
      endSeconds: endSeconds,
    );
  }

  Future<void> _chooseDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 7)),
      helpText: 'Select timetable date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      selectedDate = DateUtils.dateOnly(picked);
      selectedPeriod = _TimetablePeriod.allDay;
      schedule = _loadSchedule();
    });
  }

  void _selectPeriod(_TimetablePeriod period) {
    if (period == selectedPeriod) return;
    setState(() {
      selectedPeriod = period;
      schedule = _loadSchedule();
    });
  }

  bool get _isToday {
    final today = DateUtils.dateOnly(DateTime.now());
    return selectedDate == today;
  }

  String _dateLabel(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (selectedDate == today) return 'Today';
    if (selectedDate == today.add(const Duration(days: 1))) return 'Tomorrow';
    return MaterialLocalizations.of(context).formatMediumDate(selectedDate);
  }

  String _periodLabel(_TimetablePeriod period) => switch (period) {
    _TimetablePeriod.allDay => _isToday ? 'Upcoming' : 'All day',
    _TimetablePeriod.morning => 'Morning',
    _TimetablePeriod.afternoon => 'Afternoon',
    _TimetablePeriod.evening => 'Evening',
  };

  @override
  Widget build(BuildContext context) => FutureBuilder<ScheduleResult>(
    future: schedule,
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
          Row(
            children: [
              Expanded(
                child: Text(
                  _isToday
                      ? 'NEXT PUBLISHED DEPARTURES'
                      : 'PUBLISHED DEPARTURES',
                  style: const TextStyle(
                    color: Color(0xFF71839E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_dateLabel(context)),
                tooltip: 'Choose a date within the next 7 days',
                onPressed: _chooseDate,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _TimetablePeriod.values.map((period) {
              return ChoiceChip(
                label: Text(_periodLabel(period)),
                selected: selectedPeriod == period,
                onSelected: (_) => _selectPeriod(period),
              );
            }).toList(),
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
            _MessageCard(
              icon: Icons.event_busy_outlined,
              color: const Color(0xFF64748B),
              message: _isToday
                  ? 'No upcoming timetable is available for this stop today. '
                      'This can mean the stop has no remaining service today '
                      'or the operator did not publish stop times for it.'
                  : 'No published timetable is available for this stop on '
                      '${MaterialLocalizations.of(context).formatMediumDate(selectedDate)}. '
                      'The service may not operate on this date or the operator '
                      'may not have published stop times for it.',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
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
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  group.destination,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (group.frequencyNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...group.frequencyNotes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.schedule_outlined,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note,
                        softWrap: true,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                          height: 1.35,
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
