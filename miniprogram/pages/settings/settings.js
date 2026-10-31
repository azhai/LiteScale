const app = getApp();
const { strings, importResult } = require('../../utils/i18n');
const units = require('../../utils/protocol');
const csv = require('../../utils/csv');
const store = require('../../utils/store');

Page({
  data: {
    s: {},
    langs: [],
    lang: 'zh',
    unitList: units.UNITS,
    unit: 'jin',
    unitLabel: 'jin',
    height: '',
    bodyDirty: false,
    gender: '',
    genderOptions: [],
    genderIndex: 0,
    birth: '',
    birthValue: '1990-01',
    todayMonth: '',
    goals: [],
    goalDate: '',
    goalTarget: '',
    avatars: store.AVATARS.map((id) => ({ id, src: store.avatarPath(id) })),
    activeAvatar: '',
    activeMemberName: '',
    members: [],
    activeMemberId: '',
    recordCount: 0,
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const lang = app.globalData.lang;
    const s = strings(lang);
    const unit = app.globalData.unit;
    const activeMemberId = store.getActiveMemberId();
    const activeMember = store.memberById(activeMemberId);
    const height = store.memberHeight(activeMemberId);
    const goals = store.memberGoals(activeMemberId).map((g) => {
      const actual = store.goalActual(activeMemberId, g.date);
      return {
        date: g.date,
        targetText: units.format(g.kg, unit, lang),
        actualText: actual === null ? '—' : units.format(actual, unit, lang),
        reached: actual !== null && actual <= g.kg,
      };
    });

    wx.setNavigationBarTitle({ title: s.tabSettings });

    // Avatar/goal edits refresh the page; keep unsaved body fields for the same
    // member instead of overwriting what the user typed.
    const keepBody = this.data.bodyDirty && this.data.activeMemberId === activeMemberId;
    const genderOptions = [
      { value: '', name: s.genderUnset },
      { value: 'female', name: s.female },
      { value: 'male', name: s.male },
    ];
    const birth = activeMember.birth || '';
    this.setData({
      s,
      lang,
      unit,
      unitLabel: units.label(unit, lang),
      height: keepBody ? this.data.height : height === null ? '' : String(height),
      bodyDirty: keepBody,
      genderOptions,
      genderIndex: Math.max(0, genderOptions.findIndex((o) => o.value === (keepBody ? this.data.gender : activeMember.gender || ''))),
      gender: keepBody ? this.data.gender : activeMember.gender || '',
      birth: keepBody ? this.data.birth : birth,
      birthValue: keepBody && this.data.birth ? this.data.birth : birth || '1990-01',
      todayMonth: store.dayKey(Date.now()).slice(0, 7),
      goals,
      goalDate: this.data.goalDate || store.dayKey(Date.now()),
      avatars: store.AVATARS.map((id) => ({ id, src: store.avatarPath(id) })),
      activeAvatar: store.normalizeAvatar(activeMember.avatar, activeMember.id),
      activeMemberName: activeMember.name,
      langs: [
        { key: 'zh', name: s.chinese },
        { key: 'en', name: s.english },
      ],
      activeMemberId,
      members: store.getMembers().map((m) => {
        const tags = [];
        if (m.id === activeMemberId) tags.push(s.activeMember);
        if (m.gender === 'female' || m.gender === 'male') tags.push(m.gender === 'female' ? s.female : s.male);
        if (m.birth) tags.push(m.birth);
        return {
          id: m.id,
          name: m.name,
          avatarSrc: store.avatarPath(m.avatar, m.id),
          color: m.color || 0,
          active: m.id === activeMemberId,
          note: tags.join(' · '),
        };
      }),
      recordCount: store.getRecords().length,
    });
  },

  // --- members -------------------------------------------------------------

  onMember(e) {
    const id = e.currentTarget.dataset.id;
    const s = this.data.s;
    wx.showActionSheet({
      itemList: [s.setActive, s.renameMember, s.delete],
      success: (res) => {
        if (res.tapIndex === 0) {
          store.setActiveMemberId(id);
          app.globalData.activeMemberId = id;
          this.refresh();
        } else if (res.tapIndex === 1) {
          this.renameMember(id);
        } else {
          this.removeMember(id);
        }
      },
    });
  },

  addMember() {
    const s = this.data.s;
    wx.showModal({
      title: s.addMember,
      editable: true,
      placeholderText: s.memberName,
      cancelText: s.cancel,
      confirmText: s.save,
      success: (res) => {
        if (!res.confirm) return;
        const name = String(res.content || '').trim();
        if (!name) return;
        const created = store.addMember(name);
        store.setActiveMemberId(created.id);
        app.globalData.activeMemberId = created.id;
        this.refresh();
      },
    });
  },

  renameMember(id) {
    const s = this.data.s;
    wx.showModal({
      title: s.renameMember,
      editable: true,
      placeholderText: s.memberName,
      content: store.memberName(id),
      cancelText: s.cancel,
      confirmText: s.save,
      success: (res) => {
        if (!res.confirm) return;
        store.renameMember(id, res.content);
        this.refresh();
      },
    });
  },

  // The body card shows every avatar: a sheet can only hold 6 items.
  onPickAvatar(e) {
    const avatar = e.currentTarget.dataset.avatar;
    if (!avatar) return;
    store.setMemberAvatar(store.getActiveMemberId(), avatar);
    this.refresh();
  },

  removeMember(id) {
    const s = this.data.s;
    if (store.getMembers().length <= 1) {
      wx.showToast({ title: s.cantRemoveLast, icon: 'none' });
      return;
    }
    wx.showModal({
      title: s.removeMember,
      content: s.removeMemberHint,
      cancelText: s.cancel,
      confirmText: s.delete,
      success: (res) => {
        if (!res.confirm) return;
        store.removeMember(id);
        this.refresh();
      },
    });
  },

  // --- csv -----------------------------------------------------------------

  onExport() {
    const s = this.data.s;
    const records = store.getRecords();
    if (!records.length) {
      wx.showToast({ title: s.exportEmpty, icon: 'none' });
      return;
    }

    const body = csv.build(records);
    // BOM so Excel opens UTF-8 correctly.
    const text = '\ufeff' + body;
    const now = new Date();
    const name = `litescale-${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}.csv`;
    const path = `${wx.env.USER_DATA_PATH}/${name}`;

    try {
      wx.getFileSystemManager().writeFileSync(path, text, 'utf8');
    } catch (e) {
      wx.showToast({ title: `${s.exportFailed}: ${e.errMsg || e}`, icon: 'none' });
      return;
    }

    // The mini program has no "save as" dialog: the file is shared to a chat,
    // and when that is unavailable (devtools) the table is copied instead.
    const fallback = () => {
      wx.showModal({
        title: s.exportFailed,
        content: `${path}\n${s.exportHint}`,
        cancelText: s.cancel,
        confirmText: s.copy,
        success: (res) => {
          if (res.confirm) wx.setClipboardData({ data: body });
        },
      });
    };

    if (!wx.shareFileMessage) {
      fallback();
      return;
    }
    wx.shareFileMessage({
      filePath: path,
      fileName: name,
      success: () => wx.showToast({ title: s.exported, icon: 'none' }),
      fail: fallback,
    });
  },

  onImport() {
    const s = this.data.s;
    wx.chooseMessageFile({
      count: 1,
      type: 'file',
      extension: ['csv'],
      success: (res) => {
        const file = (res.tempFiles || [])[0];
        if (!file || !file.path) return;
        let text = '';
        try {
          text = wx.getFileSystemManager().readFileSync(file.path, 'utf8');
        } catch (e) {
          wx.showToast({ title: s.importFailed, icon: 'none' });
          return;
        }
        const parsed = csv.parse(text);
        const added = store.importRecords(parsed.records, parsed.deviceNames);
        wx.showToast({ title: importResult(added, app.globalData.lang), icon: 'none' });
        this.refresh();
      },
    });
  },

  onClear() {
    const s = this.data.s;
    wx.showModal({
      title: s.clearAll,
      content: s.clearAllConfirm,
      cancelText: s.cancel,
      confirmText: s.delete,
      success: (res) => {
        if (!res.confirm) return;
        store.clearRecords();
        this.refresh();
      },
    });
  },

  // --- settings ------------------------------------------------------------

  onLang(e) {
    app.setLang(e.currentTarget.dataset.key);
    this.refresh();
  },

  onUnit(e) {
    const unit = e.currentTarget.dataset.key;
    app.globalData.unit = unit;
    store.saveSettings({ unit });
    this.refresh();
  },

  onHeight(e) {
    this.setData({ height: e.detail.value, bodyDirty: true });
  },

  onGender(e) {
    const index = Number(e.detail.value) || 0;
    this.setData({
      genderIndex: index,
      gender: this.data.genderOptions[index].value,
      bodyDirty: true,
    });
  },

  onBirth(e) {
    const birth = e.detail.value;
    this.setData({ birth, birthValue: birth, bodyDirty: true });
  },

  onGoalDate(e) {
    this.setData({ goalDate: e.detail.value });
  },

  onGoalTarget(e) {
    this.setData({ goalTarget: e.detail.value });
  },

  onAddGoal() {
    const s = this.data.s;
    const value = Number(String(this.data.goalTarget || '').trim());
    if (!value || value <= 0) {
      wx.showToast({ title: s.invalidNumber, icon: 'none' });
      return;
    }
    store.setMemberGoal(store.getActiveMemberId(), {
      date: this.data.goalDate || store.dayKey(Date.now()),
      kg: units.fromDisplay(value, app.globalData.unit),
    });
    this.setData({ goalTarget: '' });
    wx.showToast({ title: s.saved, icon: 'none' });
    this.refresh();
  },

  onDeleteGoal(e) {
    const date = e.currentTarget.dataset.date;
    if (!date) return;
    const s = this.data.s;
    wx.showModal({
      title: s.delete,
      content: `${s.goals} · ${date}`,
      cancelText: s.cancel,
      confirmText: s.delete,
      success: (res) => {
        if (!res.confirm) return;
        store.removeMemberGoal(store.getActiveMemberId(), date);
        this.refresh();
      },
    });
  },

  onSave() {
    const s = this.data.s;
    const rawHeight = String(this.data.height || '').trim();
    const height = Number(rawHeight);
    if (rawHeight && (!height || height <= 0)) {
      wx.showToast({ title: s.invalidNumber, icon: 'none' });
      return;
    }
    // Body data belongs to the active member; only unit/lang are global.
    const id = store.getActiveMemberId();
    if (rawHeight) store.setMemberHeight(id, height);
    store.setMemberDetails(id, { gender: this.data.gender, birth: this.data.birth });
    store.saveSettings({
      unit: app.globalData.unit,
      lang: app.globalData.lang,
    });
    wx.showToast({ title: s.saved, icon: 'none' });
    this.setData({ bodyDirty: false });
    this.refresh();
  },
});

function pad(n) {
  return n < 10 ? `0${n}` : String(n);
}
