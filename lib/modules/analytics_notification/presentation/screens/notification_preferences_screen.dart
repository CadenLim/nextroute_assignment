import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/notification_preferences.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/repositories/notification_repository.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({required this.repository, super.key});

  final NotificationRepository repository;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final preferences = await widget.repository.loadPreferences();
      if (!mounted) {
        return;
      }
      setState(() {
        _preferences = preferences;
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

  Future<void> _savePreferences(NotificationPreferences updated) async {
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
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _preferences = previous;
        _isSaving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final preferences = _preferences;
    if (preferences == null) {
      return _PreferencesError(error: _error, onRetry: _loadPreferences);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Foundation only: these local settings do not generate live '
              'alerts or operating-system notifications yet.',
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('Service alerts'),
          subtitle: const Text(
            'Store the local preference for service alerts.',
          ),
          value: preferences.serviceAlertsEnabled,
          onChanged: _isSaving
              ? null
              : (value) => _savePreferences(
                  preferences.copyWith(serviceAlertsEnabled: value),
                ),
        ),
        SwitchListTile(
          title: const Text('Delay alerts'),
          subtitle: const Text('Store the local preference for delay alerts.'),
          value: preferences.delayAlertsEnabled,
          onChanged: _isSaving
              ? null
              : (value) => _savePreferences(
                  preferences.copyWith(delayAlertsEnabled: value),
                ),
        ),
        SwitchListTile(
          title: const Text('Crowd alerts'),
          subtitle: const Text('Store the local preference for crowd alerts.'),
          value: preferences.crowdAlertsEnabled,
          onChanged: _isSaving
              ? null
              : (value) => _savePreferences(
                  preferences.copyWith(crowdAlertsEnabled: value),
                ),
        ),
        if (_isSaving) const LinearProgressIndicator(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            'Could not save notification preferences: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _PreferencesError extends StatelessWidget {
  const _PreferencesError({required this.error, required this.onRetry});

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
            Text('Could not load preferences: $error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
