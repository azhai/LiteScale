const app = getApp();
const { strings, bmiCategory } = require('../../utils/i18n');
const { parseAdvertisement, format, label } = require('../../utils/protocol');
const store = require('../../utils/store');

const TARGET_NAME = 'chipsea';
const DEBUG = true;
const SCAN_WINDOW = 30000;

Page({
  data: {
    s: {},
    status: '',
    weightText: '--',
    unitLabel: 'jin',
    locked: false,
    bmiText: '',
    scanning: false,
    debugText: '',
    members: [],
    activeMemberId: '',
    found: [],
  },

  onLoad() {
    this.refreshTexts();
    this.startScan();
  },

  onShow() {
    this.refreshTexts();
    // Scanning was paused when the tab lost focus.
    if (this._wasScanning) this.startScan();
  },

  onHide() {
    this._wasScanning = this.data.scanning;
    this.stopScan();
  },

  onUnload() {
    this.stopScan();
  },

  refreshTexts() {
    const s = strings(app.globalData.lang);
    const activeMemberId = store.getActiveMemberId();
    app.globalData.activeMemberId = activeMemberId;
    wx.setNavigationBarTitle({ title: s.tabMeasure });
    // Re-render the last reading with the current unit / language.
    const patch = {};
    if (typeof this._lastKg === 'number') {
      const unit = app.globalData.unit;
      const text = format(this._lastKg, unit, app.globalData.lang);
      patch.weightText = text.replace(` ${label(unit, app.globalData.lang)}`, '');
      const bmi = store.bmi(this._lastKg, app.globalData.heightCm);
      patch.bmiText = bmi ? `${s.bmi} ${bmi.toFixed(1)} · ${bmiCategory(bmi, app.globalData.lang)}` : '';
    }
    patch.s = s;
    this.setData(Object.assign({
      unitLabel: label(app.globalData.unit, app.globalData.lang),
      activeMemberId,
      members: store.getMembers().map((m) => ({
        id: m.id,
        name: m.name,
        avatar: m.avatar || '🙂',
        active: m.id === activeMemberId,
      })),
      status: this.data.status || s.ready,
    }, patch));
  },

  onMember(e) {
    const id = e.currentTarget.dataset.id;
    store.setActiveMemberId(id);
    app.globalData.activeMemberId = id;
    this.refreshTexts();
    wx.showToast({ title: store.memberName(id), icon: 'none' });
  },

  startScan() {
    if (this.data.scanning) return;
    const s = this.data.s;
    this.setData({ scanning: true, status: s.scanning });

    wx.openBluetoothAdapter({
      success: () => {
        if (!this._listener) {
          this._listener = this.onDeviceFound.bind(this);
          wx.onBluetoothDeviceFound(this._listener);
        }
        wx.startBluetoothDevicesDiscovery({
          allowDuplicatesKey: true,
          interval: 0,
          fail: (err) => {
            this.setData({
              scanning: false,
              status: `${s.scanFailed}: ${err.errMsg || err.errCode}`,
            });
          },
        });
        this.scheduleRestart();
      },
      fail: (err) => {
        this.setData({
          scanning: false,
          status: `${s.btOff} (${err.errMsg || err.errCode})`,
        });
      },
    });
  },

  // The scale only advertises for ~30s after you step on it, so the discovery
  // is recycled instead of running forever.
  scheduleRestart() {
    clearTimeout(this._timer);
    this._timer = setTimeout(() => this.restartDiscovery(), SCAN_WINDOW);
  },

  restartDiscovery() {
    if (!this.data.scanning) return;
    wx.stopBluetoothDevicesDiscovery({
      complete: () => {
        wx.startBluetoothDevicesDiscovery({ allowDuplicatesKey: true, interval: 0 });
        this.scheduleRestart();
      },
    });
  },

  stopScan() {
    clearTimeout(this._timer);
    if (this.data.scanning) wx.stopBluetoothDevicesDiscovery();
    this.setData({ scanning: false });
  },

  toggle() {
    if (this.data.scanning) {
      this.stopScan();
      this.setData({ status: this.data.s.ready });
    } else {
      this.startScan();
    }
  },

  onDeviceFound(res) {
    const devices = (res && res.devices) || [];
    const s = this.data.s;
    let found = this.data.found;
    let changed = false;

    for (let i = 0; i < devices.length; i++) {
      const d = devices[i];
      const name = d.name || d.localName || '';
      const id = d.deviceId;
      const reading = parseAdvertisement(d.advertisData);
      const nameMatch = String(name).toLowerCase().indexOf(TARGET_NAME) >= 0;

      const index = found.findIndex((x) => x.id === id);
      if (index >= 0) {
        found[index] = {
          id,
          name: name || found[index].name,
          rssi: d.RSSI || 0,
          ok: !!reading,
        };
        changed = true;
      } else if (reading || nameMatch) {
        found = found.concat([{ id, name, rssi: d.RSSI || 0, ok: !!reading }]);
        changed = true;
      }

      if (DEBUG) {
        const bytes = d.advertisData ? Array.from(new Uint8Array(d.advertisData)) : [];
        this.setData({
          debugText: `name=${name}\nid=${id}\nrssi=${d.RSSI}\nadv=[${bytes.join(',')}]`,
        });
      }

      if (!reading) {
        if (nameMatch) this.setData({ status: s.noPayload });
        continue;
      }

      store.rememberDevice(id, name);
      this.applyReading(reading, id);
      break;
    }

    if (changed) this.setData({ found: found.slice(0, 8) });
  },

  applyReading(reading, deviceId) {
    const s = this.data.s;
    const lang = app.globalData.lang;
    const unit = app.globalData.unit;
    const value = format(reading.kg, unit, lang);
    const bmi = store.bmi(reading.kg, app.globalData.heightCm);
    this._lastKg = reading.kg;

    this.setData({
      status: reading.locked ? s.locked : s.measuring,
      weightText: value.replace(` ${label(unit, lang)}`, ''),
      locked: !!reading.locked,
      bmiText: bmi ? `${s.bmi} ${bmi.toFixed(1)} · ${bmiCategory(bmi, lang)}` : '',
    });

    if (reading.locked) {
      const memberId = store.getActiveMemberId();
      if (store.addRecord(reading.kg, memberId, deviceId)) {
        wx.showToast({ title: s.savedToHistory, icon: 'none' });
      }
    }
  },
});
