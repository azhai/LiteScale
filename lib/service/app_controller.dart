import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/strings.dart';
import '../model/entities.dart';
import '../model/weight_record.dart';
import 'units.dart';

/// Single source of truth for settings, members, devices and measurements.
class AppController extends ChangeNotifier {
  static const String _kLang = 'lang';
  static const String _kUnit = 'unit';
  static const String _kLegacyHeight = 'heightCm';
  static const String _kDark = 'darkMode';
  static const String _kLegacyGoal = 'goalKg';
  static const String _kRecords = 'records';
  static const String _kMembers = 'members';
  static const String _kActiveMember = 'activeMember';
  static const String _kDevices = 'devices';

  AppLang _lang = AppLang.en;
  String _unit = 'jin';
  bool _darkMode = false;

  List<Member> _members = <Member>[];
  String _activeMemberId = kDefaultMemberId;
  List<ScaleDevice> _devices = <ScaleDevice>[];
  List<WeightRecord> _records = <WeightRecord>[];

  SharedPreferences? _prefs;

  AppLang get lang => _lang;
  String get unit => _unit;
  bool get darkMode => _darkMode;
  S get s => S(_lang);

  List<Member> get members => List.unmodifiable(_members);
  String get activeMemberId => _activeMemberId;
  Member get activeMember => _memberById(_activeMemberId);
  List<ScaleDevice> get devices => List.unmodifiable(_devices);
  List<WeightRecord> get records => List.unmodifiable(_records);

  Member _memberById(String id) {
    for (final Member m in _members) {
      if (m.id == id) return m;
    }
    return _members.isEmpty
        ? const Member(id: kDefaultMemberId, name: 'Me')
        : _members.first;
  }

  Member memberOf(WeightRecord r) => _memberById(r.memberId);

  String? deviceNameOf(WeightRecord r) {
    if (r.deviceId == null) return null;
    for (final ScaleDevice d in _devices) {
      if (d.id == r.deviceId) {
        return d.name.isEmpty ? d.id : d.name;
      }
    }
    return r.deviceId;
  }

  // --- lifecycle ---------------------------------------------------------

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    final String storedLang = _prefs!.getString(_kLang) ?? '';
    if (storedLang.isNotEmpty) {
      _lang = storedLang == 'zh' ? AppLang.zh : AppLang.en;
    } else {
      final String systemLocale =
          PlatformDispatcher.instance.locale.languageCode.toLowerCase();
      _lang = systemLocale.startsWith('zh') ? AppLang.zh : AppLang.en;
    }

    _unit = _prefs!.getString(_kUnit) ?? 'jin';
    if (!Units.all.contains(_unit)) _unit = 'jin';
    _darkMode = _prefs!.getBool(_kDark) ?? false;

    final String membersRaw = _prefs!.getString(_kMembers) ?? '';
    _members = _decodeMembers(membersRaw);
    if (_members.isEmpty) {
      _members = <Member>[
        Member(id: kDefaultMemberId, name: _lang == AppLang.zh ? '我' : 'Me'),
      ];
    }
    _activeMemberId = _prefs!.getString(_kActiveMember) ?? _members.first.id;
    if (!_members.any((Member m) => m.id == _activeMemberId)) {
      _activeMemberId = _members.first.id;
    }
    await _migrateLegacyBodySettings();

    final String devicesRaw = _prefs!.getString(_kDevices) ?? '';
    _devices = _decodeDevices(devicesRaw);

