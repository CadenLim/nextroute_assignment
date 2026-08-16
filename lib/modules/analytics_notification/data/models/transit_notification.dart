enum TransitNotificationType { service, delay, crowd }

class TransitNotification {
  const TransitNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.routeId,
    required this.createdAt,
    required this.isRead,
    required this.isDemo,
  });

  final String id;
  final TransitNotificationType type;
  final String title;
  final String message;
  final String? routeId;
  final DateTime createdAt;
  final bool isRead;
  final bool isDemo;

  factory TransitNotification.fromJson(Map<String, dynamic> json) {
    return TransitNotification(
      id: _requiredString(json, 'id'),
      type: _parseType(json['type']),
      title: _requiredString(json, 'title'),
      message: _requiredString(json, 'message'),
      routeId: _optionalString(json['routeId']),
      createdAt: _parseDateTime(json['createdAt']),
      isRead: _requiredBool(json, 'isRead'),
      isDemo: _requiredBool(json, 'isDemo'),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'message': message,
      'routeId': routeId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'isRead': isRead,
      'isDemo': isDemo,
    };
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
      isDemo: isDemo,
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

  static bool _requiredBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    throw FormatException('Invalid or missing $key.');
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
}
