import '../model/entities.dart';
import '../model/weight_record.dart';
import 'app_controller.dart';

/// CSV import / export for measurements.
///
/// Columns: timestamp, device_id, device_name, member_id, member_name, weight_kg
/// Timestamps are ISO-8601 (local time). Extra columns are ignored on import so
/// exported files from other tools still work, and rows without a valid
/// timestamp / weight are skipped.
class CsvService {
  static const String header =
      'timestamp,device_id,device_name,member_id,member_name,weight_kg';

  static String export(List<WeightRecord> records, AppController c) {
    final StringBuffer out = StringBuffer()
      ..writeln(header);
    for (final WeightRecord r in records) {
      out.writeln(<String>[
        r.time.toIso8601String(),
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
  /// Members that do not exist yet are returned in [CsvImportResult.newMembers].
  static CsvImportResult parse(String source, AppController c) {
    final List<WeightRecord> records = <WeightRecord>[];
    final List<String> newMembers = <String>[];

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
      return CsvImportResult(records, newMembers);
    }

    // Skip the header row when present.
    int start = 0;
    final List<String> first = _splitLine(lines.first);
    if (first.isNotEmpty &&
        first.first.toLowerCase().replaceAll('\ufeff', '').contains('time')) {
      start = 1;
    }

    for (int i = start; i < lines.length; i++) {
      final List<String> cells = _splitLine(lines[i]);
      if (cells.length < 2) continue;

      final DateTime? time = DateTime.tryParse(cells[0].trim());
      final double? kg = double.tryParse(cells[cells.length - 1].trim());
      if (time == null || kg == null || kg <= 0) continue;

      final String deviceId = cells.length > 1 ? cells[1].trim() : '';
      final String memberKey =
          cells.length > 4 ? cells[4].trim() : (cells.length > 3 ? cells[3].trim() : '');

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

    return CsvImportResult(records, newMembers);
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

  const CsvImportResult(this.records, this.newMembers);
}
