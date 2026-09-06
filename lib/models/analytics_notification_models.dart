enum TransitCongestionLevel { unknown, smooth, stopAndGo, congested, severe }

enum RealtimeFeedAvailability { live, noVehicleData, stale, unavailable }

class RealtimeFeedStatus {
  const RealtimeFeedStatus({
    required this.category,
    required this.availability,
    required this.entityCount,
    required this.vehicleCount,
    this.latestUpdate,
    this.error,
  });

  final String category;
  final RealtimeFeedAvailability availability;
  final int? entityCount;
  final int? vehicleCount;
  final DateTime? latestUpdate;
  final String? error;
}

class RealtimeVehicle {
  const RealtimeVehicle({
    required this.routeId,
    required this.timestamp,
    this.congestionLevel = TransitCongestionLevel.unknown,
    this.sourceCategory,
    this.vehicleId,
    this.tripId,
  });

  final String? routeId;
  final DateTime? timestamp;
  final TransitCongestionLevel congestionLevel;
  final String? sourceCategory;
  final String? vehicleId;
  final String? tripId;
}

class VehiclePositionFeed {
  const VehiclePositionFeed({
    required this.totalEntities,
    required this.vehicles,
    this.sources = const [],
  });

  final int totalEntities;
  final List<RealtimeVehicle> vehicles;
  final List<RealtimeFeedStatus> sources;
}

class ServiceAnalytics {
  const ServiceAnalytics({
    required this.vehicleCount,
    required this.routeCount,
    required this.vehiclesByRoute,
    required this.latestUpdate,
    this.congestedVehicleCount = 0,
    this.severeCongestionCount = 0,
    this.congestionReportedVehicleCount = 0,
    this.sourceStatuses = const [],
    this.latestUpdateByRoute = const {},
  });

  final int vehicleCount;
  final int routeCount;
  final Map<String, int> vehiclesByRoute;
  final DateTime? latestUpdate;
  final int congestedVehicleCount;
  final int severeCongestionCount;
  final int congestionReportedVehicleCount;
  final List<RealtimeFeedStatus> sourceStatuses;
  final Map<String, DateTime> latestUpdateByRoute;

  double? get congestionRate => congestionReportedVehicleCount == 0
      ? null
      : congestedVehicleCount * 100 / congestionReportedVehicleCount;
}

class DailyAnalyticsSummary {
  const DailyAnalyticsSummary({
    required this.serviceDate,
    required this.sampleCount,
    required this.successfulSampleCount,
    required this.failedSampleCount,
    required this.averageVehicleCount,
    required this.averageRouteCount,
    required this.averageCongestedVehicleCount,
    required this.averageSevereCongestionCount,
    required this.averageCongestionRate,
    required this.feedSuccessRate,
    required this.peakVehicleCount,
    required this.peakCongestedVehicleCount,
    required this.peakSevereCongestionCount,
    this.qualitySampleCount = 0,
    this.emptySampleCount = 0,
    this.staleSampleCount = 0,
    this.unknownFreshnessSampleCount = 0,
    this.congestionReportedObservationCount = 0,
  });

  final DateTime serviceDate;
  final int sampleCount;
  final int successfulSampleCount;
  final int failedSampleCount;
  final double averageVehicleCount;
  final double averageRouteCount;
  final double averageCongestedVehicleCount;
  final double averageSevereCongestionCount;
  final double? averageCongestionRate;
  final double feedSuccessRate;
  final int peakVehicleCount;
  final int peakCongestedVehicleCount;
  final int peakSevereCongestionCount;
  final int qualitySampleCount;
  final int emptySampleCount;
  final int staleSampleCount;
  final int unknownFreshnessSampleCount;
  final int congestionReportedObservationCount;

