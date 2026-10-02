import '../core/time.dart';

/// A notification row from `GET /api/v1/notifications/`.
///
/// Backend NotificationSerializer fields:
/// id, title, body, type, is_read, sent_at (nullable), created_at.
class AppNotification {
  final int id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime? sentAt;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.sentAt,
    required this.createdAt,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    title: title,
    body: body,
    type: type,
    isRead: isRead ?? this.isRead,
    sentAt: sentAt,
    createdAt: createdAt,
  );

  /// Best timestamp to display (sent, else created).
  DateTime? get timestamp => sentAt ?? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['title'] ?? '') as String,
        body: (json['body'] ?? '') as String,
        type: (json['type'] ?? '') as String,
        isRead: (json['is_read'] ?? false) as bool,
        sentAt: _parseDate(json['sent_at']),
        createdAt: _parseDate(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'type': type,
    'is_read': isRead,
    'sent_at': sentAt?.toIso8601String(),
    'created_at': createdAt?.toIso8601String(),
  };

  /// Notification times carry `+08:00`; kept as exact instants (UTC).
  static DateTime? _parseDate(dynamic value) => parseApiInstant(value);
}
