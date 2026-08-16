class NotificationPreferences {
  const NotificationPreferences({
    required this.serviceAlertsEnabled,
    required this.delayAlertsEnabled,
    required this.crowdAlertsEnabled,
    this.realtimeDataAlertsEnabled = true,
  });

  const NotificationPreferences.defaults()
    : serviceAlertsEnabled = true,
      delayAlertsEnabled = true,
      crowdAlertsEnabled = true,
      realtimeDataAlertsEnabled = true;

  final bool serviceAlertsEnabled;
  final bool delayAlertsEnabled;
  final bool crowdAlertsEnabled;
  final bool realtimeDataAlertsEnabled;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      serviceAlertsEnabled: _readBool(json['serviceAlertsEnabled']),
      delayAlertsEnabled: _readBool(json['delayAlertsEnabled']),
      crowdAlertsEnabled: _readBool(json['crowdAlertsEnabled']),
      realtimeDataAlertsEnabled: _readBool(json['realtimeDataAlertsEnabled']),
    );
  }

  Map<String, Object> toJson() {
    return {
      'serviceAlertsEnabled': serviceAlertsEnabled,
      'delayAlertsEnabled': delayAlertsEnabled,
      'crowdAlertsEnabled': crowdAlertsEnabled,
      'realtimeDataAlertsEnabled': realtimeDataAlertsEnabled,
    };
  }

  NotificationPreferences copyWith({
    bool? serviceAlertsEnabled,
    bool? delayAlertsEnabled,
    bool? crowdAlertsEnabled,
    bool? realtimeDataAlertsEnabled,
  }) {
    return NotificationPreferences(
      serviceAlertsEnabled: serviceAlertsEnabled ?? this.serviceAlertsEnabled,
      delayAlertsEnabled: delayAlertsEnabled ?? this.delayAlertsEnabled,
      crowdAlertsEnabled: crowdAlertsEnabled ?? this.crowdAlertsEnabled,
      realtimeDataAlertsEnabled:
          realtimeDataAlertsEnabled ?? this.realtimeDataAlertsEnabled,
    );
  }

  static bool _readBool(Object? value) {
    return value is bool ? value : true;
  }
}
