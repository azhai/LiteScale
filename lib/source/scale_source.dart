import 'package:flutter/foundation.dart';

/// One decoded weight reading from any data source.
class ScaleSample {
  final DateTime time;
  final double kg;
  final bool locked;
  final String deviceId;
  final String deviceName;

  /// Which source produced it: "ble", "mqtt", "http", ...
  final String sourceKind;

  const ScaleSample({
    required this.time,
    required this.kg,
    required this.locked,
    required this.deviceId,
    required this.deviceName,
    required this.sourceKind,
  });
}

/// A device the current source knows about.
class SourceDevice {
  final String id;
  final String name;
  final int rssi;
  final bool decoded;
  final DateTime seenAt;

  const SourceDevice({
    required this.id,
    required this.name,
    this.rssi = 0,
    this.decoded = false,
    required this.seenAt,
  });

  SourceDevice copyWith({String? name, int? rssi, bool? decoded, DateTime? seenAt}) =>
      SourceDevice(
        id: id,
        name: name ?? this.name,
        rssi: rssi ?? this.rssi,
        decoded: decoded ?? this.decoded,
        seenAt: seenAt ?? this.seenAt,
      );
}

/// Coarse state of a source, mapped to UI text by the page.
enum SourceState { idle, starting, running, error, unsupported, permissionDenied }

/// Common interface for anything that can produce weight readings.
///
/// The measure page only talks to this interface, so new transports (MQTT,
/// HTTP POST, a file watcher, ...) can be added without touching the UI: create
/// a subclass, register it in `source_registry.dart`, done.
abstract class ScaleSource extends ChangeNotifier {
  /// Stable id, e.g. "ble".
  String get kind;

  SourceState get state;

  /// Machine readable status code, resolved to text by the UI (see `S.status`).
  String get statusCode;

  /// Extra detail appended to the status (device name, error message, ...).
  String get statusDetail;

  bool get isRunning;

  /// Devices seen since the source was created (newest activity first).
  List<SourceDevice> get devices;

  /// Every decoded reading. Broadcast stream: subscribe before [start].
  Stream<ScaleSample> get samples;

  /// Raw diagnostic lines (one per advertisement / request), newest last.
  List<String> get logs;

  Future<void> start();
  Future<void> stop();
}
