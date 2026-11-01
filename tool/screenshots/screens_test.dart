// Regenerates the README screenshots from the real widget tree.
//
//   ./scripts/screenshots.sh          # wrapper (handles fonts + --update-goldens)
//
// Not part of `flutter test`: it lives outside test/ so a normal run never
// rewrites checked-in images.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/main.dart';
import 'package:litescale/model/entities.dart';
import 'package:litescale/model/weight_record.dart';
import 'package:litescale/source/scale_source.dart';
import 'package:litescale/source/source_registry.dart';
import 'package:litescale/view/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the BLE scanner: the real one asks for runtime permissions,
/// which has no implementation under flutter_test.
class _FakeSource extends ScaleSource {
  @override
  String get kind => 'ble';
  @override
  SourceState get state => SourceState.running;
  @override
  String get statusCode => 'scanning';
  @override
  String get statusDetail => '';
  @override
  bool get isRunning => true;
  @override
  List<SourceDevice> get devices => <SourceDevice>[
        SourceDevice(
          id: 'C0:FF:EE:12:34:56',
          name: 'OKOK S3',
          rssi: -52,
          decoded: true,
          seenAt: DateTime.now(),
        ),
        SourceDevice(
          id: 'C0:FF:EE:98:76:54',
          name: 'Chipsea-BLE',
          rssi: -74,
          decoded: true,
          seenAt: DateTime.now(),
        ),
        SourceDevice(
          id: '5C:11:22:33:44:55',
          name: '',
          rssi: -88,
          decoded: false,
          seenAt: DateTime.now(),
        ),
      ];
  @override
  Stream<ScaleSample> get samples => const Stream<ScaleSample>.empty();
  @override
  List<String> get logs => <String>['adv ok', 'rssi -52'];
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

/// Flutter's test runner ships no real fonts: without these every glyph and
/// icon renders as a filled box.
Future<void> _loadFont(String family, List<String> paths) async {
  final FontLoader loader = FontLoader(family);
  bool any = false;
  for (final String path in paths) {
    final File file = File(path);
    if (!file.existsSync()) continue;
    final Uint8List bytes = file.readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    any = true;
  }
  if (!any) {
    // ignore: avoid_print
    print('WARN: no font file found for "$family" — glyphs will render as boxes');
    return;
  }
  await loader.load();
}

String _flutterRoot() {
  final String? fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final ProcessResult which = Process.runSync('which', <String>['flutter']);
  final String bin = (which.stdout as String).trim();
  return Directory(bin).parent.path;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Realistic household data: two members, a downward trend for the active one,
/// two known scales and a dated goal.
Future<void> _seed() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'lang': 'zh',
    'unit': 'kg',
    'darkMode': false,
  });
  await app.init();
  await uploader.init();

  final DateTime now = DateTime.now();
  final String me = app.activeMemberId;

  await app.renameMember(me, '我');
  await app.setMemberAvatar(me, avatar: 'a12', colorIndex: 0);
  await app.setHeightCm(168, memberId: me);
  await app.setMemberDetails(me, gender: 'female', birth: '1994-06');
  await app.setMemberGoal(
    MemberGoal(date: _ymd(now.add(const Duration(days: 45))), targetKg: 62.0),
    memberId: me,
  );

  final Member lin = await app.addMember('小林');
  await app.setMemberAvatar(lin.id, avatar: 'a27', colorIndex: 2);
  await app.setHeightCm(176, memberId: lin.id);
  await app.setMemberDetails(lin.id, gender: 'male', birth: '1991-11');

  await app.rememberDevice('C0:FF:EE:12:34:56', 'OKOK S3');
  await app.rememberDevice('C0:FF:EE:98:76:54', 'Chipsea-BLE');

  // 12 weeks of readings, every other day, 73.8 → 66.9 kg for me, with a
  // little noise so the chart is not a straight line.
  final List<WeightRecord> rows = <WeightRecord>[];
  const List<double> wobble = <double>[0, .2, -.1, .3, -.2, .1, 0, -.3, .2, .1, -.1, .2];
  for (int i = 0; i < 42; i++) {
    final DateTime day = now.subtract(Duration(days: (41 - i) * 2, hours: 7, minutes: 12));
    final double trend = 73.8 - (6.9 * i / 41);
    rows.add(WeightRecord(
      time: day,
      kg: double.parse((trend + wobble[i % wobble.length]).toStringAsFixed(1)),
      memberId: me,
      deviceId: 'C0:FF:EE:12:34:56',
    ));
  }
  for (int i = 0; i < 10; i++) {
    final DateTime day = now.subtract(Duration(days: (9 - i) * 7, hours: 21, minutes: 40));
    rows.add(WeightRecord(
      time: day,
      kg: double.parse((81.2 - i * 0.3).toStringAsFixed(1)),
      memberId: lin.id,
      deviceId: 'C0:FF:EE:98:76:54',
    ));
  }
  await app.importRecords(rows, deviceNames: const <String, String>{
    'C0:FF:EE:12:34:56': 'OKOK S3',
    'C0:FF:EE:98:76:54': 'Chipsea-BLE',
  });
  await app.setActiveMember(me);
}

void main() {
  setUpAll(() async {
    final String root = _flutterRoot();
    await _loadFont('Roboto', <String>[
      '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ]);
    await _loadFont('MaterialIcons', <String>[
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    // CJK + emoji fallbacks; Arial Unicode covers the Chinese labels.
    await _loadFont('ArialUnicode', <String>[
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    ]);
  });

  testWidgets('capture every tab', (WidgetTester tester) async {
    sourceFactoryOverride = () => <ScaleSource>[_FakeSource()];
    addTearDown(() => sourceFactoryOverride = null);
    await _seed();

    tester.view.physicalSize = const Size(780, 1688); // iPhone 13 @2x
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // A RepaintBoundary lets us rasterise the whole shell at 2x below, which
    // matchesGoldenFile cannot do (it always captures at pixel ratio 1).
    final GlobalKey boundaryKey = GlobalKey();

    await tester.pumpWidget(RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
          Brightness.light,
          fontFamily: 'Roboto',
          fontFamilyFallback: <String>['ArialUnicode'],
        ),
        home: const MainShell(),
      ),
    ));
    // The measure page animates its scanning pulse forever, so pumpAndSettle
    // would never return; fixed-length pumps give a deterministic frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Decode every avatar up front: Image.asset resolves asynchronously and a
    // golden taken before decode finishes would show empty circles.
    await tester.runAsync(() async {
      final BuildContext ctx = tester.element(find.byType(MainShell));
      for (final String id in kAvatarIds.take(8)) {
        await precacheImage(AssetImage('assets/avatars/$id.png'), ctx);
      }
    });
    await tester.pump(const Duration(milliseconds: 300));

    final Directory outDir = Directory('docs/screenshots')..createSync(recursive: true);

    Future<void> shot(String name) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      final RenderRepaintBoundary boundary =
          boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // Rasterising needs real async; without runAsync the engine never
      // completes the future and the test hangs.
      final ui.Image image =
          (await tester.runAsync(() => boundary.toImage(pixelRatio: 2.0)))!;
      final ByteData? png = await tester.runAsync<ByteData?>(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      image.dispose();
      File('${outDir.path}/ui-$name.png')
          .writeAsBytesSync(png!.buffer.asUint8List(), flush: true);
      // ignore: avoid_print
      print('wrote ${outDir.path}/ui-$name.png');
    }

    await shot('measure');

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await shot('history');

    await tester.tap(find.byIcon(Icons.bluetooth_outlined));
    await shot('devices');

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await shot('settings');
  });
}
