import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../model/entities.dart';
import '../model/weight_record.dart';
import 'app_controller.dart';

/// Keep in sync with the `version:` field in pubspec.yaml.
const String kClientAppVersion = '1.0.5';
const int kSchemaVersion = 1;
const int kMaxRecordsPerBatch = 300;

/// Uploads members, devices, goal and measurements to a self-hosted
/// LiteScale server. Records are sent as a cursor-ordered stream; every batch
/// carries the same `X-Body-Sha256` header and a body-derived idempotency key,
/// so retries are safe on both sides.
class Uploader extends ChangeNotifier {
  Uploader(this.app, {http.Client? client}) : _client = client ?? http.Client();

  final AppController app;
  final http.Client _client;

  static const String _kEnabled = 'uploadEnabled';
  static const String _kUrl = 'uploadUrl';
  static const String _kEnroll = 'uploadEnrollKey';
  static const String _kClientId = 'uploadClientId';
  static const String _kToken = 'uploadToken';
  static const String _kTokenUrl = 'uploadTokenUrl';
  static const String _kCursor = 'uploadCursor';
  static const String _kLastSync = 'uploadLastSync';
  static const String _kMeta = 'uploadMetaSig';
  static const String _kError = 'uploadError';

  SharedPreferences? _prefs;
  Timer? _debounce;

  bool _enabled = false;
  String _baseUrl = '';
  String _enrollKey = '';
  String _clientId = '';
  String _token = '';
  String _tokenUrl = '';
  int _cursor = 0;
  int _lastSyncMs = 0;
  String _metaSig = '';
  String _error = '';
  bool _busy = false;

  bool get enabled => _enabled;
  String get baseUrl => _baseUrl;
  String get enrollKey => _enrollKey;
  String get clientId => _clientId;
  int get lastSyncMs => _lastSyncMs;
  String get error => _error;
  bool get busy => _busy;
  bool get linked => _token.isNotEmpty;
  int get cursor => _cursor;

  bool get _zh => app.s.isZh;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final SharedPreferences p = _prefs!;
    _enabled = p.getBool(_kEnabled) ?? false;
    _baseUrl = p.getString(_kUrl) ?? '';
    _enrollKey = p.getString(_kEnroll) ?? '';
    _clientId = p.getString(_kClientId) ?? '';
    _token = p.getString(_kToken) ?? '';
    _tokenUrl = p.getString(_kTokenUrl) ?? '';
    _cursor = p.getInt(_kCursor) ?? 0;
    _lastSyncMs = p.getInt(_kLastSync) ?? 0;
    _metaSig = p.getString(_kMeta) ?? '';
    _error = p.getString(_kError) ?? '';

    app.addListener(_onAppChanged);
    if (_enabled) {
      _debounce = Timer(const Duration(seconds: 3), syncNow);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    app.removeListener(_onAppChanged);
    _debounce?.cancel();
    _client.close();
    super.dispose();
  }

