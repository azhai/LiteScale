import '../model/entities.dart';
import '../model/weight_record.dart';
import 'app_controller.dart';

/// CSV import / export for measurements.
///
/// Canonical columns: ts, client_id, device_id, device_name, member_id,
/// member_name, kg — the same layout the server exports and imports.
/// `ts` is Unix epoch seconds with exactly 3 decimals (millisecond precision).
/// `client_id` is this install's uploader id when one exists, blank otherwise;
/// import maps columns by header name. Rows without a valid timestamp or
/// weight are skipped.
class CsvService {
  static const String header =
      'ts,client_id,device_id,device_name,member_id,member_name,kg';

  // Compatibility: headers written by older builds or third-party tools.
  // Applied only after the canonical names, and never for new fields.
  static const Set<String> _timeHeaders = <String>{
    'ts', 'ts_ms', 't', 'timestamp_ms', 'timestamp', 'time',
  };
  static const Map<String, String> _legacyHeaders = <String, String>{
    'ts_ms': 'ts',
    't': 'ts',
    'timestamp_ms': 'ts',
    'timestamp': 'ts',
    'time': 'ts',
    'weight_kg': 'kg',
    'weight': 'kg',
  };

  /// Canonical `ts`: epoch seconds with exactly 3 decimals.
  static String formatTs(DateTime time) {
    final int ms = time.millisecondsSinceEpoch;
    return '${ms ~/ 1000}.${(ms % 1000).toString().padLeft(3, '0')}';
  }

  static String export(
    List<WeightRecord> records,
    AppController c, {
    String clientId = '',
  }) {
    final StringBuffer out = StringBuffer()
      ..writeln(header);
    for (final WeightRecord r in records) {
      out.writeln(<String>[
        formatTs(r.time),
        _escape(clientId),
        _escape(r.deviceId ?? ''),
        _escape(c.deviceNameOf(r) ?? ''),
        _escape(r.memberId),
        _escape(c.memberOf(r).name),
        r.kg.toStringAsFixed(3),
      ].join(','));
    }
    return out.toString();
  }

  /// Parses a CSV and returns records plus the members referenced by name.
  /// Members that do not exist yet are returned in [CsvImportResult.newMembers];
  /// `device_name` labels are returned in [CsvImportResult.deviceNames].
  static CsvImportResult parse(String source, AppController c) {
    final List<WeightRecord> records = <WeightRecord>[];
    final List<String> newMembers = <String>[];
    final Map<String, String> deviceNames = <String, String>{};

    final Map<String, String> memberIdByKey = <String, String>{};
    for (final Member m in c.members) {
      memberIdByKey[m.id] = m.id;
      memberIdByKey[m.name] = m.id;
    }

    final List<String> lines = source
        .split(RegExp(r'\r?\n'))
        .where((String l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return CsvImportResult(records, newMembers, deviceNames);
    }

    // Canonical columns first; compatibility aliases are applied last, so the
    // schema above stays the import contract. Headerless files fall back to
    // the positional layout of the original export.
    final List<String> first = _splitLine(lines.first);
    final bool hasHeader = first.any(
      (String cell) => _timeHeaders.contains(_normalizeHeader(cell)),
    );
    final Map<String, int> cols = <String, int>{};
    if (hasHeader) {
      for (int i = 0; i < first.length; i++) {
        cols[_normalizeHeader(first[i])] = i;
      }
      _legacyHeaders.forEach((String from, String to) {
        final int? i = cols[from];
        if (i != null && cols[to] == null) cols[to] = i;
      });
    }
    final int timeCol = hasHeader ? (cols['ts'] ?? -1) : 0;
    if (timeCol < 0) return CsvImportResult(records, newMembers, deviceNames);
    final int kgCol = hasHeader ? (cols['kg'] ?? -1) : -1;
    final int deviceCol = hasHeader ? (cols['device_id'] ?? -1) : 1;
    final int deviceNameCol = hasHeader ? (cols['device_name'] ?? -1) : 2;
    final int nameCol = hasHeader ? (cols['member_name'] ?? -1) : -1;
    final int idCol = hasHeader ? (cols['member_id'] ?? -1) : -1;

    for (int i = hasHeader ? 1 : 0; i < lines.length; i++) {
      final List<String> cells = _splitLine(lines[i]);
      if (cells.length < 2) continue;

      final DateTime? time = _parseTime(_cell(cells, timeCol));
      final double? kg =
          double.tryParse(_cell(cells, kgCol >= 0 ? kgCol : cells.length - 1));
      if (time == null || kg == null || kg <= 0) continue;

      final String deviceId = _cell(cells, deviceCol);
      final String deviceName = _cell(cells, deviceNameCol);
      if (deviceId.isNotEmpty && deviceName.isNotEmpty) {
        deviceNames[deviceId] = deviceName;
      }
      final String memberName = _cell(
        cells,
        hasHeader ? nameCol : (cells.length > 4 ? 4 : -1),
      );
      final String memberIdCell = _cell(
        cells,
        hasHeader ? idCol : (cells.length > 3 ? 3 : -1),
      );
      final String memberKey =
          memberName.isNotEmpty ? memberName : memberIdCell;

      String memberId = kDefaultMemberId;
      if (memberKey.isNotEmpty) {
        final String? known = memberIdByKey[memberKey];
        if (known != null) {
          memberId = known;
        } else if (memberKey.length > 20) {
          memberId = memberKey; // looks like an id, keep it
        } else {
          if (!newMembers.contains(memberKey)) newMembers.add(memberKey);
          memberId = 'pending:$memberKey';
        }
      }

      records.add(WeightRecord(
        time: time,
        kg: kg,
        memberId: memberId,
        deviceId: deviceId.isEmpty ? null : deviceId,
      ));
    }

    return CsvImportResult(records, newMembers, deviceNames);
  }

  static String _normalizeHeader(String value) =>
      value.toLowerCase().replaceAll('\ufeff', '').trim();

  static String _cell(List<String> cells, int index) =>
      index >= 0 && index < cells.length ? cells[index].trim() : '';

  /// Canonical `ts` is epoch seconds with 3 decimals. Epoch milliseconds and
  /// ISO-8601 are accepted for compatibility with older exports.
  static DateTime? _parseTime(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return null;
    final double? value = double.tryParse(text);
    if (value != null && value.isFinite) {
      final double ms = value.abs() < 100000000000 ? value * 1000 : value;
      // 2000-01-01 .. 2100-01-01; anything else is a broken column.
      if (!ms.isFinite || ms < 946684800000 || ms > 4102444800000) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(ms.round());
    }
    return DateTime.tryParse(text);
  }

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static List<String> _splitLine(String line) {
    final List<String> out = <String>[];
    final StringBuffer current = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final String ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        out.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    out.add(current.toString());
    return out;
  }
}

class CsvImportResult {
  final List<WeightRecord> records;

  /// Member names found in the file that do not exist yet.
  final List<String> newMembers;

  /// Display names declared for device ids in the file.
  final Map<String, String> deviceNames;

  const CsvImportResult(
    this.records,
    this.newMembers, [
    this.deviceNames = const <String, String>{},
  ]);
}
