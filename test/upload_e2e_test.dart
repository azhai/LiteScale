@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/model/weight_record.dart';
import 'package:litescale/service/app_controller.dart';
import 'package:litescale/service/uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end: a real [Uploader] talks to the real Odin server binary.
/// Skipped when the binary has not been built (`make -C server build`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HTTP override that answers 400 for every request;
  // this suite talks to a real local server.
  HttpOverrides.global = null;

  test('uploads members, devices, goal and records to a live server', () async {
    final File bin = File('server/bin/litescale-server');
    if (!bin.existsSync()) {
      // ignore: avoid_print
      print('server binary missing — build it with `make -C server build`');
      return;
    }
    final Directory data =
        await Directory.systemTemp.createTemp('litescale-upload-test-');
    final int port = 19500 + DateTime.now().millisecond % 400;
    final Process server = await Process.start(bin.absolute.path, <String>[
      '-addr',
      '127.0.0.1:$port',
      '-data',
      data.path,
      '-admin-token',
      'test-admin-token',
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

    final HttpClient probe = HttpClient();
    bool ready = false;
    for (int i = 0; i < 100 && !ready; i++) {
      try {
        final HttpClientRequest req =
            await probe.getUrl(Uri.parse('http://127.0.0.1:$port/api/v1/ping'));
        final HttpClientResponse res = await req.close();
        await res.drain<void>();
        ready = res.statusCode == 200;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    probe.close();
    expect(ready, isTrue, reason: 'server did not start:\n$log');

    SharedPreferences.setMockInitialValues(<String, Object>{});
    await app.init();
    await app.addMember('阿债');
    await app.rememberDevice('C0:FF:EE:12:34:56', 'OKOK S3');
    await app.setGoalKg(68.5);
    await app.importRecords(<WeightRecord>[
      WeightRecord(
        time: DateTime(2026, 10, 28, 8, 30),
        kg: 71.2,
        memberId: app.activeMemberId,
        deviceId: 'C0:FF:EE:12:34:56',
      ),
      WeightRecord(
        time: DateTime(2026, 10, 29, 8, 35),
        kg: 70.8,
        memberId: app.activeMemberId,
      ),
    ]);
    expect(app.records.length, 2);

    await uploader.init();
    await uploader.configure(url: 'http://127.0.0.1:$port/');
    await uploader.setEnabled(true);
    expect(uploader.error, isEmpty, reason: uploader.error);
    expect(uploader.lastSyncMs, greaterThan(0));
    expect(uploader.cursor, app.records.last.time.millisecondsSinceEpoch);

    final Map<String, dynamic> before = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/overview',
    );
    expect(before['measurements'], 2);

    final Map<String, dynamic> detail = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/clients/${uploader.clientId}',
    );
    final List<dynamic> members = detail['members'] as List<dynamic>;
    expect(members.map((dynamic m) => (m as Map<String, dynamic>)['name']),
        contains('阿债'));
    final List<dynamic> devices = detail['devices'] as List<dynamic>;
    expect(devices, hasLength(1));
    expect((devices.single as Map<String, dynamic>)['name'], 'OKOK S3');
    final Map<String, dynamic> goal = detail['goal'] as Map<String, dynamic>;
    expect(goal['set'], isTrue);
    expect((goal['kg'] as num).toDouble(), closeTo(68.5, 0.001));

    // A second sync must not duplicate anything.
    await uploader.syncNow();
    final Map<String, dynamic> after = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/overview',
    );
    expect(after['measurements'], 2);
    expect(after['batches'], before['batches']);
  });
}

Future<Map<String, dynamic>> _adminJson(String url) async {
  final HttpClient client = HttpClient();
  final HttpClientRequest req = await client.getUrl(Uri.parse(url));
  req.headers.set('Authorization', 'Bearer test-admin-token');
  final HttpClientResponse res = await req.close();
  final String body = await res.transform(utf8.decoder).join();
  client.close();
  expect(res.statusCode, 200, reason: body);
  return jsonDecode(body) as Map<String, dynamic>;
}
