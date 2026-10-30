import 'dart:convert';

import 'entities.dart';

class WeightRecord {
  final DateTime time;
  final double kg; // always stored in kilograms
  final String memberId;
  final String? deviceId;

  const WeightRecord({
    required this.time,
    required this.kg,
    this.memberId = kDefaultMemberId,
    this.deviceId,
  });

  WeightRecord copyWith({
    DateTime? time,
    double? kg,
    String? memberId,
    String? deviceId,
  }) =>
      WeightRecord(
        time: time ?? this.time,
        kg: kg ?? this.kg,
        memberId: memberId ?? this.memberId,
        deviceId: deviceId ?? this.deviceId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeightRecord &&
          other.time == time &&
          other.kg == kg &&
          other.memberId == memberId &&
          other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(time, kg, memberId, deviceId);

  Map<String, dynamic> toJson() => {
        't': time.millisecondsSinceEpoch,
        'kg': kg,
        'm': memberId,
        if (deviceId != null) 'd': deviceId,
      };

  factory WeightRecord.fromJson(Map<String, dynamic> json) => WeightRecord(
        time: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
        kg: (json['kg'] as num).toDouble(),
        memberId: json['m'] as String? ?? kDefaultMemberId,
        deviceId: json['d'] as String?,
      );

  static String encodeList(List<WeightRecord> records) =>
      jsonEncode(records.map((r) => r.toJson()).toList());

  static List<WeightRecord> decodeList(String source) {
    if (source.isEmpty) return <WeightRecord>[];
    final List<dynamic> raw = jsonDecode(source) as List<dynamic>;
    return raw
        .map((e) => WeightRecord.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }
}
