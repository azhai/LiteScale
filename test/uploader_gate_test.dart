import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:litescale/model/weight_record.dart';
import 'package:litescale/service/app_controller.dart';
import 'package:litescale/service/uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts requests and fails the test if the uploader touches the network
/// before the user has switched upload on.
class _CountingClient extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    throw StateError('unexpected request: ${request.url}');
  }
}

void main() {
  test('no outbound traffic while upload is disabled', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController app = AppController();
    await app.init();
    await app.importRecords(<WeightRecord>[
      WeightRecord(time: DateTime(2026, 10, 29, 8), kg: 70.8),
    ]);

    final _CountingClient client = _CountingClient();
    final Uploader uploader = Uploader(app, client: client);
    addTearDown(uploader.dispose);

    await uploader.init();
    expect(uploader.baseUrl, kDefaultServerUrl);
    await uploader.configure(url: '  ');
    expect(uploader.baseUrl, kDefaultServerUrl);
    await uploader.configure(url: 'https://example.invalid');
    await uploader.configure(url: 'https://example.invalid', enrollKey: 'k');
    await uploader.setEnabled(false);
    await uploader.syncNow();
    await app.setDarkMode(true);

    // Covers the debounce window as well.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(uploader.enabled, isFalse);
    expect(client.calls, 0);
  });

  test('enabled without configuration targets the built-in server', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController app = AppController();
    await app.init();
    final _CountingClient client = _CountingClient();
    final Uploader uploader = Uploader(app, client: client);
    addTearDown(uploader.dispose);

    await uploader.init();
    expect(uploader.baseUrl, kDefaultServerUrl);
    await uploader.setEnabled(true);
    expect(client.calls, greaterThan(0));
    expect(uploader.error, isNotEmpty);
  });
}
