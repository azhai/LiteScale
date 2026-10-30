enum AppLang { zh, en }

/// Status codes used by the measure page, resolved to text through [S.status].
enum StatusKey {
  idle,
  scanning,
  locked,
  measuring,
  btOff,
  permDenied,
  noPayload,
  stopped,
  scanError,
  scanStartFailed,
}

/// Minimal hand-rolled localisation (no flutter_localizations needed).
class S {
  final AppLang lang;
  const S(this.lang);

  bool get isZh => lang == AppLang.zh;
  String get langCode => isZh ? 'zh' : 'en';

  // --- shell
  String get appTitle => isZh ? 'LiteScale' : 'LiteScale';
  String get tabMeasure => isZh ? '测量' : 'Measure';
  String get tabHistory => isZh ? '历史' : 'History';
  String get tabDevices => isZh ? '设备' : 'Devices';
  String get tabSettings => isZh ? '设置' : 'Settings';

  // --- measure page
  String get currentWeight => isZh ? '当前体重' : 'Current Weight';
  String get locked => isZh ? '已锁定' : 'Locked';
  String get measuring => isZh ? '测量中' : 'Measuring';
  String get startScan => isZh ? '开始扫描' : 'Start Scanning';
  String get stopScan => isZh ? '停止扫描' : 'Stop Scanning';
  String get openSystemSettings => isZh ? '打开系统设置' : 'Open App Settings';
  String get debugTitle => isZh ? '调试' : 'Debug';
  String get packets => isZh ? '数据包' : 'packets';
  String get savedToHistory => isZh ? '已保存到历史记录' : 'Saved to history';
  String get bmi => 'BMI';
  String get noHeightSet => isZh ? '请先到设置填写身高' : 'Set your height in Settings first';
  String get currentMember => isZh ? '当前成员' : 'Active member';
  String get measureHint =>
      isZh ? '站上体重秤，数据会自动同步' : 'Step on the scale — it syncs automatically';
  String get today => isZh ? '今天' : 'Today';
  String get yesterday => isZh ? '昨天' : 'Yesterday';
  String get overview => isZh ? '概览' : 'Overview';
  String get bodyData => isZh ? '身体数据' : 'Body data';
  String get appearance => isZh ? '外观' : 'Appearance';
  String get unitsShort => isZh ? '单位' : 'Units';
  String get recordsTotal => isZh ? '记录' : 'records';
  String get weightLabel => isZh ? '体重' : 'Weight';
  String recordsCount(int n) => isZh ? '$n 条记录' : '$n records';
  String get saveChanges => isZh ? '保存' : 'Save';
  String get noData => isZh ? '暂无数据' : 'No data yet';
  String get lastTime => isZh ? '上次' : 'Last';
  String get lastReading => isZh ? '上次测量' : 'Last reading';

  String status(StatusKey key, [String? arg]) {
    final String text;
    switch (key) {
      case StatusKey.idle:
        text = isZh ? '准备就绪' : 'Ready';
      case StatusKey.scanning:
        text = isZh
            ? '正在扫描…请站上体重秤唤醒它'
            : 'Scanning... Step on the scale to wake it up';
      case StatusKey.locked:
        text = isZh ? '测量完成，数据已锁定' : 'Measurement locked';
      case StatusKey.measuring:
        text = isZh ? '测量中…请保持站立' : 'Measuring... stay on the scale';
      case StatusKey.btOff:
        text = isZh ? '蓝牙未开启，请打开蓝牙' : 'Bluetooth is off. Please turn it on.';
      case StatusKey.permDenied:
        text = isZh
            ? '蓝牙权限被拒绝，请授权后重试'
            : 'Bluetooth permissions denied. Grant them and try again.';
      case StatusKey.noPayload:
        text = isZh
            ? '已发现设备，但暂时无法解析其广播数据'
            : 'Scale found, but its payload could not be decoded yet.';
      case StatusKey.stopped:
        text = isZh ? '已停止扫描' : 'Scan stopped.';
      case StatusKey.scanError:
        text = isZh ? '扫描出错' : 'Scan error';
      case StatusKey.scanStartFailed:
        text = isZh ? '无法启动扫描' : 'Failed to start scan';
    }
    return arg == null || arg.isEmpty ? text : '$text: $arg';
  }

  // --- history page
  String get historyEmpty => isZh ? '没有符合条件的记录' : 'No records match the filters.';
  String get range7 => isZh ? '7天' : '7d';
  String get range30 => isZh ? '30天' : '30d';
  String get range90 => isZh ? '90天' : '90d';
  String get rangeAll => isZh ? '全部' : 'All';
  String get trend => isZh ? '体重趋势' : 'Weight Trend';
  String get movingAverage => isZh ? '7次均线' : '7-point Average';
  String get statistics => isZh ? '统计分析' : 'Statistics';
  String get latest => isZh ? '最新' : 'Latest';
  String get minimum => isZh ? '最低' : 'Min';
  String get maximum => isZh ? '最高' : 'Max';
  String get average => isZh ? '平均' : 'Avg';
  String get change7d => isZh ? '7天变化' : '7-day Change';
  String get change30d => isZh ? '30天变化' : '30-day Change';
  String get recordCount => isZh ? '记录数' : 'Records';
  String get delete => isZh ? '删除' : 'Delete';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get save => isZh ? '保存' : 'Save';
  String get saved => isZh ? '已保存' : 'Saved';
  String get allMembers => isZh ? '全部成员' : 'All members';
  String get allDevices => isZh ? '全部设备' : 'All devices';
  String get member => isZh ? '成员' : 'Member';
  String get device => isZh ? '设备' : 'Device';
  String get changeMember => isZh ? '更改成员' : 'Change member';
  String get recordDetail => isZh ? '记录详情' : 'Record';
  String get deleteRecord => isZh ? '删除这条记录？' : 'Delete this record?';
  String get clearAll => isZh ? '清空全部记录' : 'Clear all records';
  String get clearAllConfirm =>
      isZh ? '将删除所有成员的记录，无法恢复。' : 'All records will be deleted. This cannot be undone.';
  String get noDeviceTag => isZh ? '未标记设备' : 'No device';

