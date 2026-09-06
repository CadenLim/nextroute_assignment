import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/screens/notification_preferences.dart';
import 'package:nextroute_assignment/services/analytics_service.dart';
import 'package:nextroute_assignment/services/notification_service.dart';
import 'package:nextroute_assignment/services/module5_route_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationCentreScreen extends StatefulWidget {
  const NotificationCentreScreen({
    this.repository,
    this.embedded = false,
    this.onNotificationsChanged,
    this.enableRealtime = true,
    this.routePreferences,
    super.key,
  });

  final NotificationRepository? repository;
  final bool embedded;
  final VoidCallback? onNotificationsChanged;
  final bool enableRealtime;
  final Module5RoutePreferences? routePreferences;

  @override
  State<NotificationCentreScreen> createState() =>
      _NotificationCentreScreenState();
}

class _NotificationCentreScreenState extends State<NotificationCentreScreen> {
  late final NotificationRepository _repository;
  late final Module5RoutePreferences _routePreferences;
  late final bool _ownsRoutePreferences;
  List<TransitNotification> _notifications = const [];
  NotificationFilter _filter = NotificationFilter.all;
  Object? _error;
  bool _isLoading = true;
  bool _isUpdating = false;
  Map<String, BusRouteInfo> _busRoutes = const {};
  RealtimeChannel? _notificationChannel;
  Timer? _expiryTimer;
  final _searchController = TextEditingController();
  String _search = '';
  bool _allNetwork = false;

  @override
  void initState() {
    super.initState();
    _ownsRoutePreferences = widget.routePreferences == null;
    _routePreferences = widget.routePreferences ?? Module5RoutePreferences();
    _routePreferences.addListener(_routePreferencesChanged);
    if (!_routePreferences.loaded) _routePreferences.load();
    _repository =
        widget.repository ??
        NotificationRepository(
          SharedPreferencesNotificationLocalStorage(),
          pushService: LocalPushNotificationService(),
        );
    _loadBusRoutes();
    _loadNotifications();
    if (widget.enableRealtime) {
      _notificationChannel = _repository.subscribeToNotifications(
        _loadNotifications,
      );
    }
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
      widget.onNotificationsChanged?.call();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _expiryTimer?.cancel();
    final channel = _notificationChannel;
    if (channel != null) {
      _repository.removeSubscription(channel);
    }
    _routePreferences.removeListener(_routePreferencesChanged);
    if (_ownsRoutePreferences) _routePreferences.dispose();
    super.dispose();
  }

