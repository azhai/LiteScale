/// Illustrated avatars bundled under assets/avatars. They are local-only
/// decoration (never part of CSV export/import), stored by id in prefs.
const List<String> kAvatarIds = <String>[
  'a01', 'a02', 'a03', 'a04', 'a05', 'a06', 'a07', 'a08',
  'a09', 'a10', 'a11', 'a12', 'a13', 'a14', 'a15', 'a16',
  'a17', 'a18', 'a19', 'a20', 'a21', 'a22', 'a23', 'a24',
  'a25', 'a26', 'a27', 'a28', 'a29', 'a30', 'a31', 'a32',
  'a33', 'a34', 'a35', 'a36', 'a37', 'a38', 'a39', 'a40',
  'a41', 'a42', 'a43', 'a44', 'a45', 'a46', 'a47', 'a48',
];

/// Legacy emoji avatars (and any unknown value) map to a stable id so users
/// keep a distinct-looking avatar after the switch to illustrated ones.
String normalizeAvatarId(String avatar, {String seed = ''}) {
  if (kAvatarIds.contains(avatar)) return avatar;
  // djb2 stays within 2^41, so it agrees on VM and web (JS numbers).
  int hash = 5381;
  for (final int unit in '$seed|$avatar'.codeUnits) {
    hash = (hash * 33 + unit) & 0xffffffff;
  }
  return kAvatarIds[hash % kAvatarIds.length];
}

String avatarAssetPath(String avatar, {String seed = ''}) =>
    'assets/avatars/${normalizeAvatarId(avatar, seed: seed)}.png';

/// One dated goal for a member: reach [targetKg] on [date] (yyyy-MM-dd).
/// The actual weight is not stored — it is the last reading of that day.
class MemberGoal {
  final String date;
  final double targetKg;

  const MemberGoal({required this.date, required this.targetKg});

  MemberGoal copyWith({String? date, double? targetKg}) => MemberGoal(
        date: date ?? this.date,
        targetKg: targetKg ?? this.targetKg,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'kg': targetKg,
      };

  factory MemberGoal.fromJson(Map<String, dynamic> json) => MemberGoal(
        date: json['date'] as String? ?? '',
        targetKg: (json['kg'] as num?)?.toDouble() ?? 0,
      );
}

/// A household member whose measurements are tracked separately.
class Member {
  final String id;
  final String name;
  final String avatar; // id from kAvatarIds
  final int colorIndex;
  final double? heightCm;
  final String gender; // '', 'female' or 'male'
  final String birth; // yyyy-MM, empty when unset
  final List<MemberGoal> goals; // sorted by date ascending

  const Member({
    required this.id,
    required this.name,
    this.avatar = 'a01',
    this.colorIndex = 0,
    this.heightCm,
    this.gender = '',
    this.birth = '',
    this.goals = const <MemberGoal>[],
  });

  Member copyWith({
    String? name,
    String? avatar,
    int? colorIndex,
    double? heightCm,
    String? gender,
    String? birth,
    List<MemberGoal>? goals,
  }) =>
      Member(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        colorIndex: colorIndex ?? this.colorIndex,
        heightCm: heightCm ?? this.heightCm,
        gender: gender ?? this.gender,
        birth: birth ?? this.birth,
        goals: goals ?? this.goals,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'avatar': avatar,
        'color': colorIndex,
        if (heightCm != null) 'heightCm': heightCm,
        if (gender.isNotEmpty) 'gender': gender,
        if (birth.isNotEmpty) 'birth': birth,
        if (goals.isNotEmpty)
          'goals': <Map<String, dynamic>>[
            for (final MemberGoal g in goals) g.toJson(),
          ],
      };

  factory Member.fromJson(Map<String, dynamic> json) {
    final List<MemberGoal> goals = <MemberGoal>[
      for (final dynamic g in (json['goals'] as List<dynamic>? ?? <dynamic>[]))
        MemberGoal.fromJson(g as Map<String, dynamic>),
    ]..sort((MemberGoal a, MemberGoal b) => a.date.compareTo(b.date));
    final String id = json['id'] as String;
    return Member(
      id: id,
      name: json['name'] as String,
      avatar: normalizeAvatarId(json['avatar'] as String? ?? '', seed: id),
      colorIndex: json['color'] as int? ?? 0,
      heightCm: (json['heightCm'] as num?)?.toDouble(),
      gender: json['gender'] as String? ?? '',
      birth: json['birth'] as String? ?? '',
      goals: goals,
    );
  }
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

  Map<String, dynamic> toJson() => <String, dynamic>{
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