  factory DailyAnalyticsSummary.fromSupabase(Map<String, dynamic> json) {
    final serviceDate = DateTime.tryParse('${json['service_date']}');
    if (serviceDate == null) {
      throw const FormatException('Invalid analytics service date.');
    }
    return DailyAnalyticsSummary(
      serviceDate: DateTime.utc(
        serviceDate.year,
        serviceDate.month,
        serviceDate.day,
      ),
      sampleCount: _readInt(json['sample_count']),
      successfulSampleCount: _readInt(json['successful_sample_count']),
      failedSampleCount: _readInt(json['failed_sample_count']),
      averageVehicleCount: _readDouble(json['average_vehicle_count']),
      averageRouteCount: _readDouble(json['average_route_count']),
      averageCongestedVehicleCount: _readDouble(
        json['average_congested_vehicle_count'],
      ),
      averageSevereCongestionCount: _readDouble(
        json['average_severe_congestion_count'],
      ),
      // Legacy snapshots did not distinguish unknown congestion from zero.
      averageCongestionRate:
          _readInt(json['congestion_reported_observation_count']) > 0 &&
              json['average_congestion_rate'] != null
          ? _readRate(json['average_congestion_rate'])
          : null,
      feedSuccessRate: _readDouble(json['feed_success_rate']),
      peakVehicleCount: _readInt(json['peak_vehicle_count']),
      peakCongestedVehicleCount: _readInt(json['peak_congested_vehicle_count']),
      peakSevereCongestionCount: _readInt(json['peak_severe_congestion_count']),
      qualitySampleCount: _readInt(json['quality_sample_count']),
      emptySampleCount: _readInt(json['empty_sample_count']),
      staleSampleCount: _readInt(json['stale_sample_count']),
      unknownFreshnessSampleCount: _readInt(
        json['unknown_freshness_sample_count'],
      ),
      congestionReportedObservationCount: _readInt(
        json['congestion_reported_observation_count'],
      ),
    );
  }

  static int _readInt(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  static double _readDouble(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static double? _readRate(Object? value) {
    final rate = value is num ? value.toDouble() : double.tryParse('$value');
    return rate != null && rate.isFinite && rate >= 0 && rate <= 100
        ? rate
        : null;
  }
}

class NotificationPreferences {
  const NotificationPreferences({
    required this.serviceAlertsEnabled,
    required this.delayAlertsEnabled,
    required this.crowdAlertsEnabled,
    this.realtimeDataAlertsEnabled = true,
    this.pushNotificationsEnabled = false,
  });

  const NotificationPreferences.defaults()
    : serviceAlertsEnabled = true,
      delayAlertsEnabled = true,
      crowdAlertsEnabled = true,
      realtimeDataAlertsEnabled = true,
      pushNotificationsEnabled = false;

  final bool serviceAlertsEnabled;
  final bool delayAlertsEnabled;
  final bool crowdAlertsEnabled;
  final bool realtimeDataAlertsEnabled;
  final bool pushNotificationsEnabled;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      serviceAlertsEnabled: _readBool(json['serviceAlertsEnabled']),
      delayAlertsEnabled: _readBool(json['delayAlertsEnabled']),
      crowdAlertsEnabled: _readBool(json['crowdAlertsEnabled']),
      realtimeDataAlertsEnabled: _readBool(json['realtimeDataAlertsEnabled']),
      pushNotificationsEnabled: _readBool(
        json['pushNotificationsEnabled'],
        fallback: false,
      ),
    );
  }

  Map<String, Object> toJson() {
    return {
      'serviceAlertsEnabled': serviceAlertsEnabled,
      'delayAlertsEnabled': delayAlertsEnabled,
      'crowdAlertsEnabled': crowdAlertsEnabled,
      'realtimeDataAlertsEnabled': realtimeDataAlertsEnabled,
      'pushNotificationsEnabled': pushNotificationsEnabled,
    };
  }

  NotificationPreferences copyWith({
    bool? serviceAlertsEnabled,
    bool? delayAlertsEnabled,
    bool? crowdAlertsEnabled,
    bool? realtimeDataAlertsEnabled,
    bool? pushNotificationsEnabled,
  }) {
    return NotificationPreferences(
      serviceAlertsEnabled: serviceAlertsEnabled ?? this.serviceAlertsEnabled,
      delayAlertsEnabled: delayAlertsEnabled ?? this.delayAlertsEnabled,
      crowdAlertsEnabled: crowdAlertsEnabled ?? this.crowdAlertsEnabled,
      realtimeDataAlertsEnabled:
          realtimeDataAlertsEnabled ?? this.realtimeDataAlertsEnabled,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
    );
  }

  static bool _readBool(Object? value, {bool fallback = true}) =>
      value is bool ? value : fallback;
}