  String bmiCategory(double bmi) {
    if (bmi < 18.5) return isZh ? '偏瘦' : 'Underweight';
    if (bmi < 25) return isZh ? '正常' : 'Normal';
    if (bmi < 30) return isZh ? '超重' : 'Overweight';
    return isZh ? '肥胖' : 'Obese';
  }

  // --- devices page
  String get devicesEmpty => isZh
      ? '还没有发现过设备。到「测量」页扫描，秤广播一次就会记录在这里。'
      : 'No devices yet. Scan from the Measure tab — each scale is recorded the first time it advertises.';
  String get deviceId => isZh ? '设备 ID' : 'Device ID';
  String get lastSeen => isZh ? '最近发现' : 'Last seen';
  String get rename => isZh ? '重命名' : 'Rename';
  String get remove => isZh ? '移除' : 'Remove';
  String get deviceName => isZh ? '设备名称' : 'Device name';
  String get deviceRecords => isZh ? '记录数' : 'Records';
  String get renameDevice => isZh ? '重命名设备' : 'Rename device';
  String get removeDevice => isZh ? '移除这个设备？' : 'Remove this device?';
  String get removeDeviceHint => isZh
      ? '只从列表移除，已有记录会保留（显示为设备 ID）。'
      : 'Removes it from the list only; existing records are kept.';

  // --- settings page
  String get members => isZh ? '成员' : 'Members';
  String get addMember => isZh ? '添加成员' : 'Add member';
  String get renameMember => isZh ? '重命名成员' : 'Rename member';
  String get avatar => isZh ? '头像' : 'Avatar';
  String get avatarLocalOnly => isZh ? '头像与目标仅保存在本机，不参与导入导出' : 'Avatar and goal stay on this device; they are not exported.';
  String get goalWeight => isZh ? '目标体重' : 'Goal Weight';
  String get goalHint => isZh ? '留空表示不设目标' : 'Leave empty for no goal';
  String get goalLine => isZh ? '目标' : 'Goal';
  String get goalDistance => isZh ? '距目标' : 'To Goal';
  String get noGoalSet => isZh ? '未设置' : 'Not set';
  String get goalReached => isZh ? '已达成' : 'Reached';

  // --- data / csv
  String get data => isZh ? '数据' : 'Data';
  String get exportCsv => isZh ? '导出 CSV' : 'Export CSV';
  String get importCsv => isZh ? '导入 CSV' : 'Import CSV';
  String get exported => isZh ? '已导出' : 'Exported';
  String get exportedToTemp => isZh
      ? '已导出到临时目录（目标位置不可写）'
      : 'Exported to a temp folder (target not writable)';
  String get exportFailed => isZh ? '导出失败' : 'Export failed';
  String get importFailed => isZh ? '导入失败' : 'Import failed';
  String importResult(int n) =>
      isZh ? '已导入 $n 条记录' : 'Imported $n record(s)';
  String get csvFormat => 'CSV · UTF-8';
  String get csvHint => isZh
      ? '列：timestamp, device_id, device_name, member_id, member_name, weight_kg'
      : 'Columns: timestamp, device_id, device_name, member_id, member_name, weight_kg';
  String get dataSource => isZh ? '数据源' : 'Data source';
  String get sourceBle => isZh ? 'BLE 广播' : 'BLE advertisement';
  String get memberName => isZh ? '成员名称' : 'Member name';
  String get activeMember => isZh ? '当前成员' : 'Active member';
  String get removeMember => isZh ? '删除这个成员？' : 'Delete this member?';
  String get removeMemberHint => isZh
      ? '该成员的历史记录会转移到第一个成员。'
      : "This member's records move to the first member.";
  String get cantRemoveLast => isZh ? '至少保留一个成员' : 'Keep at least one member';
  String get language => isZh ? '语言' : 'Language';
  String get chinese => isZh ? '中文' : 'Chinese';
  String get english => isZh ? '英文' : 'English';
  String get unit => isZh ? '显示单位' : 'Unit';
  String get height => isZh ? '身高' : 'Height';
  String get heightCm => isZh ? '身高（厘米）' : 'Height (cm)';
  String get darkMode => isZh ? '深色模式' : 'Dark Mode';
  String get invalidNumber => isZh ? '请输入有效数字' : 'Please enter a valid number';
  String get about => isZh ? '关于' : 'About';
  String get aboutBody => isZh
      ? '通过 BLE 广播读取体重，数据仅保存在本机。'
      : 'Reads weight from BLE advertisements. All data stays on this device.';
}