  // --- settings ----------------------------------------------------------

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs?.setBool(_kEnabled, value);
    if (value) {
      await syncNow();
    }
    notifyListeners();
  }

  /// Saves the server address; a different host invalidates the old token.
  Future<void> configure({required String url, String? enrollKey}) async {
    final String normalized = _normalizeUrl(url);
    final bool hostChanged = normalized != _tokenUrl && normalized != _baseUrl;
    _baseUrl = normalized;
    if (enrollKey != null) _enrollKey = enrollKey.trim();
    await _prefs?.setString(_kUrl, _baseUrl);
    await _prefs?.setString(_kEnroll, _enrollKey);
    if (hostChanged) {
      _token = '';
      _tokenUrl = '';
      await _prefs?.remove(_kToken);
      await _prefs?.remove(_kTokenUrl);
    }
    _error = '';
    await _prefs?.remove(_kError);
    if (_enabled) await syncNow();
    notifyListeners();
  }

  /// Forgets the token so the next sync enrols this install again.
  Future<void> relink() async {
    _token = '';
    _tokenUrl = '';
    _metaSig = '';
    _error = '';
    await _prefs?.remove(_kToken);
    await _prefs?.remove(_kTokenUrl);
    await _prefs?.remove(_kError);
    notifyListeners();
    if (_enabled) await syncNow();
  }

  void _onAppChanged() {
    if (!_enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), syncNow);
  }

  // --- sync --------------------------------------------------------------

  Future<void> syncNow() async {
    if (!_enabled || _busy) return;
    if (_baseUrl.isEmpty) {
      await _setError(_t('请先填写服务器地址', 'Set a server URL first'));
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      await _ensureRegistered();
      int sent = 0;
      int rejected = 0;
      while (true) {
        final List<WeightRecord> chunk = _pendingChunk();
        if (chunk.isEmpty) break;
        final _BatchResult r = await _postBatch(chunk);
        sent += r.accepted;
        rejected += r.rejected;
        _cursor = chunk.last.time.millisecondsSinceEpoch;
        await _prefs?.setInt(_kCursor, _cursor);
        if (chunk.length < kMaxRecordsPerBatch) break;
      }

      final String sig = _metaSignature();
      if (sent == 0 && sig != _metaSig) {
        // Metadata-only batch (member rename, new goal, ...).
        final _BatchResult r = await _postBatch(<WeightRecord>[]);
        sent += r.accepted;
        rejected += r.rejected;
      }

      _lastSyncMs = DateTime.now().millisecondsSinceEpoch;
      await _prefs?.setInt(_kLastSync, _lastSyncMs);
      _metaSig = _metaSignature();
      await _prefs?.setString(_kMeta, _metaSig);
      _error = rejected > 0
          ? _t('已同步 $sent 条，$rejected 条被服务器拒绝', 'Synced $sent, $rejected rejected')
          : '';
    } on _UploadException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = _t('同步失败：$e', 'Sync failed: $e');
    } finally {
      if (_error.isNotEmpty) await _prefs?.setString(_kError, _error);
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _setError(String message) async {
    _error = message;
    await _prefs?.setString(_kError, message);
    notifyListeners();
  }

  List<WeightRecord> _pendingChunk() {
    final List<WeightRecord> out = <WeightRecord>[];
    for (final WeightRecord r in app.records) {
      if (r.time.millisecondsSinceEpoch <= _cursor) continue;
      out.add(r);
      if (out.length >= kMaxRecordsPerBatch) break;
    }
    return out;
  }

  Future<void> _ensureRegistered() async {
    if (_clientId.isEmpty) {
      _clientId = 'c-${_platform()}-${_randomHex(8)}';
      await _prefs?.setString(_kClientId, _clientId);
    }
    if (_token.isNotEmpty && _tokenUrl == _baseUrl) return;
    await _register();
  }

  Future<void> _register() async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'id': _clientId,
      'name': 'LiteScale · ${_platformLabel()}',
      'app_version': kClientAppVersion,
      'platform': _platform(),
      'lang': app.s.langCode,
    };
    final http.Response res = await _client
        .post(
          Uri.parse('$_baseUrl/api/v1/clients'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            if (_enrollKey.isNotEmpty) 'X-Enroll-Key': _enrollKey,
          },
          body: utf8.encode(jsonEncode(payload)),
        )
        .timeout(const Duration(seconds: 20));
    final Map<String, dynamic>? body = _decode(res);
    if (res.statusCode != 200 || body == null) {
      throw _UploadException(_httpMessage(res, body));
    }
    final String token = body['token'] as String? ?? '';
    if (token.isEmpty) {
      throw _UploadException(_t('服务器未返回令牌', 'Server returned no token'));
    }
    _token = token;
    _tokenUrl = _baseUrl;
    await _prefs?.setString(_kToken, _token);
    await _prefs?.setString(_kTokenUrl, _tokenUrl);
  }

  Future<_BatchResult> _postBatch(List<WeightRecord> records) async {
    final List<int> bytes = utf8.encode(_batchBody(records));
    final String sha = sha256.convert(bytes).toString();
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_token',
      'X-Idempotency-Key': 'b-$sha',
      'X-Body-Sha256': sha,
    };

    http.Response res = await _post(bytes, headers);
    if (res.statusCode == 401) {
      await _register();
      headers['Authorization'] = 'Bearer $_token';
      res = await _post(bytes, headers);
    }
    final Map<String, dynamic>? body = _decode(res);
    if (res.statusCode == 429) {
      throw _UploadException(_t('请求过于频繁，请稍后重试', 'Rate limited, retry later'));
    }
    if (res.statusCode != 200 || body == null) {
      throw _UploadException(_httpMessage(res, body));
    }
    final List<dynamic> rejected = body['rejected'] as List<dynamic>? ?? <dynamic>[];
    return _BatchResult(
      accepted: body['accepted'] as int? ?? 0,
      rejected: rejected.length,
    );
  }

  Future<http.Response> _post(List<int> bytes, Map<String, String> headers) =>
      _client
          .post(
            Uri.parse('$_baseUrl/api/v1/ingest'),
            headers: headers,
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));

  String _batchBody(List<WeightRecord> records) {
    final Map<String, dynamic> body = <String, dynamic>{
      'schema_version': kSchemaVersion,
      'client': <String, dynamic>{
        'id': _clientId,
        'name': 'LiteScale · ${_platformLabel()}',
        'app_version': kClientAppVersion,
        'platform': _platform(),
        'lang': app.s.langCode,
      },
      'devices': <Map<String, dynamic>>[
        for (final ScaleDevice d in app.devices)
          <String, dynamic>{
            'id': d.id,
            'name': d.name,
            'last_seen': d.lastSeen.millisecondsSinceEpoch,
          },
      ],
      'members': <Map<String, dynamic>>[
        for (final Member m in app.members)
          <String, dynamic>{
            'id': m.id,
            'name': m.name,
            'avatar': m.avatar,
            'color': m.colorIndex,
            'updated_at': 0,
          },
      ],
      'goal': <String, dynamic>{
        'cleared': app.goalKg == null,
        'member_id': app.activeMemberId,
        'kg': app.goalKg ?? 0,
        'updated_at': 0,
      },
      'records': <Map<String, dynamic>>[
        for (final WeightRecord r in records)
          <String, dynamic>{
            't': r.time.millisecondsSinceEpoch,
            'kg': r.kg,
            'm': r.memberId,
            'd': r.deviceId ?? '',
          },
      ],
    };
    return jsonEncode(body);
  }

  /// Changes to this signature mean a metadata-only batch is worth sending.
  /// Device `last_seen` is excluded so ordinary scans do not trigger uploads.
  String _metaSignature() {
    return jsonEncode(<String, dynamic>{
      'members': <Map<String, dynamic>>[
        for (final Member m in app.members)
          <String, dynamic>{'id': m.id, 'name': m.name, 'avatar': m.avatar, 'color': m.colorIndex},
      ],
      'devices': <Map<String, dynamic>>[
        for (final ScaleDevice d in app.devices) <String, dynamic>{'id': d.id, 'name': d.name},
      ],
      'goal': <String, dynamic>{
        'member': app.activeMemberId,
        'kg': app.goalKg,
      },
    });
  }

  // --- helpers -----------------------------------------------------------

  static String _normalizeUrl(String raw) {
    String url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }

  static String _platform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static String _platformLabel() {
    const Map<String, String> labels = <String, String>{
      'android': 'Android',
      'ios': 'iOS',
      'macos': 'macOS',
      'windows': 'Windows',
      'linux': 'Linux',
      'fuchsia': 'Fuchsia',
    };
    final String key = _platform();
    return labels[key] ?? key;
  }

  static String _randomHex(int bytes) {
    final Random rng = Random.secure();
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      sb.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  Map<String, dynamic>? _decode(http.Response res) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _httpMessage(http.Response res, Map<String, dynamic>? body) {
    final String detail = body?['error'] as String? ?? '';
    if (res.statusCode == 401) {
      return _t('令牌无效，请重新绑定', 'Token rejected — relink required');
    }
    if (res.statusCode == 403) {
      return _t('客户端 ID 与令牌不匹配', 'Client id does not match the token');
    }
    final String prefix = _t('服务器返回 ${res.statusCode}', 'Server returned ${res.statusCode}');
    return detail.isEmpty ? prefix : '$prefix：$detail';
  }

  String _t(String zh, String en) => _zh ? zh : en;
}

class _BatchResult {
  const _BatchResult({required this.accepted, required this.rejected});
  final int accepted;
  final int rejected;
}

class _UploadException implements Exception {
  const _UploadException(this.message);
  final String message;
}