/// An archived public alert, independent of a user's read/preferences state.
class AnalyticsAlert {
  const AnalyticsAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.routeId,
    this.dedupeKey,
    this.delayMinutes,
    this.vehicleLabel,
    this.fromStop,
    this.toStop,
    this.direction,
    this.tripId,
    this.observedStopId,
    this.scheduledArrival,
    this.estimatedArrival,
    this.estimateMethod,
    this.observedSpeedKmh,
    this.observationDurationMinutes,
    this.confidence,
    this.expiresAt,
    this.isActive = true,
  });

  final String id;
  final TransitNotificationType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final String? routeId;
  final String? dedupeKey;
  final int? delayMinutes;
  final String? vehicleLabel;
  final String? fromStop;
  final String? toStop;
  final String? direction;
  final String? tripId;
  final String? observedStopId;
  final DateTime? scheduledArrival;
  final DateTime? estimatedArrival;
  final String? estimateMethod;
  final double? observedSpeedKmh;
  final int? observationDurationMinutes;
  final String? confidence;
  final DateTime? expiresAt;
  final bool isActive;

  bool get isDataHealth =>
      dedupeKey?.startsWith('data-health:') == true ||
      title == 'Realtime data unavailable';

  bool isCurrentAt(DateTime now) =>
      isActive && !createdAt.isAfter(now) && !isExpiredAt(now);

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  bool get isEstimatedDelay =>
      type == TransitNotificationType.delay &&
      (estimateMethod == 'schedule_stop_observation' ||
          estimateMethod == 'schedule_near_stop_position');

  bool get isEstimatedCongestion =>
      type == TransitNotificationType.crowd &&
      (estimateMethod == 'gps_low_speed_two_intervals' ||
          estimateMethod == 'gps_sustained_low_speed');

  factory AnalyticsAlert.fromSupabase(Map<String, dynamic> row) {
    final notification = TransitNotification.fromSupabase(row, isRead: false);
    return AnalyticsAlert(
      id: notification.id,
      type: notification.type,
      title: notification.title,
      message: notification.message,
      createdAt: notification.createdAt,
      routeId: notification.routeId,
      dedupeKey: row['dedupe_key'] as String?,
      delayMinutes: notification.delayMinutes,
      vehicleLabel: notification.vehicleLabel,
      fromStop: notification.fromStop,
      toStop: notification.toStop,
      direction: notification.direction,
      tripId: notification.tripId,
      observedStopId: notification.observedStopId,
      scheduledArrival: notification.scheduledArrival,
      estimatedArrival: notification.estimatedArrival,
      estimateMethod: notification.estimateMethod,
      observedSpeedKmh: notification.observedSpeedKmh,
      observationDurationMinutes: notification.observationDurationMinutes,
      confidence: notification.confidence,
      expiresAt: notification.expiresAt,
      isActive: notification.isActive,
    );
  }
}

enum TransitNotificationType { service, delay, crowd }

enum TransitNotificationOrigin { appGenerated, official }

enum NotificationSeverity { info, moderate, high, critical }

