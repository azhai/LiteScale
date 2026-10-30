import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../model/entities.dart';
import '../service/app_controller.dart';
import '../service/csv.dart';
import '../service/file_saver.dart';
import '../service/units.dart';
import '../service/uploader.dart';
import 'theme.dart';
import 'widgets/app_widgets.dart';

class SettingsPage extends StatefulWidget {
  final AppController controller;
  final Uploader uploader;
  const SettingsPage({
    super.key,
    required this.controller,
    required this.uploader,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _heightCtrl;
  late final TextEditingController _goalCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _enrollCtrl;

  @override
  void initState() {
    super.initState();
    _heightCtrl = TextEditingController(
      text: widget.controller.heightCm.toStringAsFixed(0),
    );
    final double? goal = widget.controller.goalKg;
    _goalCtrl = TextEditingController(
      text: goal == null
          ? ''
          : Units.toDisplay(goal, widget.controller.unit).toStringAsFixed(1),
    );
    _urlCtrl = TextEditingController(text: widget.uploader.baseUrl);
    _enrollCtrl = TextEditingController(text: widget.uploader.enrollKey);
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _goalCtrl.dispose();
    _urlCtrl.dispose();
    _enrollCtrl.dispose();
    super.dispose();
  }

  AppController get c => widget.controller;
  Uploader get u => widget.uploader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(c.s.tabSettings)),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[c, u]),
        builder: (BuildContext context, Widget? _) {
          final S s = c.s;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.page,
              4,
              Insets.page,
              32,
            ),
            children: <Widget>[
              SectionHeader(title: s.members, top: 6),
              _membersCard(s),
              SectionHeader(title: s.bodyData),
              _bodyCard(s),
              SectionHeader(title: s.unit),
              _unitCard(s),
              SectionHeader(title: s.language),
              _languageCard(s),
              SectionHeader(title: s.appearance),
              _appearanceCard(s),
              SectionHeader(title: s.data),
              _dataCard(s),
              SectionHeader(title: s.upload),
              _uploadCard(s),
              SectionHeader(title: s.about),
              _aboutCard(s),
            ],
          );
        },
      ),
    );
  }

  // --- members -----------------------------------------------------------

  Widget _membersCard(S s) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < c.members.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 66),
                child: Divider(
                  color: cs.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            _memberRow(s, c.members[i]),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _addMember(s),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(s.addMember),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(S s, Member m) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final bool active = c.activeMemberId == m.id;

    return InkWell(
      onTap: () => c.setActiveMember(m.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _avatarColor(m.colorIndex),
                shape: BoxShape.circle,
              ),
              child: Text(m.avatar, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(m.name, style: t.textTheme.titleMedium),
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        s.activeMember,
                        style: t.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (active)
              Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
            PopupMenuButton<String>(
              tooltip: '',
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              onSelected: (String action) {
                if (action == 'rename') {
                  _renameMember(s, m);
                } else if (action == 'avatar') {
                  _pickAvatar(s, m);
                } else {
                  _removeMember(s, m);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'rename',
                  child: Text(s.rename),
                ),
                PopupMenuItem<String>(
                  value: 'avatar',
                  child: Text(s.avatar),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(s.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- body data ---------------------------------------------------------

  Widget _bodyCard(S s) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(Insets.card, 6, Insets.card, 14),
      child: Column(
        children: <Widget>[
          _fieldRow(
            label: s.height,
            controller: _heightCtrl,
            suffix: 'cm',
            onSubmitted: () => _saveHeight(s),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          _fieldRow(
            label: s.goalWeight,
            controller: _goalCtrl,
            suffix: Units.label(c.unit, s.isZh),
            hint: s.goalHint,
            onSubmitted: () => _saveGoal(s),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  s.avatarLocalOnly,
                  style: t.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () {
                  _saveHeight(s);
                  _saveGoal(s);
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(s.saveChanges),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compact number field (fixed width) instead of a full-bleed input.
  Widget _fieldRow({
    required String label,
    required TextEditingController controller,
    String? suffix,
    String? hint,
    required VoidCallback onSubmitted,
  }) {
    final ThemeData t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: t.textTheme.bodyMedium),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      hint,
                      style: t.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: t.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 104,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                suffixText: suffix,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
              ),
              onSubmitted: (String _) => onSubmitted(),
            ),
          ),
        ],
      ),
    );
  }

  // --- unit / language / appearance --------------------------------------

  Widget _unitCard(S s) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Insets.card, 12, Insets.card, 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          segments: Units.all
              .map((String u) => ButtonSegment<String>(
                    value: u,
                    label: Text(Units.label(u, s.isZh)),
                  ))
              .toList(),
          selected: <String>{c.unit},
          showSelectedIcon: false,
          onSelectionChanged: (Set<String> v) => c.setUnit(v.first),
        ),
      ),
    );
  }

  Widget _languageCard(S s) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Insets.card, 12, Insets.card, 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<AppLang>(
          segments: <ButtonSegment<AppLang>>[
            ButtonSegment<AppLang>(
              value: AppLang.zh,
              label: Text(s.chinese),
            ),
            ButtonSegment<AppLang>(
              value: AppLang.en,
              label: Text(s.english),
            ),
          ],
          selected: <AppLang>{c.lang},
          showSelectedIcon: false,
          onSelectionChanged: (Set<AppLang> v) => c.setLang(v.first),
        ),
      ),
    );
  }

  Widget _appearanceCard(S s) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: c.darkMode,
        onChanged: (bool v) => c.setDarkMode(v),
        secondary: const IconBadge(icon: Icons.dark_mode_outlined, size: 38),
        title: Text(s.darkMode),
      ),
    );
  }

  // --- data --------------------------------------------------------------

  Widget _dataCard(S s) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: <Widget>[
          _dataRow(
            icon: Icons.upload_file_rounded,
            title: s.exportCsv,
            subtitle: '${c.records.length} ${s.recordCount}',
            onTap: () => _exportCsv(s),
          ),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.6)),
          _dataRow(
            icon: Icons.download_rounded,
            title: s.importCsv,
            subtitle: s.csvFormat,
            onTap: () => _importCsv(s),
          ),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.6)),
          _dataRow(
            icon: Icons.delete_outline_rounded,
            title: s.clearAll,
            subtitle: s.clearAllConfirm,
            tint: cs.error,
            onTap: () => _clearAll(s),
          ),
        ],
      ),
    );
  }

  Widget _dataRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? tint,
  }) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final Color base = tint ?? cs.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: <Widget>[
            IconBadge(icon: icon, tint: base, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: t.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tint == null ? cs.onSurface : base,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // --- server upload -----------------------------------------------------

  Widget _uploadCard(S s) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final bool failed = u.error.isNotEmpty;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: u.enabled,
            onChanged: (bool v) => _toggleUpload(s, v),
            secondary: const IconBadge(
              icon: Icons.cloud_upload_outlined,
              size: 38,
            ),
            title: Text(s.uploadSwitch),
            subtitle: Text(
              u.enabled ? s.uploadEnabledHint : s.uploadHint,
              style: t.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.6)),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 88,
                        child: Text(s.serverUrl, style: t.textTheme.bodySmall),
                      ),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: TextField(
                            controller: _urlCtrl,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: s.serverUrlHint,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (String _) => _saveUpload(s),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _saveUpload(s),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: Text(s.save),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 88,
                        child: Text(
                          s.enrollKeyLabel,
                          style: t.textTheme.bodySmall,
                        ),
                      ),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: TextField(
                            controller: _enrollCtrl,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (String _) => _saveUpload(s),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _uploadStatus(s),
                          style: t.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            height: 1.35,
                            color: failed ? cs.error : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: u.busy ? null : () => u.relink(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Text(s.relink),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.tonalIcon(
                        onPressed: u.busy ? null : () => u.syncNow(),
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: Text(s.syncNow),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _uploadStatus(S s) {
    if (u.busy) return s.syncing;
    if (u.error.isNotEmpty) return u.error;
    if (u.lastSyncMs == 0) return s.neverSynced;
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(u.lastSyncMs);
    final String time = TimeOfDay.fromDateTime(at).format(context);
    return s.lastSyncAt(time);
  }

  Future<void> _toggleUpload(S s, bool value) async {
    if (value && _urlCtrl.text.trim().isNotEmpty) {
      await u.configure(url: _urlCtrl.text, enrollKey: _enrollCtrl.text);
    }
    await u.setEnabled(value);
  }

  Future<void> _saveUpload(S s) async {
    if (_urlCtrl.text.trim().isEmpty) {
      _snack(s.uploadNeedUrl);
      return;
    }
    await u.configure(url: _urlCtrl.text, enrollKey: _enrollCtrl.text);
    _urlCtrl.text = u.baseUrl;
    _snack(s.saved);
  }

  // --- about -------------------------------------------------------------

  Widget _aboutCard(S s) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(Insets.card),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const IconBadge(icon: Icons.monitor_weight_outlined, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('LiteScale', style: t.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  s.aboutBody,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- actions -----------------------------------------------------------

  Future<void> _addMember(S s) async {
    final String? name = await _askName(s, s.addMember, '');
    if (name == null || name.trim().isEmpty) return;
    final Member created = await c.addMember(name.trim());
    await c.setActiveMember(created.id);
  }

  Future<void> _renameMember(S s, Member m) async {
    final String? name = await _askName(s, s.renameMember, m.name);
    if (name == null || name.trim().isEmpty) return;
    await c.renameMember(m.id, name.trim());
  }

  Future<void> _removeMember(S s, Member m) async {
    if (c.members.length <= 1) {
      _snack(s.cantRemoveLast);
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(s.removeMember),
        content: Text(s.removeMemberHint),
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
    if (ok == true) await c.removeMember(m.id);
  }

  Future<String?> _askName(S s, String title, String initial) {
    final TextEditingController ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: s.memberName),
          onSubmitted: (String v) => Navigator.pop(context, v),
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
  }

  Future<void> _exportCsv(S s) async {
    final String csv = CsvService.export(c.records, c);
    final String date = DateTime.now().toIso8601String().substring(0, 10);
    final String fileName = 'litescale-$date.csv';
    // BOM so Excel opens UTF-8 correctly.
    final Uint8List bytes = Uint8List.fromList(utf8.encode('\ufeff$csv'));

    try {
      // file_picker: bytes are only accepted on Android/iOS (where the plugin
      // writes the file). On macOS it throws UnsupportedError("Bytes are not
      // supported on macOS") — there we get a path back and write it ourselves.
      final bool pluginWrites = pickerWritesBytes;
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: s.exportCsv,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: <String>['csv'],
        bytes: pluginWrites ? bytes : null,
      );
      if (path == null) return; // user cancelled the dialog
      final String saved =
          pluginWrites ? path : await writeBytesToPath(path, bytes);
      _snack('${s.exported}: $saved');
    } catch (e) {
      // The dialog succeeded but the write was blocked (sandbox, read-only
      // volume, ...). Fall back to the temp folder so nothing is lost.
      try {
        final String fallback = await writeBytesToTemp(fileName, bytes);
        _snack('${s.exportedToTemp}: $fallback');
      } catch (_) {
        _snack('${s.exportFailed}: $e');
      }
    }
  }

  Future<void> _importCsv(S s) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: s.importCsv,
        type: FileType.custom,
        allowedExtensions: <String>['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final PlatformFile file = result.files.single;
      final Uint8List? bytes = file.bytes;
      final String content = bytes != null
          ? utf8.decode(bytes, allowMalformed: true)
          : '';
      if (content.isEmpty) {
        _snack(s.importFailed);
        return;
      }
      final CsvImportResult parsed = CsvService.parse(content, c);
      final int added = await c.importRecords(parsed.records);
      _snack(s.importResult(added));
    } catch (e) {
      _snack('${s.importFailed}: $e');
    }
  }

  Future<void> _clearAll(S s) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(s.clearAll),
        content: Text(s.clearAllConfirm),
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
    if (ok == true) await c.clearRecords();
  }

  void _saveHeight(S s) {
    final double? v = double.tryParse(_heightCtrl.text.trim());
    if (v == null || v <= 0) {
      _snack(s.invalidNumber);
      return;
    }
    c.setHeightCm(v);
    _snack(s.saved);
  }

  void _saveGoal(S s) {
    final String text = _goalCtrl.text.trim();
    if (text.isEmpty) {
      c.setGoalKg(null);
      _snack(s.saved);
      return;
    }
    final double? v = double.tryParse(text);
    if (v == null || v <= 0) {
      _snack(s.invalidNumber);
      return;
    }
    c.setGoalKg(Units.fromDisplay(v, c.unit));
    _snack(s.saved);
  }

  Color _avatarColor(int index) {
    const List<Color> palette = <Color>[
      Color(0xFFD6F2E9),
      Color(0xFFE3F2FD),
      Color(0xFFE8F5E9),
      Color(0xFFFFF3E0),
      Color(0xFFFCE4EC),
      Color(0xFFE0F7FA),
    ];
    return palette[index % palette.length];
  }

  Future<void> _pickAvatar(S s, Member m) async {
    final ThemeData t = Theme.of(context);
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(s.avatar),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kAvatarEmojis
                .map((String e) => InkWell(
                      onTap: () => Navigator.pop(context, e),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: m.avatar == e
                              ? t.colorScheme.primaryContainer
                              : t.colorScheme.surfaceContainerHigh,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ))
                .toList(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
        ],
      ),
    );
    if (picked != null) await c.setMemberAvatar(m.id, avatar: picked);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}
