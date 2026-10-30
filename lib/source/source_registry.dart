import 'ble_adv_source.dart';
import 'scale_source.dart';

/// Overridable factory used by tests and previews to inject fake sources.
/// Production code never sets this.
List<ScaleSource> Function()? sourceFactoryOverride;

/// Registry of available data sources.
///
/// To add a transport (e.g. a scale that POSTs to an HTTP endpoint, or one that
/// publishes over MQTT), implement [ScaleSource] and append an instance here.
/// The measure page renders one entry per source and needs no changes.
///
/// Example skeleton:
///
/// ```dart
/// class HttpPostScaleSource extends ScaleSource {
///   @override String get kind => 'http';
///   // ... start(): bind a local server / poll an endpoint, then add
///   // ScaleSample(...) to your broadcast stream for every reading.
/// }
/// ```
List<ScaleSource> buildSources() =>
    sourceFactoryOverride?.call() ??
    <ScaleSource>[
      BleAdvScaleSource(),
    ];
