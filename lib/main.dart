import 'package:flutter/material.dart';

import 'service/app_controller.dart';
import 'service/uploader.dart';
import 'view/devices_page.dart';
import 'view/history_page.dart';
import 'view/home.dart';
import 'view/settings_page.dart';
import 'view/theme.dart';

final AppController app = AppController();
final Uploader uploader = Uploader(app);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  await uploader.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    app.addListener(_onAppChanged);
  }

  @override
  void dispose() {
    app.removeListener(_onAppChanged);
    super.dispose();
  }

  void _onAppChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: app.s.appTitle,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: app.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<Widget> pages = <Widget>[
      ScaleConnectPage(controller: app),
      HistoryPage(controller: app),
      DevicesPage(controller: app),
      SettingsPage(controller: app, uploader: uploader),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              width: 0.8,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (int i) => setState(() => _index = i),
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: const Icon(Icons.speed_outlined),
              selectedIcon: const Icon(Icons.speed_rounded),
              label: app.s.tabMeasure,
            ),
            NavigationDestination(
              icon: const Icon(Icons.insights_outlined),
              selectedIcon: const Icon(Icons.insights_rounded),
              label: app.s.tabHistory,
            ),
            NavigationDestination(
              icon: const Icon(Icons.bluetooth_outlined),
              selectedIcon: const Icon(Icons.bluetooth_rounded),
              label: app.s.tabDevices,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: app.s.tabSettings,
            ),
          ],
        ),
      ),
    );
  }
}
