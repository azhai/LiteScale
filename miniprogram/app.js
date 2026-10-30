// LiteScale — WeChat Mini Program
const store = require('./utils/store');

App({
  globalData: {
    lang: 'zh',
    unit: 'jin',
    heightCm: 170,
    goalKg: null,
    activeMemberId: store.DEFAULT_MEMBER_ID,
  },

  onLaunch() {
    // Upgrades records written by the single-member version.
    store.migrate();

    const settings = store.getSettings();
    const info = wx.getAppBaseInfo ? wx.getAppBaseInfo() : {};
    const sysLang = String(info.language || 'zh_CN');

    this.globalData.lang = settings.lang || (sysLang.indexOf('zh') === 0 ? 'zh' : 'en');
    this.globalData.unit = settings.unit || 'jin';
    this.globalData.heightCm = settings.heightCm || 170;
    this.globalData.goalKg = typeof settings.goalKg === 'number' ? settings.goalKg : null;

    store.ensureMembers(this.globalData.lang);
    this.globalData.activeMemberId = store.getActiveMemberId();

    this.applyTabBar();
  },

  setLang(lang) {
    this.globalData.lang = lang;
    store.saveSettings({ lang });
    this.applyTabBar();
  },

  applyTabBar() {
    const i18n = require('./utils/i18n');
    const s = i18n.strings(this.globalData.lang);
    const items = [s.tabMeasure, s.tabHistory, s.tabDevices, s.tabSettings];
    const paths = [
      'pages/index/index',
      'pages/history/history',
      'pages/devices/devices',
      'pages/settings/settings',
    ];
    items.forEach((text, i) => {
      wx.setTabBarItem({ index: i, text, pagePath: paths[i] });
    });
  },
});
