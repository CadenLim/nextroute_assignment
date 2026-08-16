class NotificationPreferences {
  const NotificationPreferences({
    required this.serviceAlertsEnabled,
    required this.delayAlertsEnabled,
    required this.crowdAlertsEnabled,
  });

  const NotificationPreferences.defaults()
    : serviceAlertsEnabled = true,
      delayAlertsEnabled = true,
      crowdAlertsEnabled = true;

  final bool serviceAlertsEnabled;
  final bool delayAlertsEnabled;
  final bool crowdAlertsEnabled;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      serviceAlertsEnabled: _readBool(json['serviceAlertsEnabled']),
      delayAlertsEnabled: _readBool(json['delayAlertsEnabled']),
      crowdAlertsEnabled: _readBool(json['crowdAlertsEnabled']),
    );
  }

  Map<String, Object> toJson() {
    return {
      'serviceAlertsEnabled': serviceAlertsEnabled,
      'delayAlertsEnabled': delayAlertsEnabled,
      'crowdAlertsEnabled': crowdAlertsEnabled,
    };
  }

  NotificationPreferences copyWith({
    bool? serviceAlertsEnabled,
    bool? delayAlertsEnabled,
    bool? crowdAlertsEnabled,
  }) {
    return NotificationPreferences(
      serviceAlertsEnabled: serviceAlertsEnabled ?? this.serviceAlertsEnabled,
      delayAlertsEnabled: delayAlertsEnabled ?? this.delayAlertsEnabled,
      crowdAlertsEnabled: crowdAlertsEnabled ?? this.crowdAlertsEnabled,
    );
  }

  static bool _readBool(Object? value) {
    return value is bool ? value : true;
  }
}
