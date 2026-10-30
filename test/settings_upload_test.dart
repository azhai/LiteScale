import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/service/app_controller.dart';
import 'package:litescale/service/uploader.dart';
import 'package:litescale/view/settings_page.dart';
import 'package:litescale/view/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('upload card stays compact on a phone width', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController app = AppController();
    await app.init();
    final Uploader uploader = Uploader(app);
    addTearDown(uploader.dispose);
    await uploader.init();
    expect(uploader.baseUrl, kDefaultServerUrl);

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(controller: app, uploader: uploader),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Enable upload'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Enable upload'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text(kDefaultServerUrl), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
