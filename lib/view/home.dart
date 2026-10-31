import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../i18n/strings.dart';
import '../model/entities.dart';
import '../model/weight_record.dart';
import '../service/app_controller.dart';
import '../service/units.dart';
import '../source/scale_source.dart';
import '../source/source_registry.dart';
import 'theme.dart';
import 'widgets/app_widgets.dart';

class ScaleConnectPage extends StatefulWidget {
  final AppController controller;
  const ScaleConnectPage({super.key, required this.controller});

  @override
  State<ScaleConnectPage> createState() => _ScaleConnectPageState();
}

class _ScaleConnectPageState extends State<ScaleConnectPage> {
  late final List<ScaleSource> _sources;
  late ScaleSource _active;
  StreamSubscription<ScaleSample>? _sampleSub;

  double? _lastKg;
  String? _lastDeviceId;
  int _packetCount = 0;
  bool _showLogs = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _sources = buildSources();
    _active = _sources.first;
    _active.addListener(_onSourceChanged);
    _sampleSub = _active.samples.listen(_onSample);
    _active.start();
  }

  void _onSourceChanged() {
    if (mounted) setState(() {});
  }

  void _onSample(ScaleSample sample) {
    _packetCount++;
    _lastDeviceId = sample.deviceId;
    if (mounted) {
      setState(() => _lastKg = sample.kg);
    }
    if (sample.locked) {
      _save(sample);
    }
  }

  Future<void> _save(ScaleSample sample) async {
    await c.rememberDevice(sample.deviceId, sample.deviceName);
    final bool added = await c.addRecord(sample.kg, deviceId: sample.deviceId);
    if (added && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('${c.s.savedToHistory} · ${c.activeMember.name}'),
        ));
    }
  }

  @override
  void dispose() {
    _sampleSub?.cancel();
    _active.removeListener(_onSourceChanged);
    for (final ScaleSource s in _sources) {
      s.dispose();
    }
    super.dispose();
  }

  StatusKey _keyFor(String code) {
    switch (code) {
      case 'scanning':
        return StatusKey.scanning;
      case 'bt_off':
        return StatusKey.btOff;
      case 'perm_denied':
        return StatusKey.permDenied;
      case 'no_payload':
        return StatusKey.noPayload;
      case 'stopped':
        return StatusKey.stopped;
      case 'locked':
        return StatusKey.locked;
      case 'measuring':
        return StatusKey.measuring;
      case 'scan_error':
        return StatusKey.scanError;
      case 'scan_start_failed':
        return StatusKey.scanStartFailed;
      default:
        return StatusKey.idle;
    }
  }

  Color _statusTone(ColorScheme cs) {
    switch (_active.statusCode) {
      case 'locked':
        return cs.primary;
      case 'measuring':
        return cs.tertiary;
      case 'scanning':
        return cs.secondary;
      case 'bt_off':
      case 'perm_denied':
      case 'scan_error':
      case 'scan_start_failed':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }

  /// Most recent stored reading for the active member — shown until a live
  /// advertisement arrives, so the hero is never just an empty placeholder.
  WeightRecord? _latestRecord() {
    WeightRecord? latest;
    for (final WeightRecord r in c.records) {
      if (r.memberId != c.activeMemberId) continue;
      if (latest == null || r.time.isAfter(latest.time)) latest = r;
    }
    return latest;
  }

  /// Goal progress when a goal is set, otherwise the reading's position inside
  /// a 15–35 BMI band. Purely a visual cue, never a medical claim.
  double _ringProgress(double? kg, double? bmi) {
    if (kg == null || kg <= 0) return 0;
    final double? goal = c.activeGoal?.targetKg;
    if (goal != null && goal > 0) return (goal / kg).clamp(0.02, 1.0);
    if (bmi == null) return 0.62;
    return ((bmi - 15) / 20).clamp(0.06, 0.98);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final S s = c.s;
    final bool isZh = s.isZh;
    final WeightRecord? latest = _latestRecord();
    final bool live = _lastKg != null;
    final double? kg = _lastKg ?? latest?.kg;
    final double? bmi = kg == null ? null : c.bmiOf(kg);
    final String unit = Units.label(c.unit, isZh);
    final String weightValue = kg == null
        ? '—'
        : Units.toDisplay(kg, c.unit).toStringAsFixed(c.unit == 'st' ? 2 : 1);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            Text(s.appTitle),
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: t.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: s.debugTitle,
            onPressed: () => setState(() => _showLogs = !_showLogs),
            icon: Icon(
              _showLogs ? Icons.bug_report : Icons.bug_report_outlined,
              color: _showLogs ? t.colorScheme.primary : null,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Insets.page, 4, Insets.page, 28),
        children: <Widget>[
          _memberBar(s),
          const SizedBox(height: Insets.gap),
          _heroCard(s, weightValue, unit, bmi, kg, live, latest),
          const SizedBox(height: Insets.gap + 2),
          _actions(s),
          if (_sources.length > 1) ...<Widget>[
            const SizedBox(height: Insets.gap),
            _sourceBar(s),
          ],
          SectionHeader(
            title: s.tabDevices,
            trailing: Text(
              '${_active.devices.length}',
              style: t.textTheme.labelMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _devicesCard(s),
          if (_showLogs) ...<Widget>[
            SectionHeader(title: s.debugTitle),
            _logCard(s),
          ],
        ],
      ),
    );
  }

  Widget _memberBar(S s) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: c.members.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final Member m = c.members[i];
          final bool selected = c.activeMemberId == m.id;
          return ChoicePill(
            label: m.name,
            selected: selected,
            onTap: () => c.setActiveMember(m.id),
            leading: ClipOval(
              child: Image.asset(
                avatarAssetPath(m.avatar, seed: m.id),
                width: 22,
                height: 22,
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _heroCard(
    S s,
    String weightValue,
    String unit,
    double? bmi,
    double? kg,
    bool live,
    WeightRecord? latest,
  ) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final double? goalKg = c.activeGoal?.targetKg;
    final bool hasGoal = goalKg != null;
    final int memberRecords = c.records
        .where((WeightRecord r) => r.memberId == c.activeMemberId)
        .length;

    String caption;
    if (!live && latest != null) {
      caption = '${s.lastReading} · ${_shortTime(latest.time)}';
    } else if (kg == null) {
      caption = s.measureHint;
    } else if (hasGoal) {
      final double diff = kg - goalKg;
      caption = diff <= 0
          ? s.goalReached
          : '${s.goalDistance} ${Units.format(diff, c.unit, isZh: s.isZh)}';
    } else {
      caption = '${s.bmi} ${bmi!.toStringAsFixed(1)} · ${s.bmiCategory(bmi)}';
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(Insets.card, 16, Insets.card, 14),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          cs.primary.withValues(alpha: t.brightness == Brightness.light
              ? 0.055
              : 0.10),
          Colors.transparent,
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: s.status(
                      _keyFor(_active.statusCode),
                      _active.statusDetail,
                    ),
                    tone: _statusTone(cs),
                  ),
                ),
              ),
              if (_active.isRunning) ...<Widget>[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: cs.primary.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          WeightRing(
            progress: _ringProgress(kg, bmi),
            size: 218,
            stroke: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        weightValue,
                        style: t.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          color: kg == null
                              ? cs.onSurface.withValues(alpha: 0.28)
                              : cs.onSurface,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          unit,
                          style: t.textTheme.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 172,
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: s.bmi,
                  value: bmi?.toStringAsFixed(1) ?? '--',
                ),
              ),
              _vDivider(cs),
              Expanded(
                child: StatTile(
                  label: s.goalDistance,
                  value: hasGoal ? _goalText(s, kg) : s.noGoalSet,
                  align: CrossAxisAlignment.center,
                ),
              ),
              _vDivider(cs),
              Expanded(
                child: StatTile(
                  label: s.recordsTotal,
                  value: '$memberRecords',
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _goalText(S s, double? kg) {
    final double? goal = c.activeGoal?.targetKg;
    if (goal == null) return s.noGoalSet;
    if (kg == null) return '--';
    final double diff = kg - goal;
    if (diff <= 0) return s.goalReached;
    return Units.format(diff, c.unit, isZh: s.isZh);
  }

  String _shortTime(DateTime t) {
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${two(t.hour)}:${two(t.minute)}';
    }
    return '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _vDivider(ColorScheme cs) => Container(
        width: 1,
        height: 26,
        color: cs.outlineVariant.withValues(alpha: 0.6),
      );

  Widget _actions(S s) {
    final bool running = _active.isRunning;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          onPressed: () => running ? _active.stop() : _active.start(),
          icon: Icon(
            running ? Icons.stop_rounded : Icons.bluetooth_searching_rounded,
            size: 20,
          ),
          label: Text(running ? s.stopScan : s.startScan),
        ),
        if (_active.state == SourceState.permissionDenied)
          OutlinedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(s.openSystemSettings),
          ),
      ],
    );
  }

  Widget _sourceBar(S s) {
    return Wrap(
      spacing: 8,
      children: _sources.map((ScaleSource src) {
        return ChoicePill(
          label: src.kind,
          selected: identical(src, _active),
          onTap: () => _switchSource(src),
        );
      }).toList(),
    );
  }

  Future<void> _switchSource(ScaleSource next) async {
    if (identical(next, _active)) return;
    await _active.stop();
    _active.removeListener(_onSourceChanged);
    await _sampleSub?.cancel();

    _active = next;
    _active.addListener(_onSourceChanged);
    _sampleSub = _active.samples.listen(_onSample);
    _active.start();
    setState(() {});
  }

  Widget _devicesCard(S s) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final List<SourceDevice> found = _active.devices;

    if (found.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.sensors_off_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                s.devicesEmpty,
                style: t.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final List<SourceDevice> shown = found.take(5).toList();
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < shown.length; i++) ...<Widget>[
            if (i > 0)
              Divider(color: cs.outlineVariant.withValues(alpha: 0.6)),
            _deviceRow(s, shown[i]),
          ],
        ],
      ),
    );
  }

  Widget _deviceRow(S s, SourceDevice d) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final bool current = d.id == _lastDeviceId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: <Widget>[
          IconBadge(
            icon: d.decoded
                ? Icons.monitor_weight_outlined
                : Icons.bluetooth_rounded,
            tint: d.decoded ? cs.primary : cs.onSurfaceVariant,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  d.name.isEmpty ? s.noDeviceTag : d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodyMedium?.copyWith(
                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${d.id}  ·  ${d.rssi} dBm',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (current)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle, size: 16, color: cs.primary),
            ),
        ],
      ),
    );
  }

  Widget _logCard(S s) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final List<String> logs = _active.logs;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                s.packets,
                style: t.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '$_packetCount',
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            Text(
              '--',
              style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            ...logs.reversed.take(8).map(
                  (String line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style: t.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.4,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
