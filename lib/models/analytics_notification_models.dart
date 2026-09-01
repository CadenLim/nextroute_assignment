enum TransitCongestionLevel { unknown, smooth, stopAndGo, congested, severe }

class RealtimeVehicle {
  const RealtimeVehicle({
    required this.routeId,
    required this.timestamp,
    this.congestionLevel = TransitCongestionLevel.unknown,
  });

  final String? routeId;
  final DateTime? timestamp;
  final TransitCongestionLevel congestionLevel;
}

class VehiclePositionFeed {
  const VehiclePositionFeed({
    required this.totalEntities,
    required this.vehicles,
  });

  final int totalEntities;
  final List<RealtimeVehicle> vehicles;
}

class ServiceAnalytics {
  const ServiceAnalytics({
    required this.vehicleCount,
    required this.routeCount,
    required this.vehiclesByRoute,
    required this.latestUpdate,
    this.congestedVehicleCount = 0,
    this.severeCongestionCount = 0,
  });

  final int vehicleCount;
  final int routeCount;
  final Map<String, int> vehiclesByRoute;
  final DateTime? latestUpdate;
  final int congestedVehicleCount;
  final int severeCongestionCount;
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
  });

  final DateTime serviceDate;
  final int sampleCount;
  final int successfulSampleCount;
  final int failedSampleCount;
  final double averageVehicleCount;
  final double averageRouteCount;
  final double averageCongestedVehicleCount;
  final double averageSevereCongestionCount;
  final double averageCongestionRate;
  final double feedSuccessRate;
  final int peakVehicleCount;
  final int peakCongestedVehicleCount;
  final int peakSevereCongestionCount;

  factory DailyAnalyticsSummary.fromSupabase(Map<String, dynamic> json) {
    final serviceDate = DateTime.tryParse('${json['service_date']}');
    if (serviceDate == null) {
      throw const FormatException('Invalid analytics service date.');
    }
    return DailyAnalyticsSummary(
      serviceDate: serviceDate,
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
      averageCongestionRate: _readDouble(json['average_congestion_rate']),
      feedSuccessRate: _readDouble(json['feed_success_rate']),
      peakVehicleCount: _readInt(json['peak_vehicle_count']),
      peakCongestedVehicleCount: _readInt(json['peak_congested_vehicle_count']),
      peakSevereCongestionCount: _readInt(json['peak_severe_congestion_count']),
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
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw FormatException('Invalid or missing $key.');
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
