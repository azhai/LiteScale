import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/model/weight_record.dart';
import 'package:litescale/service/app_controller.dart';
import 'package:litescale/service/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('export uses the canonical ts/kg schema', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController app = AppController();
    await app.init();

    final DateTime time = DateTime.fromMillisecondsSinceEpoch(1793000000123);
    final List<WeightRecord> rows = <WeightRecord>[
      WeightRecord(time: time, kg: 70.8, deviceId: 'd1'),
    ];
    final String csv =
        CsvService.export(rows, app, clientId: 'c-ios-test');

    expect(
      csv.split('\n').first,
      'ts,client_id,device_id,device_name,member_id,member_name,kg',
    );
    expect(CsvService.formatTs(time), '1793000000.123');
    expect(csv, contains('1793000000.123,c-ios-test,d1'));
    expect(csv, isNot(contains('1793000000123')));

    final String anonymous = CsvService.export(rows, app);
    expect(anonymous, contains('1793000000.123,,d1'));

    final CsvImportResult parsed = CsvService.parse(csv, app);
    expect(parsed.records.single.time, time);
    expect(parsed.records.single.kg, 70.8);
    expect(parsed.records.single.deviceId, 'd1');
  });

  test('import maps columns by header name (server export order)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController app = AppController();
    await app.init();
    final String memberId = app.members.first.id;
    final String memberName = app.members.first.name;

    final String source =
        'ts,client_id,device_id,device_name,member_id,member_name,kg\n'
        '1793000000.456,c1,d9,Scale,$memberId,$memberName,70.800\n';
    final CsvImportResult parsed = CsvService.parse(source, app);

    expect(parsed.records.length, 1);
    expect(
      parsed.records.single.time,
      DateTime.fromMillisecondsSinceEpoch(1793000000456),
    );
    expect(parsed.records.single.memberId, memberId);
    expect(parsed.records.single.deviceId, 'd9');
    expect(parsed.records.single.kg, 70.8);
    expect(parsed.newMembers, isEmpty);
  });

  test('import keeps older headers, millisecond ts and ISO as compat', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController app = AppController();
    await app.init();

    const String source =
        'timestamp,device_id,device_name,member_id,member_name,weight_kg\n'
        '1793000000,d1,Scale,,Me,70.800\n'
        '2026-10-29T08:00:00.000,d1,Scale,,Me,71.500\n';
    final CsvImportResult parsed = CsvService.parse(source, app);

    expect(parsed.records.length, 2);
    expect(
      parsed.records.first.time,
      DateTime.fromMillisecondsSinceEpoch(1793000000000),
    );
    expect(parsed.records.last.time, DateTime(2026, 10, 29, 8));

    final CsvImportResult ms = CsvService.parse(
      'ts_ms,kg\n1793000000123,72.000\n',
      app,
    );
    expect(ms.records.length, 1);
    expect(
      ms.records.single.time,
      DateTime.fromMillisecondsSinceEpoch(1793000000123),
    );
  });

  test('headerless files keep the positional layout', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController app = AppController();
    await app.init();

    const String source = '1793000000,d1,Scale,m1,新人,70.800\n';
    final CsvImportResult parsed = CsvService.parse(source, app);

    expect(parsed.records.single.deviceId, 'd1');
    expect(parsed.records.single.time.millisecondsSinceEpoch, 1793000000000);
    expect(parsed.records.single.memberId, 'pending:新人');
    expect(parsed.newMembers, <String>['新人']);
  });
}
