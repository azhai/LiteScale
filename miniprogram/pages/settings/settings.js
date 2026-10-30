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
    goal: '',
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
    const goal = app.globalData.goalKg;

    wx.setNavigationBarTitle({ title: s.tabSettings });

    this.setData({
      s,
      lang,
      unit,
      unitLabel: units.label(unit, lang),
      height: String(app.globalData.heightCm || ''),
      goal: typeof goal === 'number' ? units.toDisplay(goal, unit).toFixed(1) : '',
      langs: [
        { key: 'zh', name: s.chinese },
        { key: 'en', name: s.english },
      ],
      activeMemberId,
      members: store.getMembers().map((m) => ({
        id: m.id,
        name: m.name,
        avatar: m.avatar || '🙂',
        color: m.color || 0,
        active: m.id === activeMemberId,
      })),
      recordCount: store.getRecords().length,
    });
  },

  // --- members -------------------------------------------------------------

  onMember(e) {
    const id = e.currentTarget.dataset.id;
    const s = this.data.s;
    wx.showActionSheet({
      itemList: [s.setActive, s.renameMember, s.avatar, s.delete],
      success: (res) => {
        if (res.tapIndex === 0) {
          store.setActiveMemberId(id);
          app.globalData.activeMemberId = id;
          this.refresh();
        } else if (res.tapIndex === 1) {
          this.renameMember(id);
        } else if (res.tapIndex === 2) {
          this.pickAvatar(id);
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

  pickAvatar(id) {
    // showActionSheet accepts at most 6 items.
    const avatars = store.AVATARS.slice(0, 6);
    wx.showActionSheet({
      itemList: avatars,
      success: (res) => {
        store.setMemberAvatar(id, avatars[res.tapIndex]);
        this.refresh();
      },
    });
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
        const added = store.importRecords(parsed.records);
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
    this.setData({ height: e.detail.value });
  },

  onGoal(e) {
    this.setData({ goal: e.detail.value });
  },

  onSave() {
    const s = this.data.s;
    const height = Number(this.data.height);
    if (!height || height <= 0) {
      wx.showToast({ title: s.invalidNumber, icon: 'none' });
      return;
    }

    let goalKg = null;
    const raw = String(this.data.goal).trim();
    if (raw) {
      const value = Number(raw);
      if (!value || value <= 0) {
        wx.showToast({ title: s.invalidNumber, icon: 'none' });
        return;
      }
      goalKg = units.fromDisplay(value, app.globalData.unit);
    }

    app.globalData.heightCm = height;
    app.globalData.goalKg = goalKg;
    // Goal + avatar are local-only, they never reach the CSV.
    store.saveSettings({
      heightCm: height,
      goalKg,
      unit: app.globalData.unit,
      lang: app.globalData.lang,
    });
    wx.showToast({ title: s.saved, icon: 'none' });
    this.refresh();
  },
});

function pad(n) {
  return n < 10 ? `0${n}` : String(n);
}
