import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../model/entities.dart';
import '../model/weight_record.dart';
import '../service/app_controller.dart';
import '../service/units.dart';
import 'theme.dart';
import 'widgets/app_widgets.dart';

class HistoryPage extends StatefulWidget {
  final AppController controller;
  const HistoryPage({super.key, required this.controller});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  int _rangeIndex = 1; // 0:7d 1:30d 2:90d 3:all
  String? _memberFilter; // null = all members
  String? _deviceFilter; // null = all devices

  @override
  void initState() {
    super.initState();
    // A trend line mixing several people is meaningless, so default to the
    // member whose measurements the app is currently recording.
    _memberFilter = widget.controller.activeMemberId;
  }

  static const List<int> _rangeDays = <int>[7, 30, 90, 0];
  static const String _all = '__all';

  AppController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(c.s.tabHistory)),
      body: AnimatedBuilder(
        animation: c,
        builder: (BuildContext context, Widget? _) {
          final S s = c.s;
          final List<WeightRecord> records = c.filteredRecords(
            memberId: _memberFilter,
            deviceId: _deviceFilter,
            days: _rangeDays[_rangeIndex],
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.page,
              4,
              Insets.page,
              28,
            ),
            children: <Widget>[
              _filters(s),
              if (records.isEmpty)
                EmptyState(icon: Icons.show_chart_rounded, text: s.historyEmpty)
              else ...<Widget>[
                const SizedBox(height: Insets.gap + 2),
                _chartCard(s, records),
                SectionHeader(title: s.statistics),
                _statsCard(s, records),
                ..._recordGroups(s, records),
              ],
            ],
          );
        },
      ),
    );
  }

  // --- filters -----------------------------------------------------------

  Widget _filters(S s) {
    final List<String> labels =
        <String>[s.range7, s.range30, s.range90, s.rangeAll];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: List<ButtonSegment<int>>.generate(
              labels.length,
              (int i) => ButtonSegment<int>(value: i, label: Text(labels[i])),
            ),
            selected: <int>{_rangeIndex},
            showSelectedIcon: false,
            onSelectionChanged: (Set<int> v) =>
                setState(() => _rangeIndex = v.first),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _memberMenu(s),
            _deviceMenu(s),
          ],
        ),
      ],
    );
  }

  Widget _memberMenu(S s) {
    Member? picked;
    for (final Member m in c.members) {
      if (m.id == _memberFilter) picked = m;
    }
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (String v) =>
          setState(() => _memberFilter = v == _all ? null : v),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          value: _all,
          checked: _memberFilter == null,
          child: Text(s.allMembers),
        ),
        ...c.members.map(
          (Member m) => CheckedPopupMenuItem<String>(
            value: m.id,
            checked: _memberFilter == m.id,
            child: Text(m.name),
          ),
        ),
      ],
      child: ChoicePill(
        label: picked?.name ?? s.allMembers,
        selected: _memberFilter != null,
        trailing: const Icon(Icons.expand_more_rounded, size: 16),
      ),
    );
  }

  Widget _deviceMenu(S s) {
    ScaleDevice? picked;
    for (final ScaleDevice d in c.devices) {
      if (d.id == _deviceFilter) picked = d;
    }
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (String v) =>
          setState(() => _deviceFilter = v == _all ? null : v),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          value: _all,
          checked: _deviceFilter == null,
          child: Text(s.allDevices),
        ),
        ...c.devices.map(
          (ScaleDevice d) => CheckedPopupMenuItem<String>(
            value: d.id,
            checked: _deviceFilter == d.id,
            child: Text(d.name.isEmpty ? d.id : d.name),
          ),
        ),
      ],
      child: ChoicePill(
        label: picked == null
            ? s.allDevices
            : (picked.name.isEmpty ? picked.id : picked.name),
        selected: _deviceFilter != null,
        trailing: const Icon(Icons.expand_more_rounded, size: 16),
      ),
    );
  }

  // --- chart -------------------------------------------------------------

  Widget _chartCard(S s, List<WeightRecord> records) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;

    final List<FlSpot> spots = records
        .map((WeightRecord r) => FlSpot(
              r.time.millisecondsSinceEpoch.toDouble(),
              Units.toDisplay(r.kg, c.unit),
            ))
        .toList();

    final List<FlSpot> maSpots = <FlSpot>[];
    for (int i = 0; i < records.length; i++) {
      final int from = i - 6 < 0 ? 0 : i - 6;
      double sum = 0;
      for (int j = from; j <= i; j++) {
        sum += Units.toDisplay(records[j].kg, c.unit);
      }
      maSpots.add(FlSpot(
        records[i].time.millisecondsSinceEpoch.toDouble(),
        sum / (i - from + 1),
      ));
    }

    final double minY = spots.map((FlSpot p) => p.y).reduce(min);
    final double maxY = spots.map((FlSpot p) => p.y).reduce(max);
    final double pad = (maxY - minY).abs() < 0.5 ? 0.5 : (maxY - minY) * 0.18;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(Insets.card, 16, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(s.trend, style: t.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${minY.toStringAsFixed(1)} – '
                      '${maxY.toStringAsFixed(1)} '
                      '${Units.label(c.unit, s.isZh)}',
                      style: t.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _legend(cs.primary, s.weightLabel),
                if (maSpots.length >= 2) ...<Widget>[
                  const SizedBox(width: 12),
                  _legend(cs.tertiary, s.movingAverage),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 196,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                lineBarsData: <LineChartBarData>[
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.22,
                    color: cs.primary,
                    barWidth: 2.4,
                    dotData: FlDotData(
                      show: spots.length <= 24,
                      getDotPainter: (
                        FlSpot spot,
                        double percent,
                        LineChartBarData bar,
                        int index,
                      ) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: Colors.white,
                        strokeWidth: 2,
                        strokeColor: cs.primary,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          cs.primary.withValues(alpha: 0.22),
                          cs.primary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                  if (maSpots.length >= 2)
                    LineChartBarData(
                      spots: maSpots,
                      isCurved: true,
                      curveSmoothness: 0.22,
                      color: cs.tertiary,
                      barWidth: 1.6,
                      dashArray: <int>[5, 4],
                      dotData: const FlDotData(show: false),
                    ),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY + 2 * pad) / 4,
                  getDrawingHorizontalLine: (double v) => FlLine(
                    color: cs.outlineVariant.withValues(alpha: 0.55),
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: <HorizontalLine>[
                    if (c.goalKg != null)
                      HorizontalLine(
                        y: Units.toDisplay(c.goalKg!, c.unit),
                        color: cs.secondary,
                        strokeWidth: 1.2,
                        dashArray: <int>[2, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.only(right: 4, bottom: 2),
                          style: t.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: cs.secondary,
                          ),
                          labelResolver: (HorizontalLine line) => s.goalLine,
                        ),
                      ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  // Y range lives in the card header, so the plot keeps a clean
                  // left edge instead of a stack of cramped axis labels.
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      minIncluded: false,
                      maxIncluded: false,
                      interval: spots.length < 2
                          ? null
                          : (spots.last.x - spots.first.x) / 3,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final DateTime time =
                            DateTime.fromMillisecondsSinceEpoch(value.toInt());
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${time.month}/${time.day}',
                            style: t.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (LineBarSpot spot) => cs.inverseSurface,
                    getTooltipItems: (List<LineBarSpot> touched) => touched
                        .map((LineBarSpot spot) => LineTooltipItem(
                              '${spot.y.toStringAsFixed(1)} '
                              '${Units.label(c.unit, c.s.isZh)}',
                              (t.textTheme.labelMedium ?? const TextStyle())
                                  .copyWith(color: cs.onInverseSurface),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 10,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      );

  // --- stats -------------------------------------------------------------

  double? _changeOver(int days, List<WeightRecord> records) {
    if (records.isEmpty) return null;
    final double latest = records.last.kg;
    final DateTime target = records.last.time.subtract(Duration(days: days));
    WeightRecord? best;
    for (final WeightRecord r in records) {
      if (r.time.isAfter(target)) break;
      best = r;
    }
    return best == null ? null : latest - best.kg;
  }

  String _fmtDelta(double? d) {
    if (d == null) return '--';
    final String sign = d >= 0 ? '+' : '-';
    return '$sign${Units.toDisplay(d.abs(), c.unit).toStringAsFixed(1)}';
  }

  Widget _statsCard(S s, List<WeightRecord> records) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;

    final List<double> values = records.map((WeightRecord r) => r.kg).toList();
    final double latest = values.last;
    final double min = values.reduce((double a, double b) => a < b ? a : b);
    final double max = values.reduce((double a, double b) => a > b ? a : b);
    final double avg =
        values.reduce((double a, double b) => a + b) / values.length;
    final double? d7 = _changeOver(7, records);
    final double? d30 = _changeOver(30, records);
    final double? bmi = c.bmiOf(latest);

    Color deltaColor(double? d) {
      if (d == null) return cs.onSurface;
      return d <= 0 ? cs.primary : cs.tertiary;
    }

    final List<Widget> tiles = <Widget>[
      StatTile(
        label: s.latest,
        value: Units.format(latest, c.unit, isZh: s.isZh),
      ),
      StatTile(
        label: s.average,
        value: Units.format(avg, c.unit, isZh: s.isZh),
      ),
      StatTile(
        label: s.minimum,
        value: Units.format(min, c.unit, isZh: s.isZh),
      ),
      StatTile(
        label: s.maximum,
        value: Units.format(max, c.unit, isZh: s.isZh),
      ),
      StatTile(
        label: s.change7d,
        value: _fmtDelta(d7),
        unit: d7 == null ? null : Units.label(c.unit, s.isZh),
        color: deltaColor(d7),
      ),
      StatTile(
        label: s.change30d,
        value: _fmtDelta(d30),
        unit: d30 == null ? null : Units.label(c.unit, s.isZh),
        color: deltaColor(d30),
      ),
      StatTile(
        label: s.bmi,
        value: bmi == null ? '--' : bmi.toStringAsFixed(1),
        color: bmi == null ? cs.onSurfaceVariant : null,
      ),
      StatTile(
        label: s.goalDistance,
        value: c.goalKg == null
            ? s.noGoalSet
            : (latest <= c.goalKg!
                ? s.goalReached
                : Units.format(latest - c.goalKg!, c.unit, isZh: s.isZh)),
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.fromLTRB(Insets.card, 16, Insets.card, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                s.recordsCount(records.length),
                style: t.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (bmi != null)
                Text(
                  s.bmiCategory(bmi),
                  style: t.textTheme.labelMedium?.copyWith(color: cs.primary),
                ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints cons) {
              final double w = (cons.maxWidth - 16) / 2;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: tiles
                    .map((Widget tile) => SizedBox(width: w, child: tile))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // --- records -----------------------------------------------------------

  List<Widget> _recordGroups(S s, List<WeightRecord> records) {
    final List<WeightRecord> descending = records.reversed.toList();
    final Map<String, List<WeightRecord>> groups =
        <String, List<WeightRecord>>{};
    for (final WeightRecord r in descending) {
      groups.putIfAbsent(_dayKey(r.time), () => <WeightRecord>[]).add(r);
    }

    final List<Widget> out = <Widget>[];
    groups.forEach((String key, List<WeightRecord> items) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
        child: Text(
          _dayLabel(key),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ));
      out.add(_dayCard(s, items));
    });
    return out;
  }

  Widget _dayCard(S s, List<WeightRecord> items) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 64),
                child: Divider(
                  color: cs.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            _recordRow(s, items[i]),
          ],
        ],
      ),
    );
  }

  Widget _recordRow(S s, WeightRecord r) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final String device = c.deviceNameOf(r) ?? s.noDeviceTag;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              _timeOnly(r.time),
              style: t.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Units.formatDetailed(r.kg, c.unit, isZh: s.isZh),
                  style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${c.memberOf(r).avatar} ${c.memberOf(r).name} · $device',
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
          PopupMenuButton<String>(
            tooltip: '',
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            onSelected: (String action) {
              if (action == 'member') {
                _pickMember(s, r);
              } else {
                _confirmDelete(s, r);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'member',
                child: Text(s.changeMember),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(s.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  String _dayLabel(String key) {
    final S s = c.s;
    final DateTime now = DateTime.now();
    if (key == _dayKey(now)) return s.today;
    if (key == _dayKey(now.subtract(const Duration(days: 1)))) {
      return s.yesterday;
    }
    return key;
  }

  String _timeOnly(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickMember(S s, WeightRecord r) async {
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: Text(s.changeMember),
        children: c.members
            .map((Member m) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, m.id),
                  child: Text(
                    m.name,
                    style: TextStyle(
                      fontWeight:
                          m.id == r.memberId ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
    if (picked != null) await c.setRecordMember(r, picked);
  }

  Future<void> _confirmDelete(S s, WeightRecord r) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(s.deleteRecord),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok == true) await c.removeRecord(r);
  }

  double min(double a, double b) => a < b ? a : b;
  double max(double a, double b) => a > b ? a : b;
}
