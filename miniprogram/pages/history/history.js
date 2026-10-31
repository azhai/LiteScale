const app = getApp();
const { strings, bmiCategory } = require('../../utils/i18n');
const units = require('../../utils/protocol');
const store = require('../../utils/store');

const RANGES = [7, 30, 90, 0];

Page({
  data: {
    s: {},
    rangeIndex: 1,
    rangeLabels: [],
    memberChips: [],
    deviceChips: [],
    selMember: '',
    selDevice: '',
    list: [],
    stats: [],
    hasData: false,
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    const lang = app.globalData.lang;
    const unit = app.globalData.unit;
    const s = strings(lang);
    const members = store.getMembers();
    const devices = store.getDevices();

    // Drop a filter whose member / device was deleted meanwhile.
    let selMember = this.data.selMember;
    let selDevice = this.data.selDevice;
    if (selMember && !members.some((m) => m.id === selMember)) selMember = '';
    if (selDevice && !devices.some((d) => d.id === selDevice)) selDevice = '';

    wx.setNavigationBarTitle({ title: s.tabHistory });

    const days = RANGES[this.data.rangeIndex];
    const list = store.filterRecords(store.getRecords(), selMember, selDevice, days);

    this.setData({
      s,
      selMember,
      selDevice,
      rangeLabels: [s.range7, s.range30, s.range90, s.rangeAll],
      memberChips: [{ id: '', name: s.allMembers }]
        .concat(members.map((m) => ({ id: m.id, name: m.name })))
        .map((x) => ({ id: x.id, name: x.name, on: x.id === selMember })),
      deviceChips: [{ id: '', name: s.allDevices }]
        .concat(devices.map((d) => ({ id: d.id, name: d.name || d.id })))
        .map((x) => ({ id: x.id, name: x.name, on: x.id === selDevice })),
      hasData: list.length > 0,
      list: list
        .slice()
        .reverse()
        .map((r, i, arr) => {
          const prev = arr[i + 1];
          const delta = prev ? r.kg - prev.kg : null;
          return {
            t: r.t,
            timeText: fmtTime(r.t),
            text: units.format(r.kg, unit, lang),
            sub: `${store.memberName(r.m)} · ${r.d ? store.deviceName(r.d) : s.noDeviceTag}`,
            deltaText:
              delta === null
                ? ''
                : `${delta >= 0 ? '+' : '-'}${units.toDisplay(Math.abs(delta), unit).toFixed(1)}`,
            deltaDown: delta !== null && delta <= 0,
          };
        }),
    });

    if (!list.length) {
      this.setData({ stats: [] });
      this.drawChart([]);
      return;
    }

    const values = list.map((r) => r.kg);
    const latest = values[values.length - 1];
    const min = Math.min.apply(null, values);
    const max = Math.max.apply(null, values);
    const avg = values.reduce((a, b) => a + b, 0) / values.length;
    const bodyMember = selMember || store.getActiveMemberId();
    const bmi = store.bmi(latest, store.memberHeight(bodyMember));
    const activeGoal = store.goalFor(bodyMember);
    const goal = activeGoal ? activeGoal.kg : null;

    const fmtDelta = (d) =>
      d === null ? '--' : `${d >= 0 ? '+' : '-'}${units.toDisplay(Math.abs(d), unit).toFixed(1)}`;

    this.setData({
      stats: [
        { label: s.latest, value: units.format(latest, unit, lang) },
        { label: s.minimum, value: units.format(min, unit, lang) },
        { label: s.maximum, value: units.format(max, unit, lang) },
        { label: s.average, value: units.format(avg, unit, lang) },
        { label: s.change7d, value: fmtDelta(store.changeOver(list, 7)) },
        { label: s.change30d, value: fmtDelta(store.changeOver(list, 30)) },
        {
          label: s.bmi,
          value: bmi ? `${bmi.toFixed(1)} · ${bmiCategory(bmi, lang)}` : s.noHeightSet,
        },
        {
          label: s.goalDistance,
          value:
            goal === null
              ? s.noGoalSet
              : latest <= goal
              ? s.goalReached
              : units.format(latest - goal, unit, lang),
        },
        { label: s.recordCount, value: String(list.length) },
      ],
    });

    this.drawChart(list);
  },

  onRange(e) {
    this.setData({ rangeIndex: Number(e.currentTarget.dataset.index) }, () => this.refresh());
  },

  onMemberFilter(e) {
    this.setData({ selMember: e.currentTarget.dataset.id }, () => this.refresh());
  },

  onDeviceFilter(e) {
    this.setData({ selDevice: e.currentTarget.dataset.id }, () => this.refresh());
  },

  onRecordAction(e) {
    const t = Number(e.currentTarget.dataset.t);
    const s = this.data.s;
    wx.showActionSheet({
      itemList: [s.changeMember, s.delete],
      success: (res) => {
        if (res.tapIndex === 0) this.pickMember(t);
        else this.confirmDelete(t);
      },
    });
  },

  pickMember(t) {
    // showActionSheet accepts at most 6 items.
    const members = store.getMembers().slice(0, 6);
    wx.showActionSheet({
      itemList: members.map((m) => m.name),
      success: (res) => {
        const picked = members[res.tapIndex];
        if (!picked) return;
        store.setRecordMember(t, picked.id);
        this.refresh();
      },
    });
  },

  confirmDelete(t) {
    const s = this.data.s;
    wx.showModal({
      title: s.deleteRecord,
      cancelText: s.cancel,
      confirmText: s.delete,
      success: (res) => {
        if (res.confirm) {
          store.removeRecord(t);
          this.refresh();
        }
      },
    });
  },

  drawChart(list) {
    const query = wx.createSelectorQuery();
    query
      .select('#chart')
      .fields({ node: true, size: true })
      .exec((res) => {
        if (!res || !res[0] || !res[0].node) return;
        const canvas = res[0].node;
        const ctx = canvas.getContext('2d');
        const dpr = wx.getWindowInfo ? wx.getWindowInfo().pixelRatio : 2;
        const w = res[0].width;
        const h = res[0].height;
        canvas.width = w * dpr;
        canvas.height = h * dpr;
        ctx.scale(dpr, dpr);
        ctx.clearRect(0, 0, w, h);

        if (list.length === 0) return;

        const unit = app.globalData.unit;
        const points = list.map((r) => ({ x: r.t, y: units.toDisplay(r.kg, unit) }));

        // 7-point moving average, matches the Flutter chart.
        const ma = points.map((p, i) => {
          const from = i - 6 < 0 ? 0 : i - 6;
          let sum = 0;
          for (let j = from; j <= i; j++) sum += points[j].y;
          return { x: p.x, y: sum / (i - from + 1) };
        });

        const padL = 44;
        const padB = 24;
        const padT = 12;
        const padR = 12;
        const minX = points[0].x;
        const maxX = points[points.length - 1].x || minX + 1;
        const ys = points.map((p) => p.y).concat(ma.map((p) => p.y));
        let minY = Math.min.apply(null, ys);
        let maxY = Math.max.apply(null, ys);
        const span = Math.max(maxY - minY, 1);
        minY -= span * 0.15;
        maxY += span * 0.15;

        const px = (p) => padL + ((p.x - minX) / (maxX - minX || 1)) * (w - padL - padR);
        const py = (p) => padT + (1 - (p.y - minY) / (maxY - minY || 1)) * (h - padT - padB);

        // grid
        ctx.strokeStyle = '#eee';
        ctx.lineWidth = 1;
        for (let i = 0; i <= 4; i++) {
          const y = padT + (i * (h - padT - padB)) / 4;
          ctx.beginPath();
          ctx.moveTo(padL, y);
          ctx.lineTo(w - padR, y);
          ctx.stroke();
        }

        // goal line
        const activeGoal = store.goalFor(store.getActiveMemberId());
        const goal = activeGoal ? activeGoal.kg : null;
        if (goal !== null) {
          const gy = py({ y: units.toDisplay(goal, unit) });
          ctx.save();
          ctx.strokeStyle = '#2e9e4f';
          ctx.setLineDash([6, 4]);
          ctx.beginPath();
          ctx.moveTo(padL, gy);
          ctx.lineTo(w - padR, gy);
          ctx.stroke();
          ctx.restore();
        }

        // moving average
        if (ma.length >= 2) {
          ctx.save();
          ctx.strokeStyle = '#e58f2a';
          ctx.lineWidth = 1.5;
          ctx.setLineDash([5, 4]);
          ctx.beginPath();
          ma.forEach((p, i) => {
            if (i === 0) ctx.moveTo(px(p), py(p));
            else ctx.lineTo(px(p), py(p));
          });
          ctx.stroke();
          ctx.restore();
        }

        // line
        ctx.strokeStyle = '#6a4c93';
        ctx.lineWidth = 2;
        ctx.beginPath();
        points.forEach((p, i) => {
          if (i === 0) ctx.moveTo(px(p), py(p));
          else ctx.lineTo(px(p), py(p));
        });
        ctx.stroke();

        // dots
        if (points.length <= 30) {
          ctx.fillStyle = '#6a4c93';
          points.forEach((p) => {
            ctx.beginPath();
            ctx.arc(px(p), py(p), 2.5, 0, Math.PI * 2);
            ctx.fill();
          });
        }

        // y labels
        ctx.fillStyle = '#8a8a8a';
        ctx.font = '10px sans-serif';
        ctx.textAlign = 'right';
        for (let i = 0; i <= 4; i++) {
          const value = maxY - (i * (maxY - minY)) / 4;
          const y = padT + (i * (h - padT - padB)) / 4;
          ctx.fillText(value.toFixed(1), padL - 6, y + 3);
        }

        // x labels (first / last)
        ctx.textAlign = 'left';
        ctx.fillText(fmtDate(minX), padL, h - 6);
        ctx.textAlign = 'right';
        ctx.fillText(fmtDate(maxX), w - padR, h - 6);
      });
  },
});

function pad(n) {
  return n < 10 ? `0${n}` : String(n);
}

function fmtTime(ts) {
  const d = new Date(ts);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}  ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fmtDate(ts) {
  const d = new Date(ts);
  return `${d.getMonth() + 1}/${d.getDate()}`;
}
