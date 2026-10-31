import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/model/entities.dart';
import 'package:litescale/service/app_controller.dart';
import 'package:litescale/service/uploader.dart';
import 'package:litescale/view/settings_page.dart';
import 'package:litescale/view/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('legacy emoji avatars normalize to stable bundled ids', () {
    expect(normalizeAvatarId('a01'), 'a01');
    final String me = normalizeAvatarId('🙂', seed: 'me');
    expect(kAvatarIds, contains(me));
    expect(normalizeAvatarId('🙂', seed: 'me'), me);
    expect(normalizeAvatarId('🙂', seed: 'other'), isNot(me));
  });

  test('member json migrates an emoji avatar', () {
    final Member m = Member.fromJson(<String, dynamic>{
      'id': 'me',
      'name': 'Me',
      'avatar': '🦊',
    });
    expect(kAvatarIds, contains(m.avatar));
    expect(avatarAssetPath('🦊', seed: 'me'), 'assets/avatars/${m.avatar}.png');
  });

  testWidgets('settings renders bundled avatar images', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'members': jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'me', 'name': 'Me', 'avatar': '🐷', 'color': 0},
      ]),
    });
    final AppController app = AppController();
    await app.init();
    final Uploader uploader = Uploader(app);
    addTearDown(uploader.dispose);
    await uploader.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(controller: app, uploader: uploader),
      ),
    );
    await tester.pumpAndSettle();

    final List<String> avatars = tester
        .widgetList<Image>(find.byType(Image))
        .map((Image i) => (i.image as AssetImage).assetName)
        .where((String p) => p.startsWith('assets/avatars/'))
        .toList();
    expect(avatars, isNotEmpty);
    expect(avatars.every((String p) => kAvatarIds.contains(p.split('/').last.split('.').first)), isTrue);
    expect(tester.takeException(), isNull);
  });
}
