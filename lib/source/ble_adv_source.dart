import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../service/units.dart';
import 'scale_source.dart';

/// Reads weight from BLE advertisements (Chipsea / OKOK protocol).
///
/// The scale never accepts a GATT connection: it advertises the current weight
/// for ~30s after you step on it, then powers down. So we only listen to
/// advertisements and never connect.
class BleAdvScaleSource extends ScaleSource {
  /// Dump every advertisement to the console. Turn off for production builds.
  final bool debug;

  /// When true, also remember devices that advertise a Chipsea name but whose
  /// payload could not be decoded (useful for identifying a new scale).
  final bool acceptAnyAdvertiser;

  BleAdvScaleSource({this.debug = true, this.acceptAnyAdvertiser = true});

  static const String targetNameFragment = 'chipsea';

  final StreamController<ScaleSample> _sampleCtrl =
      StreamController<ScaleSample>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  Timer? _watchdog;

  final Map<String, SourceDevice> _devices = <String, SourceDevice>{};
  final List<String> _logs = <String>[];
  DateTime _lastPacketAt = DateTime.now();

  SourceState _state = SourceState.idle;
  String _statusCode = 'idle';
  String _statusDetail = '';

  @override
  String get kind => 'ble';

  @override
  SourceState get state => _state;

  @override
  String get statusCode => _statusCode;

  @override
  String get statusDetail => _statusDetail;

  @override
  bool get isRunning => _state == SourceState.running;

  @override
  List<SourceDevice> get devices {
    final List<SourceDevice> list = _devices.values.toList()
      ..sort((a, b) => b.seenAt.compareTo(a.seenAt));
    return list;
  }

  @override
  Stream<ScaleSample> get samples => _sampleCtrl.stream;

  @override
  List<String> get logs => List<String>.unmodifiable(_logs);

