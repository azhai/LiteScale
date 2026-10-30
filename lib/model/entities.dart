/// Avatars are local-only decoration: an emoji + a colour index. They are never
/// part of the CSV export/import.
const List<String> kAvatarEmojis = <String>[
  '🙂', '😎', '🧑', '👩', '👨', '👦', '👧', '🧓', '🐱', '🐶', '🏃', '💪',
];

/// A household member whose measurements are tracked separately.
class Member {
  final String id;
  final String name;
  final String avatar; // emoji
  final int colorIndex;

  const Member({
    required this.id,
    required this.name,
    this.avatar = '🙂',
    this.colorIndex = 0,
  });

  Member copyWith({String? name, String? avatar, int? colorIndex}) => Member(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        colorIndex: colorIndex ?? this.colorIndex,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'color': colorIndex,
      };

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        name: json['name'] as String,
        avatar: json['avatar'] as String? ?? '🙂',
        colorIndex: json['color'] as int? ?? 0,
      );
}

/// A scale that has been seen during a scan.
class ScaleDevice {
  final String id; // Android: MAC, iOS: 128-bit uuid
  final String name;
  final DateTime lastSeen;

  const ScaleDevice({
    required this.id,
    required this.name,
    required this.lastSeen,
  });

  ScaleDevice copyWith({String? name, DateTime? lastSeen}) => ScaleDevice(
        id: id,
        name: name ?? this.name,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'seen': lastSeen.millisecondsSinceEpoch,
      };

  factory ScaleDevice.fromJson(Map<String, dynamic> json) => ScaleDevice(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
          json['seen'] as int? ?? 0,
        ),
      );
}

const String kDefaultMemberId = 'me';