class TransitNotification {
  const TransitNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.routeId,
    required this.createdAt,
    required this.isRead,
    required this.origin,
    this.severity = NotificationSeverity.moderate,
    this.expiresAt,
    this.isActive = true,
    this.delayMinutes,
    this.vehicleLabel,
    this.fromStop,
    this.toStop,
    this.direction,
    this.tripId,
    this.observedStopId,
    this.scheduledArrival,
    this.estimatedArrival,
    this.estimateMethod,
    this.observedSpeedKmh,
    this.observationDurationMinutes,
    this.confidence,
  });

  final String id;
  final TransitNotificationType type;
  final String title;
  final String message;
  final String? routeId;
  final DateTime createdAt;
  final bool isRead;
  final TransitNotificationOrigin origin;
  final NotificationSeverity severity;
  final DateTime? expiresAt;
  final bool isActive;

  /// Publisher-supplied details, or clearly labelled schedule-observation
  /// estimates created by the Module 5 cloud collector.
  final int? delayMinutes;
  final String? vehicleLabel;
  final String? fromStop;
  final String? toStop;
  final String? direction;
  final String? tripId;
  final String? observedStopId;
  final DateTime? scheduledArrival;
  final DateTime? estimatedArrival;
  final String? estimateMethod;
  final double? observedSpeedKmh;
  final int? observationDurationMinutes;
  final String? confidence;

  bool get isDataHealth =>
      title == 'Realtime data unavailable' ||
      message.startsWith('NextRoute could not collect');

  bool get isEstimatedDelay =>
      type == TransitNotificationType.delay &&
      (estimateMethod == 'schedule_stop_observation' ||
          estimateMethod == 'schedule_near_stop_position');

  bool get isEstimatedCongestion =>
      type == TransitNotificationType.crowd &&
      (estimateMethod == 'gps_low_speed_two_intervals' ||
          estimateMethod == 'gps_sustained_low_speed');

  String get delayLabel => delayMinutes == null
      ? 'Delay duration not provided'
      : '${isEstimatedDelay ? 'Estimated' : 'Reported'} delay: $delayMinutes min';

  bool matchesSearch(String query, {String routeName = ''}) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final text = [
      title,
      message,
      routeId,
      routeName,
      vehicleLabel,
      fromStop,
      toStop,
      direction,
      tripId,
      observedStopId,
    ].whereType<String>().join(' ').toLowerCase();
    return words.every(text.contains);
  }

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  bool isCurrentAt(DateTime now) =>
      isActive && !createdAt.isAfter(now) && !isExpiredAt(now);

  factory TransitNotification.fromSupabase(
    Map<String, dynamic> json, {
    required bool isRead,
  }) {
    return TransitNotification(
      id: _requiredString(json, 'id'),
      type: _parseType(json['notification_type']),
      title: _requiredString(json, 'title'),
      message: _requiredString(json, 'message'),
      routeId: _optionalString(json['route_id']),
      createdAt: _parseDateTime(json['created_at']),
      isRead: isRead,
      origin: _parseSupabaseOrigin(json['origin']),
      severity: _parseSeverity(json['severity']),
      expiresAt: json['expires_at'] == null
          ? null
          : _parseDateTime(json['expires_at']),
      isActive: json['is_active'] == null ? true : json['is_active'] == true,
      delayMinutes: _optionalMinutes(json['delay_minutes']),
      vehicleLabel: _detailText(json['vehicle_label']),
      fromStop: _detailText(json['from_stop']),
      toStop: _detailText(json['to_stop']),
      direction: _detailText(json['direction']),
      tripId: _detailText(json['trip_id']),
      observedStopId: _detailText(json['observed_stop_id']),
      scheduledArrival: _optionalDateTime(json['scheduled_arrival']),
      estimatedArrival: _optionalDateTime(json['estimated_arrival']),
      estimateMethod: _detailText(json['estimate_method']),
      observedSpeedKmh: _optionalDouble(json['observed_speed_kmh']),
      observationDurationMinutes: _optionalMinutes(
        json['observation_duration_minutes'],
      ),
      confidence: _detailText(json['confidence']),
    );
  }

  TransitNotification copyWith({bool? isRead}) {
    return TransitNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      routeId: routeId,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      origin: origin,
      severity: severity,
      expiresAt: expiresAt,
      isActive: isActive,
      delayMinutes: delayMinutes,
      vehicleLabel: vehicleLabel,
      fromStop: fromStop,
      toStop: toStop,
      direction: direction,
      tripId: tripId,
      observedStopId: observedStopId,
      scheduledArrival: scheduledArrival,
      estimatedArrival: estimatedArrival,
      estimateMethod: estimateMethod,
      observedSpeedKmh: observedSpeedKmh,
      observationDurationMinutes: observationDurationMinutes,
      confidence: confidence,
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw FormatException('Invalid or missing $key.');
  }

  // Invalid optional details must not suppress an otherwise valid warning.
  static int? _optionalMinutes(Object? value) =>
      value is int && value >= 0 && value <= 1440 ? value : null;

  static double? _optionalDouble(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static String? _detailText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static DateTime? _optionalDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static String? _optionalString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    throw const FormatException('Invalid routeId.');
  }

  static DateTime _parseDateTime(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    throw const FormatException('Invalid or missing createdAt.');
  }

  static TransitNotificationType _parseType(Object? value) {
    if (value is String) {
      for (final type in TransitNotificationType.values) {
        if (type.name == value) {
          return type;
        }
      }
    }
    throw const FormatException('Invalid or missing notification type.');
  }

  static TransitNotificationOrigin _parseSupabaseOrigin(Object? value) {
    return switch (value) {
      'official' => TransitNotificationOrigin.official,
      'appGenerated' => TransitNotificationOrigin.appGenerated,
      _ => throw const FormatException('Invalid notification origin.'),
    };
  }

  static NotificationSeverity _parseSeverity(Object? value) {
    if (value == null) {
      return NotificationSeverity.moderate;
    }
    if (value is String) {
      for (final severity in NotificationSeverity.values) {
        if (severity.name == value) {
          return severity;
        }
      }
    }
    throw const FormatException('Invalid notification severity.');
  }
}