  @override
  Future<void> start() async {
    _setState(SourceState.starting, 'scanning');

    final bool ok = await _ensurePermissions();
    if (!ok) {
      _setState(SourceState.permissionDenied, 'perm_denied');
      return;
    }

    _watchdog ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (isRunning &&
          DateTime.now().difference(_lastPacketAt).inSeconds > 25) {
        _startScan();
      }
    });

    final BluetoothAdapterState adapterState =
        await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _setState(SourceState.idle, 'bt_off');
      await FlutterBluePlus.turnOn();
      _adapterSub ??= FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.on && !isRunning) {
          _startScan();
        }
      });
      return;
    }

    await _startScan();
  }

  Future<bool> _ensurePermissions() async {
    // macOS/iOS raise their own system prompt; permission_handler's bluetooth
    // scopes are Android-only, so on other platforms we just let CoreBluetooth
    // ask (the usage description is set in Info.plist).
    if (!_isAndroid) {
      return await FlutterBluePlus.isSupported;
    }

    final Map<Permission, PermissionStatus> statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.any((PermissionStatus s) => s.isPermanentlyDenied)) {
      return false;
    }
    final PermissionStatus scan = statuses[Permission.bluetoothScan]!;
    final PermissionStatus loc = statuses[Permission.location]!;
    return scan.isGranted || loc.isGranted;
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  Future<void> _startScan() async {
    _setState(SourceState.running, 'scanning');

    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();

    _scanSub = FlutterBluePlus.scanResults.listen(
      (List<ScanResult> results) {
        for (final ScanResult r in results) {
          _handleResult(r);
        }
      },
      onError: (Object e) {
        _log('[scan] error: $e');
        _setState(SourceState.error, 'scan_error', e.toString());
      },
    );

    try {
      await FlutterBluePlus.startScan(
        withServices: const <Guid>[], // OKOK scales advertise no service UUID
        continuousUpdates: true,
        oneByOne: true,
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: false,
        androidCheckLocationServices: false,
      );
      _lastPacketAt = DateTime.now();
    } catch (e) {
      _log('[scan] startScan failed: $e');
      _setState(SourceState.error, 'scan_start_failed', e.toString());
    }
  }

  @override
  Future<void> stop() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _setState(SourceState.idle, 'stopped');
  }

  void _handleResult(ScanResult r) {
    final AdvertisementData adv = r.advertisementData;
    final String id = r.device.remoteId.str;
    final String name =
        adv.advName.isNotEmpty ? adv.advName : r.device.platformName;

    final _Reading? reading = _parseAdvertisement(adv);
    final bool nameMatch = name.toLowerCase().contains(targetNameFragment);
    final bool payloadMatch =
        acceptAnyAdvertiser && reading != null && reading.kg > 0;

    if (debug) {
      _log('[adv] name=$name id=$id rssi=${r.rssi} '
          'connectable=${adv.connectable} '
          'msd=${adv.msd.map(_hex).toList()} '
          'serviceData=${adv.serviceData.map((k, v) => MapEntry(k.str, _hex(v)))} '
          'uuids=${adv.serviceUuids.map((g) => g.str).toList()}');
    }

    if (!(nameMatch || payloadMatch)) {
      // Still record the device so the list can show what is around, but do not
      // treat it as a reading.
      if (name.isNotEmpty) {
        _remember(id, name, r.rssi, false);
      }
      return;
    }

    _lastPacketAt = DateTime.now();
    _remember(id, name, r.rssi, reading != null);

    if (reading == null) {
      _setState(SourceState.running, 'no_payload');
      return;
    }

    _setState(
      SourceState.running,
      reading.locked ? 'locked' : 'measuring',
    );

    _sampleCtrl.add(ScaleSample(
      time: DateTime.now(),
      kg: reading.kg,
      locked: reading.locked,
      deviceId: id,
      deviceName: name,
      sourceKind: kind,
    ));
  }

  void _remember(String id, String name, int rssi, bool decoded) {
    final SourceDevice? existing = _devices[id];
    _devices[id] = existing == null
        ? SourceDevice(
            id: id,
            name: name,
            rssi: rssi,
            decoded: decoded,
            seenAt: DateTime.now(),
          )
        : existing.copyWith(
            name: name.isEmpty ? existing.name : name,
            rssi: rssi,
            decoded: decoded || existing.decoded,
            seenAt: DateTime.now(),
          );
    notifyListeners();
  }

  void _setState(SourceState state, String code, [String detail = '']) {
    _state = state;
    _statusCode = code;
    _statusDetail = detail;
    notifyListeners();
  }

  void _log(String line) {
    _logs.add('${DateTime.now().toIso8601String()}  $line');
    if (_logs.length > 300) _logs.removeAt(0);
    if (_scanSub == null && _state == SourceState.idle) return;
    notifyListeners();
  }

  _Reading? _parseAdvertisement(AdvertisementData adv) {
    for (final List<int> bytes in adv.manufacturerData.values) {
      final _Reading? reading = _tryParsePayload(bytes);
      if (reading != null) return reading;
    }
    for (final List<int> bytes in adv.serviceData.values) {
      final _Reading? reading = _tryParsePayload(bytes);
      if (reading != null) return reading;
    }
    return null;
  }

  _Reading? _tryParsePayload(List<int> p) {
    // OKOK 1.1 frame: CA 11 <len> <lock> <type> <wMSB> <wLSB> ... <props@11>
    if (p.length >= 12 && p[0] == 0xCA) {
      final int declaredLen = p[2];
      if (p.length >= 3 + declaredLen + 1) {
        final int raw = (p[5] << 8) | p[6];
        final int props = p[11];
        final int unitBits = (props >> 3) & 0x03;
        final int decBits = (props >> 1) & 0x03;
        final int decimals = decBits == 0x01 ? 0 : (decBits == 0x02 ? 2 : 1);
        if (raw > 0 && raw <= 30000) {
          return _Reading(_toKg(raw / _pow10(decimals), unitBits), p[3] == 0x01);
        }
      }
    }

    // Chipsea advertisement payload:
    // [0..1] weight (big endian), [2..5] resistance, [6] unit + lock
    if (p.length >= 7) {
      final int props = p[6];
      const Set<int> knownProps = <int>{0x24, 0x25, 0x30, 0x31, 0x38, 0x39};
      if (!knownProps.contains(props)) return null;

      final int raw = (p[0] << 8) | p[1];
      if (raw <= 0 || raw > 30000) return null;

      final int unitBits = (props >> 3) & 0x03;
      final bool locked = (props & 0x01) == 0x01;

      if (unitBits == 0x03) {
        final int stones = raw >> 8;
        final double pounds = (raw & 0xFF) / 10.0;
        return _Reading(
          stones * Units.kgPerStone + pounds * Units.kgPerLb,
          locked,
        );
      }
      final double value = unitBits == 0x02 ? raw / 10.0 : raw / 100.0;
      return _Reading(_toKg(value, unitBits), locked);
    }

    return null;
  }

  double _toKg(double value, int unitBits) {
    switch (unitBits) {
      case 0x01:
        return value * 0.5; // jin
      case 0x02:
        return value * Units.kgPerLb;
      default:
        return value;
    }
  }

  double _pow10(int n) {
    double r = 1;
    for (int i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  String _hex(List<int> bytes) =>
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  @override
  void dispose() {
    _watchdog?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    FlutterBluePlus.stopScan();
    _sampleCtrl.close();
    super.dispose();
  }
}

class _Reading {
  final double kg;
  final bool locked;
  const _Reading(this.kg, this.locked);
}
