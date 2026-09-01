import 'package:flutter/material.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/screens/notification_preferences.dart';
import 'package:nextroute_assignment/services/analytics_service.dart';
import 'package:nextroute_assignment/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationCentreScreen extends StatefulWidget {
  const NotificationCentreScreen({
    this.repository,
    this.embedded = false,
    this.onNotificationsChanged,
    super.key,
  });

  final NotificationRepository? repository;
  final bool embedded;
  final VoidCallback? onNotificationsChanged;

  @override
  State<NotificationCentreScreen> createState() =>
      _NotificationCentreScreenState();
}

class _NotificationCentreScreenState extends State<NotificationCentreScreen> {
  late final NotificationRepository _repository;
  List<TransitNotification> _notifications = const [];
  NotificationFilter _filter = NotificationFilter.all;
  Object? _error;
  bool _isLoading = true;
  bool _isUpdating = false;
  Map<String, BusRouteInfo> _busRoutes = const {};
  RealtimeChannel? _notificationChannel;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        NotificationRepository(
          SharedPreferencesNotificationLocalStorage(),
          pushService: LocalPushNotificationService(),
        );
    _loadBusRoutes();
    _loadNotifications();
    _notificationChannel = _repository.subscribeToNotifications(
      _loadNotifications,
    );
  }

  @override
  void dispose() {
    final channel = _notificationChannel;
    if (channel != null) {
      _repository.removeSubscription(channel);
    }
    super.dispose();
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
    final visible = _repository.filterNotifications(_notifications, _filter);
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$unreadCount unread',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isUpdating || unreadCount == 0
                      ? null
                      : () => _updateNotifications(_repository.markAllAsRead),
                  tooltip: 'Mark all as read',
                  icon: const Icon(Icons.done_all),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(
                label: 'All',
                icon: Icons.inbox_outlined,
                filter: NotificationFilter.all,
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
                filter: NotificationFilter.push,
              ),
              _filterChip(
                label: 'Delays',
                icon: Icons.schedule,
                filter: NotificationFilter.delays,
              ),
            ],
          ),
        ),
        if (_filter == NotificationFilter.delays)
          const _ScopeNote(
            icon: Icons.info_outline,
            text:
                'Delay alerts shown here are received notifications. '
                'NextRoute does not calculate delay minutes from the '
                'vehicle-position feed.',
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Could not update notifications: $_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_isUpdating) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: visible.isEmpty
              ? _EmptyNotificationState(filter: _filter)
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final notification = visible[index];
                      return _NotificationCard(
                        notification: notification,
                        route: notification.routeId == null
                            ? null
                            : _busRoutes[notification.routeId],
                        onTap: notification.isRead || _isUpdating
                            ? null
                            : () => _updateNotifications(
                                () => _repository.markAsRead(notification.id),
                              ),
                      );
                    },
                  ),
                ),
        ),
      ],
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
  const _EmptyNotificationState({required this.filter});

  final NotificationFilter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (filter) {
      NotificationFilter.congestion => (
        Icons.traffic,
        'No congestion alerts',
        'Live congestion alerts appear when the feed reports congested or '
            'severely congested vehicles.',
      ),
      NotificationFilter.push => (
        Icons.notifications_none,
        'No service notifications',
        'Service announcements will appear here when they are received.',
      ),
      NotificationFilter.delays => (
        Icons.schedule,
        'No delay notifications',
        'Delay alerts appear only when delay information is supplied; it is '
            'not estimated from GPS positions.',
      ),
      _ => (
        Icons.notifications_none,
        'No notifications',
        'There are no notifications to show.',
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
    final color = _severityColor(notification.severity);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: notification.isRead ? Colors.white : color.withValues(alpha: 0.08),
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
                        if (!notification.isRead)
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
                    if (notification.routeId != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        route == null
                            ? 'Route: ${notification.routeId}'
                            : '${route!.displayName} (${route!.id})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (route != null) Text(route!.longName),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Tag(label: _originLabel(notification.origin)),
                        _Tag(
                          label: _severityLabel(notification.severity),
                          color: color,
                        ),
                        _Tag(label: notification.isRead ? 'Read' : 'Unread'),
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