  void _routePreferencesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBusRoutes() async {
    try {
      final routes = await BusRouteCatalog.load();
      if (mounted) setState(() => _busRoutes = routes);
    } on Object {
      // Notifications can still display their raw route ID.
    }
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final notifications = await _repository.loadNotifications();
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
        widget.onNotificationsChanged?.call();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateNotifications(
    Future<List<TransitNotification>> Function() operation,
  ) async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
      _error = null;
    });
    try {
      final updated = await operation();
      if (mounted) {
        setState(() {
          _notifications = updated;
          _isUpdating = false;
        });
        widget.onNotificationsChanged?.call();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _openPreferences() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationPreferencesScreen(repository: _repository),
      ),
    );
    if (mounted) await _loadNotifications();
  }

  Future<void> _manageRoutes() async {
    if (_busRoutes.isEmpty) return;
    final selected = Set<String>.from(_routePreferences.followedRoutes);
    final routes = BusRouteCatalog.selectable(_busRoutes);
    var query = '';
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = routes.where((route) {
            final value = query.toLowerCase();
            return route.routeCode.toLowerCase().contains(value) ||
                route.longName.toLowerCase().contains(value);
          }).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .82,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Choose My Routes',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, selected),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search bus route',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value.trim()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final route = visible[index];
                        final code = route.routeCode.toUpperCase();
                        return CheckboxListTile(
                          value: selected.contains(code),
                          onChanged: (checked) => setSheetState(() {
                            checked == true
                                ? selected.add(code)
                                : selected.remove(code);
                          }),
                          title: Text('Route ${route.routeCode}'),
                          subtitle: Text(route.longName),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != null) await _routePreferences.replace(result);
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildBody(context);
    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(title: const Text('Notification Centre')),
      body: content,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notifications.isEmpty && _error != null) {
      return _MessageState(
        message: 'Could not load notifications: $_error',
        onRetry: _loadNotifications,
      );
    }

    final unreadCount = _repository.unreadCount(_notifications);
    final visible = _repository
        .filterNotifications(_notifications, _filter)
        .where((notice) {
          if (!_matchesRouteScope(notice)) return false;
          final route = _busRoutes[notice.routeId];
          return notice.matchesSearch(
            _search,
            routeName: route == null
                ? ''
                : '${route.displayName} ${route.longName}',
          );
        })
        .toList();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Material(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$unreadCount unread (current)',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              onPressed: _isUpdating || unreadCount == 0
                                  ? null
                                  : () => _updateNotifications(
                                      _repository.markAllAsRead,
                                    ),
                              tooltip: 'Mark all as read',
                              icon: const Icon(Icons.done_all),
                            ),
                            IconButton(
                              onPressed: _loadNotifications,
                              tooltip: 'Refresh notifications',
                              icon: const Icon(Icons.refresh),
                            ),
                            IconButton(
                              onPressed: _openPreferences,
                              tooltip: 'Notification preferences',
                              icon: const Icon(Icons.tune),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<bool>(
                              segments: [
                                ButtonSegment(
                                  value: false,
                                  icon: const Icon(Icons.star_outline),
                                  label: Text(
                                    'My Routes (${_routePreferences.followedRoutes.length})',
                                  ),
                                ),
                                const ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.public),
                                  label: Text('All network'),
                                ),
                              ],
                              selected: {_allNetwork},
                              onSelectionChanged: (selection) =>
                                  setState(() => _allNetwork = selection.first),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _manageRoutes,
                            tooltip: 'Manage My Routes',
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _filterChip(
                            label: 'Current',
                            icon: Icons.inbox_outlined,
                            filter: NotificationFilter.all,
                          ),
                          _filterChip(
                            label: 'History',
                            icon: Icons.history,
                            filter: NotificationFilter.history,
                          ),
                          _filterChip(
                            label: 'Unread',
                            icon: Icons.mark_email_unread_outlined,
                            filter: NotificationFilter.unread,
                          ),
                          _filterChip(
                            label: 'Congestion',
                            icon: Icons.traffic,
                            filter: NotificationFilter.congestion,
                          ),
                          _filterChip(
                            label: 'Service',
                            icon: Icons.notifications_active_outlined,
                            filter: NotificationFilter.service,
                          ),
                          _filterChip(
                            label: 'Delays',
                            icon: Icons.schedule,
                            filter: NotificationFilter.delays,
                          ),
                          _filterChip(
                            label: 'Data status',
                            icon: Icons.sync_problem,
                            filter: NotificationFilter.dataStatus,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _search = value),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Search route, bus, stop or message',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _search = '');
                                  },
                                ),
                        ),
                      ),
                    ),
                    if (_filter == NotificationFilter.history)
                      const _ScopeNote(
                        icon: Icons.history,
                        text:
                            'Latest 200 expired public notifications, newest first. '
                            'These are past notices, not current travel warnings. '
                            'Expiry does not confirm that an incident was resolved. '
                            'History does not increase the current unread count or resend push alerts.',
                      ),
                    if (_filter == NotificationFilter.delays)
                      const _ScopeNote(
                        icon: Icons.info_outline,
                        text:
                            'Official notices use publisher-supplied details. NextRoute estimates '
                            'appear only when a fresh stopped bus can be matched to its GTFS '
                            'trip and timetable; missing realtime data is never treated as on time.',
                      ),
                    if (_filter == NotificationFilter.congestion)
                      const _ScopeNote(
                        icon: Icons.info_outline,
                        text:
                            'Possible slow movement is estimated only after repeated fresh GPS movement intervals. It is not operator-confirmed congestion, and insufficient data is never treated as zero congestion.',
                      ),
                    if (!_allNetwork &&
                        _routePreferences.followedRoutes.isEmpty)
                      const _ScopeNote(
                        icon: Icons.star_outline,
                        text:
                            'No routes are followed yet. Use the edit button to choose My Routes, or select All network.',
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Could not update notifications: $_error',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_isUpdating)
                      const LinearProgressIndicator(minHeight: 2),
                  ],
                ),
              ),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _search.trim().isNotEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No matching notifications in this filter.\nTry another route, clear search or check History.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _EmptyNotificationState(
                          filter: _filter,
                          noFollowedRoutes:
                              !_allNetwork &&
                              _routePreferences.followedRoutes.isEmpty,
                        ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final notification = visible[index];
                      return _NotificationCard(
                        notification: notification,
                        route: notification.routeId == null
                            ? null
                            : _busRoutes[notification.routeId],
                        onTap:
                            notification.isRead ||
                                _isUpdating ||
                                notification.isExpiredAt(DateTime.now().toUtc())
                            ? null
                            : () => _updateNotifications(
                                () => _repository.markAsRead(notification.id),
                              ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required IconData icon,
    required NotificationFilter filter,
  }) {
    return ChoiceChip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      selected: _filter == filter,
      onSelected: (_) => setState(() => _filter = filter),
    );
  }

  bool _matchesRouteScope(TransitNotification notification) {
    if (_allNetwork) return true;
    if (notification.isDataHealth || notification.routeId == null) return true;
    return _routePreferences.followedRoutes.any(
      (route) =>
          BusRouteCatalog.matches(notification.routeId, route, _busRoutes),
    );
  }
}

