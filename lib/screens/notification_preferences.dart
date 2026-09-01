import 'package:flutter/material.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/services/notification_service.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({required this.repository, super.key});

  final NotificationRepository repository;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final LocalPushNotificationService _pushService =
      LocalPushNotificationService();
  NotificationPreferences? _preferences;
  Object? _error;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await widget.repository.loadPreferences();
      if (mounted) {
        setState(() {
          _preferences = preferences;
          _isLoading = false;
          _error = null;
        });
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

  Future<void> _save(NotificationPreferences updated) async {
    final previous = _preferences;
    if (_isSaving || previous == null) {
      return;
    }
    setState(() {
      _preferences = updated;
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.repository.savePreferences(updated);
      if (mounted) {
        setState(() => _isSaving = false);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _preferences = previous;
          _isSaving = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _setPushEnabled(bool enabled) async {
    final preferences = _preferences;
    if (preferences == null || _isSaving) return;

    if (!enabled) {
      await _save(preferences.copyWith(pushNotificationsEnabled: false));
      return;
    }

    if (!_pushService.isSupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Device push is available on Android. The in-app inbox still '
              'works on this platform.',
            ),
          ),
        );
      }
      return;
    }

    final granted = await _pushService.requestPermission();
    if (!mounted) return;
    if (granted) {
      await _save(preferences.copyWith(pushNotificationsEnabled: true));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification permission was not granted.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : preferences == null
          ? Center(child: Text('Could not load preferences: $_error'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Choose which Module 5 alerts appear in the inbox and as '
                  'Android device notifications.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Android push notifications'),
                  subtitle: Text(
                    _pushService.isSupported
                        ? 'Shows new enabled alerts while NextRoute is running.'
                        : 'Android only; the in-app inbox works here.',
                  ),
                  value:
                      preferences.pushNotificationsEnabled &&
                      _pushService.isSupported,
                  onChanged: _isSaving ? null : _setPushEnabled,
                ),
                const Divider(),
                _toggle(
                  'Realtime data alerts',
                  'Feed unavailable or stale warnings.',
                  Icons.sync_problem,
                  preferences.realtimeDataAlertsEnabled,
                  (value) =>
                      preferences.copyWith(realtimeDataAlertsEnabled: value),
                ),
                _toggle(
                  'Service alerts',
                  'General service and operator announcements.',
                  Icons.directions_bus_outlined,
                  preferences.serviceAlertsEnabled,
                  (value) => preferences.copyWith(serviceAlertsEnabled: value),
                ),
                _toggle(
                  'Delay alerts',
                  'Received delay notices; no GPS delay calculation.',
                  Icons.schedule,
                  preferences.delayAlertsEnabled,
                  (value) => preferences.copyWith(delayAlertsEnabled: value),
                ),
                _toggle(
                  'Congestion alerts',
                  'Alerts from reported vehicle congestion levels.',
                  Icons.traffic,
                  preferences.crowdAlertsEnabled,
                  (value) => preferences.copyWith(crowdAlertsEnabled: value),
                ),
                if (_isSaving) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    'Could not save preferences: $_error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _toggle(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    NotificationPreferences Function(bool) update,
  ) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: _isSaving ? null : (next) => _save(update(next)),
    );
  }
}
