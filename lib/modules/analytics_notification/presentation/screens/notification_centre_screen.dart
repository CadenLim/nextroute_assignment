import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/transit_notification.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/repositories/notification_repository.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/storage/notification_local_storage.dart';
import 'package:nextroute_assignment/modules/analytics_notification/presentation/screens/notification_preferences_screen.dart';

class NotificationCentreScreen extends StatefulWidget {
  const NotificationCentreScreen({this.repository, super.key});

  final NotificationRepository? repository;

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

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        NotificationRepository(SharedPreferencesNotificationLocalStorage());
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (_isUpdating) {
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final notifications = await _repository.loadNotifications();
      if (!mounted) {
        return;
      }
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(TransitNotification notification) async {
    if (_isUpdating || notification.isRead) {
      return;
    }
    await _performUpdate(() => _repository.markAsRead(notification.id));
  }

  Future<void> _markAllAsRead() async {
    if (_isUpdating || _repository.unreadCount(_notifications) == 0) {
      return;
    }
    await _performUpdate(_repository.markAllAsRead);
  }

  Future<void> _performUpdate(
    Future<List<TransitNotification>> Function() operation,
  ) async {
    setState(() {
      _isUpdating = true;
      _error = null;
    });
    try {
      final updated = await operation();
      if (!mounted) {
        return;
      }
      setState(() {
        _notifications = updated;
        _isUpdating = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _repository.unreadCount(_notifications);
    return Scaffold(
      appBar: AppBar(
        title: Text('Notification Centre ($unreadCount unread)'),
        actions: [
          IconButton(
            onPressed: _isLoading || _isUpdating || unreadCount == 0
                ? null
                : _markAllAsRead,
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      NotificationPreferencesScreen(repository: _repository),
                ),
              );
            },
            tooltip: 'Notification preferences',
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notifications.isEmpty && _error != null) {
      return _NotificationError(error: _error, onRetry: _loadNotifications);
    }

    final visibleNotifications = _repository.filterNotifications(
      _notifications,
      _filter,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _filter == NotificationFilter.all,
                onSelected: (_) {
                  setState(() => _filter = NotificationFilter.all);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Unread'),
                selected: _filter == NotificationFilter.unread,
                onSelected: (_) {
                  setState(() => _filter = NotificationFilter.unread);
                },
              ),
              if (_isUpdating) ...[
                const Spacer(),
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Could not update notification data: $_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: visibleNotifications.isEmpty
              ? const _EmptyNotificationState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: visibleNotifications.length,
                  itemBuilder: (context, index) {
                    final notification = visibleNotifications[index];
                    return _NotificationCard(
                      notification: notification,
                      onTap: _isUpdating
                          ? null
                          : () => _markAsRead(notification),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final TransitNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: notification.isRead ? null : colorScheme.primaryContainer,
      child: InkWell(
        onTap: notification.isRead ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconForType(notification.type)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notification.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_labelForOrigin(notification.origin)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_labelForType(notification.type)),
              const SizedBox(height: 8),
              Text(notification.message),
              if (notification.routeId != null) ...[
                const SizedBox(height: 8),
                Text('Route: ${notification.routeId}'),
              ],
              const SizedBox(height: 8),
              Text(
                '${_formatDateTime(notification.createdAt)} • '
                '${notification.isRead ? 'Read' : 'Unread'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconForType(TransitNotificationType type) {
    return switch (type) {
      TransitNotificationType.service => Icons.directions_bus,
      TransitNotificationType.delay => Icons.schedule,
      TransitNotificationType.crowd => Icons.groups,
    };
  }

  static String _labelForType(TransitNotificationType type) {
    return switch (type) {
      TransitNotificationType.service => 'Service',
      TransitNotificationType.delay => 'Delay',
      TransitNotificationType.crowd => 'Crowd',
    };
  }

  static String _labelForOrigin(TransitNotificationOrigin origin) {
    return switch (origin) {
      TransitNotificationOrigin.demo => 'DEMO',
      TransitNotificationOrigin.appGenerated => 'APP-GENERATED',
      TransitNotificationOrigin.official => 'OFFICIAL',
    };
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _EmptyNotificationState extends StatelessWidget {
  const _EmptyNotificationState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No notifications to show for this filter.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _NotificationError extends StatelessWidget {
  const _NotificationError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text('Could not load local notifications: $error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
