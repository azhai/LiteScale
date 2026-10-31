@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/model/entities.dart';
import 'package:litescale/model/weight_record.dart';
import 'package:litescale/service/app_controller.dart';
import 'package:litescale/service/csv.dart';
import 'package:litescale/service/uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Full CSV loop against the real Odin server binary:
/// app export -> server import -> server export -> app import.
/// Skipped when the binary has not been built (`make -C server build`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HTTP override that answers 400 for every request.
  HttpOverrides.global = null;

  test('app export -> server import -> server export -> app import', () async {
    final File bin = File('server/bin/litescale-server');
    if (!bin.existsSync()) {
      // ignore: avoid_print
      print('server binary missing — build it with `make -C server build`');
      return;
    }
    final Directory data =
        await Directory.systemTemp.createTemp('litescale-csv-roundtrip-');
    final int port = 19900 + DateTime.now().millisecond % 100;
    final String base = 'http://127.0.0.1:$port';
    final Process server = await Process.start(bin.absolute.path, <String>[
      '-addr',
      '127.0.0.1:$port',
      '-data',
      data.path,
      '-admin-token',
      'roundtrip-admin',
      '-no-raw-log',
    ]);
    final StringBuffer log = StringBuffer();
    server.stdout.listen((List<int> b) => log.write(utf8.decode(b)));
    server.stderr.listen((List<int> b) => log.write(utf8.decode(b)));

    final AppController app = AppController();
    final Uploader uploader = Uploader(app);
    addTearDown(() async {
      uploader.dispose();
      server.kill();
      await server.exitCode;
      await data.delete(recursive: true);
    });

    await _waitReady(base, log);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    await app.init();
    final Member a = await app.addMember('阿债');
    final Member b = await app.addMember('小美');
    await app.rememberDevice('C0:FF:EE:12:34:56', 'OKOK S3');
    await app.setHeightCm(172, memberId: a.id);
    await app.setMemberGoal(
      const MemberGoal(date: '2026-10-29', targetKg: 68.5),
      memberId: a.id,
    );

    // Register the client and sync members/devices before any record exists,
    // so the export's client_id is already known to the server.
    await uploader.init();
    await uploader.configure(url: '$base/');
    await uploader.setEnabled(true);
    expect(uploader.error, isEmpty, reason: uploader.error);
    expect(uploader.clientId, isNotEmpty);
    expect(uploader.lastSyncMs, greaterThan(0));
    await uploader.setEnabled(false);

    final DateTime t1 = DateTime.fromMillisecondsSinceEpoch(1793000000123);
    final DateTime t2 = DateTime.fromMillisecondsSinceEpoch(1793000060456);
    final DateTime t3 = DateTime.fromMillisecondsSinceEpoch(1793000120789);
    await app.importRecords(<WeightRecord>[
      WeightRecord(
        time: t1,
        kg: 70.812,
        memberId: a.id,
        deviceId: 'C0:FF:EE:12:34:56',
      ),
      WeightRecord(time: t2, kg: 71.5, memberId: b.id),
      WeightRecord(time: t3, kg: 68.004, memberId: a.id),
    ]);
    expect(app.records.length, 3);

    final String csv =
        CsvService.export(app.records, app, clientId: uploader.clientId);
    expect(
      csv.split('\n').first,
      'ts,client_id,device_id,device_name,member_id,member_name,kg',
    );
    expect(csv, contains('1793000000.123,${uploader.clientId},'));
    expect(csv, contains('1793000060.456,${uploader.clientId},'));

    // The default client is optional: the row's client_id is enough.
    final Map<String, dynamic> imported =
        await _adminPostCsv('$base/api/v1/admin/measurements/import', csv);
    expect(imported['total'], 3);
    expect(imported['imported'], 3);
    expect(imported['duplicates'], 0);
    expect(imported['members_created'], 0);
    expect(imported['rejected'], isEmpty);

    final Map<String, dynamic> again =
        await _adminPostCsv('$base/api/v1/admin/measurements/import', csv);
    expect(again['imported'], 0);
    expect(again['duplicates'], 3);

    final String serverCsv =
        await _adminGetCsv('$base/api/v1/admin/measurements.csv');
    expect(
      serverCsv.replaceFirst('\uFEFF', '').split('\n').first,
      'ts,client_id,device_id,device_name,member_id,member_name,kg',
    );
    expect(serverCsv, contains('1793000000.123,${uploader.clientId},'));
    expect(serverCsv, contains('1793000060.456,${uploader.clientId},'));
    expect(serverCsv, contains('1793000120.789,${uploader.clientId},'));

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController fresh = AppController();
    await fresh.init();
    final CsvImportResult parsed = CsvService.parse(serverCsv, fresh);
    expect(parsed.records.length, 3);
    expect(parsed.deviceNames['C0:FF:EE:12:34:56'], 'OKOK S3');
    expect(await fresh.importRecords(parsed.records, deviceNames: parsed.deviceNames), 3);
    expect(fresh.records.length, 3);

    final Map<String, WeightRecord> byTime = <String, WeightRecord>{
      for (final WeightRecord r in fresh.records)
        '${r.time.millisecondsSinceEpoch}': r,
    };
    String memberName(WeightRecord r) => fresh.memberOf(r).name;
    expect(byTime['1793000000123']!.kg, closeTo(70.812, 0.0005));
    expect(memberName(byTime['1793000000123']!), '阿债');
    expect(byTime['1793000000123']!.deviceId, 'C0:FF:EE:12:34:56');
    expect(fresh.deviceNameOf(byTime['1793000000123']!), 'OKOK S3');
    expect(byTime['1793000060456']!.kg, closeTo(71.5, 0.0005));
    expect(memberName(byTime['1793000060456']!), '小美');
    expect(byTime['1793000060456']!.deviceId, isNull);
    expect(byTime['1793000120789']!.kg, closeTo(68.004, 0.0005));
    expect(memberName(byTime['1793000120789']!), '阿债');
  });
}

Future<void> _waitReady(String base, StringBuffer log) async {
  final HttpClient probe = HttpClient();
  bool ready = false;
  for (int i = 0; i < 100 && !ready; i++) {
    try {
      final HttpClientRequest req = await probe.getUrl(Uri.parse('$base/api/v1/ping'));
      final HttpClientResponse res = await req.close();
      await res.drain<void>();
      ready = res.statusCode == 200;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  probe.close();
  expect(ready, isTrue, reason: 'server did not start:\n$log');
}

Future<Map<String, dynamic>> _adminPostCsv(String url, String body) async {
  final HttpClient client = HttpClient();
  final HttpClientRequest req = await client.postUrl(Uri.parse(url));
  req.headers.set('Authorization', 'Bearer roundtrip-admin');
  req.headers.contentType = ContentType('text', 'csv', charset: 'utf-8');
  final List<int> bytes = utf8.encode(body);
  req.contentLength = bytes.length;
  req.add(bytes);
  final HttpClientResponse res = await req.close();
  final String text = await res.transform(utf8.decoder).join();
  client.close();
  expect(res.statusCode, 200, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<String> _adminGetCsv(String url) async {
  final HttpClient client = HttpClient();
  final HttpClientRequest req = await client.getUrl(Uri.parse(url));
  req.headers.set('Authorization', 'Bearer roundtrip-admin');
  final HttpClientResponse res = await req.close();
  final String body = await res.transform(utf8.decoder).join();
  client.close();
  expect(res.statusCode, 200, reason: body);
  return body;
}
