@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/model/entities.dart';
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
    final Member created = await app.addMember('阿债');
    await app.setActiveMember(created.id);
    await app.rememberDevice('C0:FF:EE:12:34:56', 'OKOK S3');
    await app.setHeightCm(172, memberId: app.activeMemberId);
    await app.setMemberDetails(
      app.activeMemberId,
      gender: 'female',
      birth: '1990-05',
    );
    await app.setMemberGoal(
      const MemberGoal(date: '2026-10-29', targetKg: 68.5),
      memberId: app.activeMemberId,
    );
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
    final Map<String, dynamic> member = members
        .cast<Map<String, dynamic>>()
        .firstWhere((Map<String, dynamic> m) => m['name'] == '阿债');
    expect(member['avatar'], app.activeMember.avatar);
    expect((member['height_cm'] as num).toDouble(), closeTo(172, 0.001));
    expect(member['gender'], 'female');
    expect(member['birth'], '1990-05');
    expect(member['goals'], 1);
    final List<dynamic> devices = detail['devices'] as List<dynamic>;
    expect(devices, hasLength(1));
    expect((devices.single as Map<String, dynamic>)['name'], 'OKOK S3');

    final List<dynamic> goals = detail['goals'] as List<dynamic>;
    expect(goals, hasLength(1));
    final Map<String, dynamic> goal = goals.single as Map<String, dynamic>;
    expect(goal['member_id'], member['id']);
    expect(goal['date'], '2026-10-29');
    expect((goal['target_kg'] as num).toDouble(), closeTo(68.5, 0.001));
    // Actual weight is the last measurement on that local date.
    expect((goal['actual_kg'] as num).toDouble(), closeTo(70.8, 0.001));
    expect((detail['goal'] as Map<String, dynamic>)['set'], isFalse);

    // A second sync must not duplicate anything.
    await uploader.syncNow();
    final Map<String, dynamic> after = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/overview',
    );
    expect(after['measurements'], 2);
    expect(after['batches'], before['batches']);

    // Avatar / gender / birth edits trigger one metadata-only batch.
    final String memberId = member['id'] as String;
    await app.setMemberAvatar(memberId, avatar: 'a24');
    await app.setMemberDetails(memberId, gender: 'male', birth: '1988-02');
    await uploader.syncNow();
    expect(uploader.error, isEmpty, reason: uploader.error);

    final Map<String, dynamic> changed = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/clients/${uploader.clientId}',
    );
    final Map<String, dynamic> changedMember =
        (changed['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((Map<String, dynamic> m) => m['id'] == memberId);
    expect(changedMember['avatar'], 'a24');
    expect(changedMember['gender'], 'male');
    expect(changedMember['birth'], '1988-02');
    expect((changedMember['height_cm'] as num).toDouble(), closeTo(172, 0.001));
    final Map<String, dynamic> finalOverview = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/overview',
    );
    expect(finalOverview['batches'], (after['batches'] as int) + 1);
    expect(finalOverview['measurements'], 2);

    // Manual "sync now" is forced: it resends metadata even when nothing
    // changed, so an upgraded server picks up fields it never stored.
    await uploader.syncNow();
    final Map<String, dynamic> quiet = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/overview',
    );
    expect(quiet['batches'], finalOverview['batches']);

    // Simulate a server that recorded the batch but dropped the profile.
    await _adminPost(
      'http://127.0.0.1:$port/api/v1/admin/clients/${uploader.clientId}/members/$memberId',
      <String, dynamic>{
        'name': '阿债',
        'avatar': 'a24',
        'color': 0,
        'height_cm': 0,
        'gender': '',
        'birth': '',
      },
    );
    final Map<String, dynamic> cleared = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/clients/${uploader.clientId}',
    );
    final Map<String, dynamic> clearedMember =
        (cleared['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((Map<String, dynamic> m) => m['id'] == memberId);
    expect(clearedMember['gender'], '');
    expect(clearedMember['birth'], '');

    await uploader.syncNow(force: true);
    expect(uploader.error, isEmpty, reason: uploader.error);
    final Map<String, dynamic> forced = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/overview',
    );
    expect(forced['batches'], (quiet['batches'] as int) + 1);
    expect(forced['measurements'], 2);
    final Map<String, dynamic> restored = await _adminJson(
      'http://127.0.0.1:$port/api/v1/admin/clients/${uploader.clientId}',
    );
    final Map<String, dynamic> restoredMember =
        (restored['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((Map<String, dynamic> m) => m['id'] == memberId);
    expect(restoredMember['avatar'], 'a24');
    expect(restoredMember['gender'], 'male');
    expect(restoredMember['birth'], '1988-02');
    expect((restoredMember['height_cm'] as num).toDouble(), closeTo(172, 0.001));
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

Future<void> _adminPost(String url, Map<String, dynamic> payload) async {
  final HttpClient client = HttpClient();
  final HttpClientRequest req = await client.postUrl(Uri.parse(url));
  req.headers.set('Authorization', 'Bearer test-admin-token');
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(payload));
  final HttpClientResponse res = await req.close();
  final String body = await res.transform(utf8.decoder).join();
  client.close();
  expect(res.statusCode, 200, reason: body);
}