    _records = WeightRecord.decodeList(_prefs!.getString(_kRecords) ?? '');
    notifyListeners();
  }

  /// Height and goal used to be global; they belong to a member now.
  Future<void> _migrateLegacyBodySettings() async {
    final double? height = _prefs!.getDouble(_kLegacyHeight);
    final double? goal = _prefs!.getDouble(_kLegacyGoal);
    if (height == null && goal == null) return;
    _members = _members.map((Member m) {
      if (m.id != _activeMemberId) return m;
      return m.copyWith(
        heightCm: m.heightCm ?? height,
        goals: m.goals.isNotEmpty || goal == null
            ? m.goals
            : <MemberGoal>[MemberGoal(date: dayKey(DateTime.now()), targetKg: goal)],
      );
    }).toList();
    await _persistMembers();
    await _prefs!.remove(_kLegacyHeight);
    await _prefs!.remove(_kLegacyGoal);
  }

  List<Member> _decodeMembers(String raw) {
    if (raw.isEmpty) return <Member>[];
    try {
      final List<dynamic> list = jsonDecodeList(raw);
      return list
          .map((e) => Member.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Member>[];
    }
  }

  List<ScaleDevice> _decodeDevices(String raw) {
    if (raw.isEmpty) return <ScaleDevice>[];
    try {
      final List<dynamic> list = jsonDecodeList(raw);
      return list
          .map((e) => ScaleDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <ScaleDevice>[];
    }
  }

  // --- settings ----------------------------------------------------------

  Future<void> setLang(AppLang value) async {
    _lang = value;
    await _prefs?.setString(_kLang, value == AppLang.zh ? 'zh' : 'en');
    notifyListeners();
  }

  Future<void> setUnit(String value) async {
    _unit = value;
    await _prefs?.setString(_kUnit, value);
    notifyListeners();
  }

  /// Height belongs to a member; [memberId] defaults to the active member.
  Future<void> setHeightCm(double value, {String? memberId}) async {
    final String id = memberId ?? _activeMemberId;
    _members = _members
        .map((Member m) => m.id == id ? m.copyWith(heightCm: value) : m)
        .toList();
    await _persistMembers();
    notifyListeners();
  }

  /// Gender and birth month (yyyy-MM); empty strings clear them.
  Future<void> setMemberDetails(
    String id, {
    String? gender,
    String? birth,
  }) async {
    _members = _members
        .map((Member m) =>
            m.id == id ? m.copyWith(gender: gender, birth: birth) : m)
        .toList();
    await _persistMembers();
    notifyListeners();
  }

  /// Adds or replaces the goal for [memberGoal.date] (one goal per day).
  Future<void> setMemberGoal(
    MemberGoal memberGoal, {
    String? memberId,
  }) async {
    final String id = memberId ?? _activeMemberId;
    _members = _members.map((Member m) {
      if (m.id != id) return m;
      final List<MemberGoal> goals = <MemberGoal>[
        for (final MemberGoal g in m.goals)
          if (g.date != memberGoal.date) g,
        memberGoal,
      ]..sort((MemberGoal a, MemberGoal b) => a.date.compareTo(b.date));
      return m.copyWith(goals: goals);
    }).toList();
    await _persistMembers();
    notifyListeners();
  }

  Future<void> removeMemberGoal(String date, {String? memberId}) async {
    final String id = memberId ?? _activeMemberId;
    _members = _members
        .map((Member m) => m.id == id
            ? m.copyWith(
                goals: m.goals
                    .where((MemberGoal g) => g.date != date)
                    .toList())
            : m)
        .toList();
    await _persistMembers();
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    await _prefs?.setBool(_kDark, value);
    notifyListeners();
  }

  // --- members -----------------------------------------------------------

  Future<void> setActiveMember(String id) async {
    _activeMemberId = id;
    await _prefs?.setString(_kActiveMember, id);
    notifyListeners();
  }

  /// Ids are millisecond-based, so bump past any id already taken; two members
  /// added within the same millisecond must not collide.
  String _newMemberId() {
    int ms = DateTime.now().millisecondsSinceEpoch;
    String id = 'm$ms';
    while (_members.any((Member m) => m.id == id)) {
      id = 'm${++ms}';
    }
    return id;
  }

  Future<Member> addMember(String name) async {
    final Member member = Member(
      id: _newMemberId(),
      name: name.trim().isEmpty ? '${_members.length + 1}' : name.trim(),
      avatar: kAvatarIds[_members.length % kAvatarIds.length],
      colorIndex: _members.length % 6,
    );
    _members = <Member>[..._members, member];
    await _persistMembers();
    notifyListeners();
    return member;
  }

  Future<void> renameMember(String id, String name) async {
    if (name.trim().isEmpty) return;
    _members = _members
        .map((Member m) => m.id == id ? m.copyWith(name: name.trim()) : m)
        .toList();
    await _persistMembers();
    notifyListeners();
  }

  /// Avatar + colour are local decoration only (never exported).
  Future<void> setMemberAvatar(String id, {String? avatar, int? colorIndex}) async {
    _members = _members
        .map((Member m) => m.id == id
            ? m.copyWith(avatar: avatar, colorIndex: colorIndex)
            : m)
        .toList();
    await _persistMembers();
    notifyListeners();
  }

  /// Removes a member; their records are moved to the first remaining member.
  Future<void> removeMember(String id) async {
    if (_members.length <= 1) return;
    final List<Member> remaining =
        _members.where((Member m) => m.id != id).toList();
    final String fallback = remaining.first.id;
    _records = _records
        .map((WeightRecord r) => r.memberId == id ? r.copyWith(memberId: fallback) : r)
        .toList();
    _members = remaining;
    if (_activeMemberId == id) _activeMemberId = fallback;
    await _persistMembers();
    await _persistRecords();
    await _prefs?.setString(_kActiveMember, _activeMemberId);
    notifyListeners();
  }

  Future<void> _persistMembers() async =>
      _prefs?.setString(_kMembers, encodeJsonList(_members.map((m) => m.toJson())));

  // --- devices -----------------------------------------------------------

  /// Called for every advertisement that produces a reading, so the user can
  /// see which scales have been used and filter history by device.
  Future<void> rememberDevice(String id, String name) async {
    final DateTime now = DateTime.now();
    final int index = _devices.indexWhere((ScaleDevice d) => d.id == id);
    if (index >= 0) {
      final ScaleDevice existing = _devices[index];
      if (existing.name == name && now.difference(existing.lastSeen).inSeconds < 30) {
        return; // avoid writing on every advertisement
      }
      _devices = List<ScaleDevice>.from(_devices)
        ..[index] = existing.copyWith(
          name: name.isEmpty ? existing.name : name,
          lastSeen: now,
        );
    } else {
      _devices = <ScaleDevice>[
        ..._devices,
        ScaleDevice(id: id, name: name, lastSeen: now),
      ];
    }
    await _prefs?.setString(
      _kDevices,
      encodeJsonList(_devices.map((d) => d.toJson())),
    );
    notifyListeners();
  }

  Future<void> renameDevice(String id, String name) async {
    _devices = _devices
        .map((ScaleDevice d) => d.id == id ? d.copyWith(name: name) : d)
        .toList();
    await _prefs?.setString(
      _kDevices,
      encodeJsonList(_devices.map((d) => d.toJson())),
    );
    notifyListeners();
  }

  Future<void> removeDevice(String id) async {
    _devices = _devices.where((ScaleDevice d) => d.id != id).toList();
    await _prefs?.setString(
      _kDevices,
      encodeJsonList(_devices.map((d) => d.toJson())),
    );
    notifyListeners();
  }

  // --- records -----------------------------------------------------------

  /// Adds a measurement for the active member. Returns false when it is a
  /// duplicate of the previous reading (same weight within 60s).
  Future<bool> addRecord(double kg, {String? deviceId}) async {
    final WeightRecord record = WeightRecord(
      time: DateTime.now(),
      kg: kg,
      memberId: _activeMemberId,
      deviceId: deviceId,
    );
    final List<WeightRecord> sameMember =
        _records.where((r) => r.memberId == _activeMemberId).toList();
    if (sameMember.isNotEmpty) {
      final WeightRecord last = sameMember.last;
      final bool sameWeight = (last.kg - kg).abs() < 0.05;
      final bool tooSoon = record.time.difference(last.time).inSeconds.abs() < 60;
      if (sameWeight && tooSoon) return false;
    }
    _records = <WeightRecord>[..._records, record]
      ..sort((a, b) => a.time.compareTo(b.time));
    await _persistRecords();
    notifyListeners();
    return true;
  }

  Future<void> setRecordMember(WeightRecord record, String memberId) async {
    _records = _records
        .map((r) => r == record ? r.copyWith(memberId: memberId) : r)
        .toList();
    await _persistRecords();
    notifyListeners();
  }

  /// Merges imported records. Members referenced as `pending:<name>` are
  /// created first, duplicates (same time and weight) are skipped.
  /// Returns the number of records actually added.
  Future<int> importRecords(
    List<WeightRecord> incoming, {
    Map<String, String> deviceNames = const <String, String>{},
  }) async {
    for (final MapEntry<String, String> e in deviceNames.entries) {
      await rememberDevice(e.key, e.value);
    }

    final Map<String, String> pendingToId = <String, String>{};
    for (final WeightRecord r in incoming) {
      if (!r.memberId.startsWith('pending:')) continue;
      final String name = r.memberId.substring('pending:'.length);
      if (pendingToId.containsKey(name)) continue;
      final Member created = await addMember(name);
      pendingToId[name] = created.id;
    }

    final Set<String> existing = _records
        .map((WeightRecord r) => '${r.time.millisecondsSinceEpoch}|${r.kg}')
        .toSet();

    int added = 0;
    for (final WeightRecord raw in incoming) {
      final String memberId = raw.memberId.startsWith('pending:')
          ? (pendingToId[raw.memberId.substring('pending:'.length)] ??
              _members.first.id)
          : raw.memberId;
      final WeightRecord record = raw.copyWith(memberId: memberId);
      final String key = '${record.time.millisecondsSinceEpoch}|${record.kg}';
      if (!existing.add(key)) continue;
      _records.add(record);
      added++;
    }

    if (added > 0) {
      _records.sort((a, b) => a.time.compareTo(b.time));
      await _persistRecords();
      notifyListeners();
    }
    return added;
  }

  Future<void> removeRecord(WeightRecord record) async {
    _records = _records.where((r) => r != record).toList();
    await _persistRecords();
    notifyListeners();
  }

  Future<void> clearRecords() async {
    _records = <WeightRecord>[];
    await _persistRecords();
    notifyListeners();
  }

  Future<void> _persistRecords() async =>
      _prefs?.setString(_kRecords, WeightRecord.encodeList(_records));

  // --- queries -----------------------------------------------------------

  /// History filter: member, device and time window (0 days = everything).
  List<WeightRecord> filteredRecords({
    String? memberId,
    String? deviceId,
    int days = 0,
  }) {
    final DateTime? from =
        days == 0 ? null : DateTime.now().subtract(Duration(days: days));
    return _records.where((WeightRecord r) {
      if (memberId != null && r.memberId != memberId) return false;
      if (deviceId != null && r.deviceId != deviceId) return false;
      if (from != null && r.time.isBefore(from)) return false;
      return true;
    }).toList();
  }

  /// Height of a member (active member by default).
  double? heightCmOf([String? memberId]) {
    final double? h = _memberById(memberId ?? _activeMemberId).heightCm;
    return h != null && h > 0 ? h : null;
  }

  /// The next goal by date (or the most recent past one when all are past).
  MemberGoal? goalFor([String? memberId]) {
    final List<MemberGoal> goals = _memberById(memberId ?? _activeMemberId).goals;
    if (goals.isEmpty) return null;
    final String today = dayKey(DateTime.now());
    for (final MemberGoal g in goals) {
      if (g.date.compareTo(today) >= 0) return g;
    }
    return goals.last;
  }

  MemberGoal? get activeGoal => goalFor(_activeMemberId);

  /// Last reading on [date] (yyyy-MM-dd, local time), i.e. that day's actual
  /// weight for the goal.
  double? goalActualKg(String date, {String? memberId}) {
    final String id = memberId ?? _activeMemberId;
    WeightRecord? last;
    for (final WeightRecord r in _records) {
      if (r.memberId != id || dayKey(r.time) != date) continue;
      if (last == null || r.time.isAfter(last.time)) last = r;
    }
    return last?.kg;
  }

  double? bmiOf(double kg, {String? memberId}) {
    final double? h = heightCmOf(memberId);
    if (h == null) return null;
    final double m = h / 100;
    return kg / (m * m);
  }

  /// yyyy-MM-dd in local time.
  static String dayKey(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}

List<dynamic> jsonDecodeList(String raw) => _json.decode(raw) as List<dynamic>;

String encodeJsonList(Iterable<Map<String, dynamic>> items) =>
    _json.encode(items.toList());

const JsonCodec _json = JsonCodec();
