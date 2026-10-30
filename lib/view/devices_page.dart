import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../model/entities.dart';
import '../model/weight_record.dart';
import '../service/app_controller.dart';
import 'theme.dart';
import 'widgets/app_widgets.dart';

class DevicesPage extends StatelessWidget {
  final AppController controller;
  const DevicesPage({super.key, required this.controller});

  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(c.s.tabDevices)),
      body: AnimatedBuilder(
        animation: c,
        builder: (BuildContext context, Widget? _) {
          final S s = c.s;
          final ThemeData t = Theme.of(context);
          final List<ScaleDevice> devices = c.devices;

          if (devices.isEmpty) {
            return EmptyState(
              icon: Icons.bluetooth_disabled_rounded,
              text: s.devicesEmpty,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              Insets.page,
              6,
              Insets.page,
              28,
            ),
            itemCount: devices.length,
            separatorBuilder: (BuildContext _, int __) =>
                const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              final ScaleDevice d = devices[index];
              final int count = c.records
                  .where((WeightRecord r) => r.deviceId == d.id)
                  .length;

              return AppCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: IconBadge(
                        icon: Icons.monitor_weight_outlined,
                        size: 44,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            d.name.isEmpty ? s.noDeviceTag : d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            d.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              letterSpacing: 0.3,
                              color: t.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              StatusPill(
                                label: _formatTime(d.lastSeen),
                                tone: t.colorScheme.onSurfaceVariant,
                                icon: Icons.schedule_rounded,
                              ),
                              StatusPill(
                                label: s.recordsCount(count),
                                tone: t.colorScheme.primary,
                                icon: Icons.timeline_rounded,
                              ),
                            ],
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
                        color: t.colorScheme.onSurfaceVariant,
                      ),
                      onSelected: (String action) {
                        if (action == 'rename') {
                          _rename(context, s, d);
                        } else {
                          _remove(context, s, d);
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'rename',
                          child: Text(s.rename),
                        ),
                        PopupMenuItem<String>(
                          value: 'remove',
                          child: Text(s.remove),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _rename(BuildContext context, S s, ScaleDevice d) async {
    final TextEditingController ctrl = TextEditingController(text: d.name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(s.renameDevice),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: s.deviceName),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(s.save),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await c.renameDevice(d.id, name.trim());
    }
  }

  Future<void> _remove(BuildContext context, S s, ScaleDevice d) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(s.removeDevice),
        content: Text(s.removeDeviceHint),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.remove),
          ),
        ],
      ),
    );
    if (ok == true) await c.removeDevice(d.id);
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