class _ScopeNote extends StatelessWidget {
  const _ScopeNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: const Color(0xFF2457D6)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EmptyNotificationState extends StatelessWidget {
  const _EmptyNotificationState({
    required this.filter,
    this.noFollowedRoutes = false,
  });

  final NotificationFilter filter;
  final bool noFollowedRoutes;

  @override
  Widget build(BuildContext context) {
    if (noFollowedRoutes) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Choose My Routes to receive relevant bus alerts.\nYou can still view All network.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final (icon, title, message) = switch (filter) {
      NotificationFilter.history => (
        Icons.history,
        'No notification history yet',
        'Expired public notifications will remain here for reference.',
      ),
      NotificationFilter.unread => (
        Icons.mark_email_read_outlined,
        'No unread current notifications',
        'You can still view expired notices in History.',
      ),
      NotificationFilter.congestion => (
        Icons.traffic,
        'No congestion alerts',
        'Live congestion alerts appear when the feed reports congested or '
            'severely congested vehicles.',
      ),
      NotificationFilter.service => (
        Icons.notifications_none,
        'No service notifications',
        'Service announcements will appear here when they are received.',
      ),
      NotificationFilter.delays => (
        Icons.schedule,
        'No delay notifications',
        'No reliable delay observation is available. Estimates require a fresh '
            'stopped bus, matching trip ID and published timetable.',
      ),
      NotificationFilter.dataStatus => (
        Icons.sync_problem,
        'No data-status notifications',
        'Collector availability warnings will appear here. They do not mean that a bus service has stopped.',
      ),
      _ => (
        Icons.notifications_none,
        'No current notifications',
        'There are no current notices for your preferences. Check History for expired notifications.',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.blueGrey.shade300),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.route,
    required this.onTap,
  });

  final TransitNotification notification;
  final BusRouteInfo? route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final expired = notification.isExpiredAt(DateTime.now().toUtc());
    final color = expired
        ? Colors.blueGrey
        : _severityColor(notification.severity);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: notification.isRead || expired
          ? Colors.white
          : color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.14),
                foregroundColor: color,
                child: Icon(_iconForType(notification.type), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!notification.isRead && !expired)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2463EB),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(notification.message),
                    const SizedBox(height: 6),
                    Text(
                      'Published: ${_notificationDate(notification.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (expired)
                      Text(
                        'Expired: ${_notificationDate(notification.expiresAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (notification.routeId != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        route == null
                            ? 'Bus route: ${notification.routeId}'
                            : 'Bus route: ${route!.routeCode} (${route!.id})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (route != null)
                        Text('Route coverage: ${route!.longName}'),
                    ],
                    if (notification.type == TransitNotificationType.delay) ...[
                      const SizedBox(height: 10),
                      Text(
                        notification.delayLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      if (notification.scheduledArrival != null)
                        Text(
                          'Scheduled arrival: ${_notificationDate(notification.scheduledArrival!)}',
                        ),
                      if (notification.estimatedArrival != null)
                        Text(
                          'Estimated arrival: ${_notificationDate(notification.estimatedArrival!)}',
                        ),
                      if (notification.vehicleLabel != null)
                        Text('Vehicle ID: ${notification.vehicleLabel}'),
                      if (notification.confidence != null)
                        Text(
                          'Confidence: ${notification.confidence}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      if (notification.fromStop != null)
                        Text('Observed at: ${notification.fromStop}'),
                      if (notification.toStop != null)
                        Text('Towards: ${notification.toStop}'),
                      if (notification.direction != null &&
                          notification.direction != notification.toStop)
                        Text('Direction: ${notification.direction}'),
                      if (notification.vehicleLabel == null &&
                          notification.fromStop == null &&
                          notification.toStop == null)
                        const Text(
                          'Route-level notice; detailed vehicle and affected section were not provided.',
                        ),
                      const SizedBox(height: 4),
                      Text(
                        notification.isEstimatedDelay
                            ? 'NextRoute estimate from a fresh near-stop GPS position and the published timetable; not an operator Trip Update.'
                            : 'Details as published in this notice; route coverage does not confirm the affected direction.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (notification.isEstimatedCongestion) ...[
                      const SizedBox(height: 10),
                      if (notification.observedSpeedKmh != null)
                        Text(
                          'Observed average speed: ${notification.observedSpeedKmh!.toStringAsFixed(1)} km/h',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      if (notification.observationDurationMinutes != null)
                        Text(
                          'Observation window: ${notification.observationDurationMinutes} min',
                        ),
                      if (notification.vehicleLabel != null)
                        Text('Vehicle ID: ${notification.vehicleLabel}'),
                      const SizedBox(height: 4),
                      Text(
                        'NextRoute estimate from repeated fresh GPS movement intervals. Normal reported stop dwell is excluded. It is not operator-confirmed congestion.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Tag(label: _originLabel(notification.origin)),
                        _Tag(
                          label: expired
                              ? 'Past severity: ${_severityLabel(notification.severity)}'
                              : _severityLabel(notification.severity),
                          color: color,
                        ),
                        _Tag(
                          label: expired
                              ? 'Expired • History'
                              : notification.isRead
                              ? 'Read'
                              : 'Unread',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconForType(TransitNotificationType type) => switch (type) {
    TransitNotificationType.service => Icons.notifications_active_outlined,
    TransitNotificationType.delay => Icons.schedule,
    TransitNotificationType.crowd => Icons.traffic,
  };

  static Color _severityColor(NotificationSeverity severity) =>
      switch (severity) {
        NotificationSeverity.info => const Color(0xFF2463EB),
        NotificationSeverity.moderate => const Color(0xFF9A6B00),
        NotificationSeverity.high => const Color(0xFFF57C00),
        NotificationSeverity.critical => const Color(0xFFD92D3A),
      };

  static String _severityLabel(NotificationSeverity severity) =>
      switch (severity) {
        NotificationSeverity.info => 'Info',
        NotificationSeverity.moderate => 'Moderate',
        NotificationSeverity.high => 'High',
        NotificationSeverity.critical => 'Critical',
      };

  static String _originLabel(TransitNotificationOrigin origin) =>
      switch (origin) {
        TransitNotificationOrigin.appGenerated => 'APP',
        TransitNotificationOrigin.official => 'OFFICIAL',
      };
}

String _notificationDate(DateTime instant) {
  final date = instant.toUtc().add(const Duration(hours: 8));
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day}/${date.month}/${date.year} $hour:$minute MYT';
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tagColor = color ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tagColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
