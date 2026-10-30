const app = getApp();
const { strings } = require('../../utils/i18n');
const store = require('../../utils/store');

Page({
  data: {
    s: {},
    devices: [],
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const s = strings(app.globalData.lang);
    wx.setNavigationBarTitle({ title: s.tabDevices });

    const counts = {};
    store.getRecords().forEach((r) => {
      if (!r.d) return;
      counts[r.d] = (counts[r.d] || 0) + 1;
    });

    this.setData({
      s,
      devices: store
        .getDevices()
        .slice()
        .sort((a, b) => (b.seen || 0) - (a.seen || 0))
        .map((d) => ({
          id: d.id,
          name: d.name || d.id,
          seenText: fmtTime(d.seen),
          count: counts[d.id] || 0,
        })),
    });
  },

  onDevice(e) {
    const id = e.currentTarget.dataset.id;
    const s = this.data.s;
    wx.showActionSheet({
      itemList: [s.rename, s.remove],
      success: (res) => {
        if (res.tapIndex === 0) this.renameDevice(id);
        else this.removeDevice(id);
      },
    });
  },

  renameDevice(id) {
    const s = this.data.s;
    const current = store.deviceName(id);
    wx.showModal({
      title: s.renameDevice,
      editable: true,
      placeholderText: s.deviceName,
      content: current,
      success: (res) => {
        if (!res.confirm) return;
        store.renameDevice(id, String(res.content || '').trim());
        this.refresh();
      },
    });
  },

  removeDevice(id) {
    const s = this.data.s;
    wx.showModal({
      title: s.removeDevice,
      content: s.removeDeviceHint,
      cancelText: s.cancel,
      confirmText: s.remove,
      success: (res) => {
        if (!res.confirm) return;
        store.removeDevice(id);
        this.refresh();
      },
    });
  },
});

function pad(n) {
  return n < 10 ? `0${n}` : String(n);
}

function fmtTime(ts) {
  if (!ts) return '--';
  const d = new Date(ts);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
