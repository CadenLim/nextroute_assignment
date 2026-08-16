import 'package:nextroute_assignment/modules/analytics_notification/data/models/service_analytics.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/transit_notification.dart';

const realtimeDataStaleThreshold = Duration(minutes: 2);
const staleRealtimeDataNotificationId = 'app-realtime-data-stale';
const unavailableRealtimeDataNotificationId = 'app-realtime-data-unavailable';

class RealtimeDataHealthAlertEngine {
  RealtimeDataHealthAlertEngine({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  int _consecutiveFailureCount = 0;

  int get consecutiveFailureCount => _consecutiveFailureCount;

  TransitNotification? recordSuccessfulFetch(ServiceAnalytics analytics) {
    _consecutiveFailureCount = 0;

    final latestUpdate = analytics.latestUpdate;
    if (latestUpdate == null) {
      return null;
    }

    final now = _now().toUtc();
    final dataAge = now.difference(latestUpdate.toUtc());
    if (dataAge <= realtimeDataStaleThreshold) {
      return null;
    }

    return TransitNotification(
      id: staleRealtimeDataNotificationId,
      type: TransitNotificationType.service,
      title: 'Realtime data may be outdated',
      message:
          'NextRoute detected that the latest Rapid Bus KL vehicle-position '
          'timestamp received by the app is more than 2 minutes old. This is '
          'a NextRoute data-freshness warning, not an official Rapid KL '
          'disruption alert. The 2-minute threshold is a NextRoute '
          'application rule.',
      routeId: null,
      createdAt: now,
      isRead: false,
      origin: TransitNotificationOrigin.appGenerated,
    );
  }

  TransitNotification? recordFailedFetch() {
    _consecutiveFailureCount += 1;
    if (_consecutiveFailureCount < 3) {
      return null;
    }

    return TransitNotification(
      id: unavailableRealtimeDataNotificationId,
      type: TransitNotificationType.service,
      title: 'Realtime data unavailable',
      message:
          'NextRoute could not retrieve Rapid Bus KL realtime '
          'vehicle-position data after 3 consecutive attempts. This is an '
          'app-generated data-access warning, not an official Rapid KL '
          'service alert.',
      routeId: null,
      createdAt: _now().toUtc(),
      isRead: false,
      origin: TransitNotificationOrigin.appGenerated,
    );
  }
}
