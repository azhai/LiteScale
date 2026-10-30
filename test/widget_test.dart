import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/model/entities.dart';
import 'package:litescale/service/app_controller.dart';
import 'package:litescale/service/units.dart';
import 'package:litescale/source/scale_source.dart';
import 'package:litescale/source/source_registry.dart';
import 'package:litescale/view/history_page.dart';
import 'package:litescale/view/home.dart';
import 'package:litescale/view/theme.dart';
import 'package:litescale/view/widgets/app_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Source used instead of the real BLE scanner so the measure page can be
/// pumped in a test environment.
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
      ];

  @override
  Stream<ScaleSample> get samples => const Stream<ScaleSample>.empty();

  @override
  List<String> get logs => <String>['adv ok'];

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

void main() {
  test('light theme uses the lake-green palette and MD3', () {
    final ThemeData theme = buildAppTheme(Brightness.light);
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, Brand.deep);
    expect(theme.colorScheme.surface, const Color(0xFFF6FAF8));
    expect(theme.navigationBarTheme.indicatorColor,
        theme.colorScheme.primaryContainer);
  });

  test('dark theme keeps the lake-green hue and a readable surface', () {
    final ThemeData theme = buildAppTheme(Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFF7BD9C3));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0B1512));
  });

  test('jin is the default unit and leads the unit list', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController();
    await c.init();
    expect(Units.all.first, 'jin');
    expect(Units.all.indexOf('jin'), lessThan(Units.all.indexOf('kg')));
    expect(c.unit, 'jin');
  });

  testWidgets('hero card pieces render without layout overflow',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              AppCard(
                child: Column(
                  children: <Widget>[
                    const StatusPill(label: 'Measuring'),
                    WeightRing(
                      progress: 0.62,
                      child: const Text('72.4'),
                    ),
                    const Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(label: 'BMI', value: '23.1'),
                        ),
                        Expanded(
                          child: StatTile(label: 'To Goal', value: '1.2'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionHeader(title: 'Section'),
              const EmptyState(
                icon: Icons.show_chart_rounded,
                text: 'Nothing here',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('72.4'), findsOneWidget);
    expect(find.text('Nothing here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('measure page shows the last stored reading before a live one',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'lang': 'zh'});
    final AppController c = AppController();
    await c.init();
    await c.addRecord(72.4);

    sourceFactoryOverride = () => <ScaleSource>[_FakeSource()];
    addTearDown(() => sourceFactoryOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ScaleConnectPage(controller: c),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('144.8'), findsOneWidget);
    expect(find.text('斤'), findsOneWidget);
    expect(find.text('OKOK S3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history defaults to the active member filter',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'lang': 'zh'});
    final AppController c = AppController();
    await c.init();
    final Member other = await c.addMember('Alex');
    await c.addRecord(70.0);
    await c.setActiveMember(other.id);
    await c.addRecord(55.0);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: HistoryPage(controller: c),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Only the active member's record is listed (stats + record row).
    expect(find.text('110.0 斤'), findsWidgets);
    expect(find.text('140.0 斤'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

