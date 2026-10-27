// =============================================================================
// Not alone 3.0 — 单文件整合版
// -----------------------------------------------------------------------------
// 设计目标：
//   · 现代极简 UI + 可切换字体
//   · 中 / 英 / 日 / 德 / 西 / 法 六语言全链路国际化
//   · 国家与节日解耦：日历只显示当前国家
//   · 树洞：真人双向授权聊天 + AI 树洞（同一窗口切换）
//   · 极端词汇拦截 + CRITICAL 本地日志
//   · 隐藏紧急热线 + 情绪卡片分享
//   · 每日 8/12/16/20 点本机通知，数百条不重复话术
//   · 关于页三连击彩蛋
//
// 单文件内部按“区块”组织，后续可按区块拆分为多文件（见 README）。
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// =============================================================================
// 0. 常量与配置
// =============================================================================

const String kAppVersion = '3.0.0';
const String kDeveloperName = 'ZephyrSeeker';

/// 首页默认壁纸（替换原来的 sunset.jpg）
const String kDefaultWallpaper = 'assets/images/flower_field_en.png';

/// 生日蛋糕图片（替换原来的 CustomPainter 蛋糕）
const String kBirthdayCake = 'assets/images/birthday_cake.png';

/// 可选 App Logo：放了就用图片，没放会自动退回内置渐变图标。
const String kAppLogo = 'assets/images/app_logo.png';

/// 高德天气
const String kAmapKey = 'ef14bbc0e73e99e67fe94e0e5f5ed1d7';
const String kCityCode = '360300';
const double kLat = 24.5130;
const double kLon = 117.6470;

/// 本地 Ollama。真机联调时用 --dart-define=OLLAMA_URL=http://192.168.x.x:11434
const String kOllamaBaseUrl = String.fromEnvironment(
  'OLLAMA_URL',
  defaultValue: 'http://192.168.1.4:11434',
);
const String kOllamaModel = String.fromEnvironment(
  'OLLAMA_MODEL',
  defaultValue: 'qwen3.5:4b',
);

/// 真人匹配服务地址，例如 https://your-domain.com
/// 为空时，真人模式会明确提示“服务未配置”，不再用假人兜底。
/// 启动：flutter run --dart-define=TREE_HOLE_API=https://your-domain.com
const String kTreeHoleApiBase = String.fromEnvironment(
  'TREE_HOLE_API',
  defaultValue: 'http://47.83.136.229:8787',
);

/// 树洞人格：温柔倾听者，简短回复，不答知识题
const String kTreeHoleSystemPrompt = '''
你是一个温柔、治愈的倾听者，名字叫「树洞」。
规则（必须遵守）：
1. 永远先共情，再回应；语气柔和、口语化，像坐在对方身边轻声说话。
2. 每次回复不超过 60 个字，最多两句话，绝不说教、不列清单、不写小作文。
3. 不回答任何知识类、技术类、事实类问题。用户问就温和地带回感受，例如「这个问题我大概帮不上，但我更想知道，你现在心里是什么感觉？」
4. 不诊断、不评判、不给医疗或法律建议。若涉及自伤或危机，温柔地建议对方联系身边信任的人或专业热线。
5. 可以偶尔用「嗯」「我在」这样的短句，但不要滥用表情符号。
6. 不要自称 AI，不要说「作为语言模型」。
7. 用户用英文说话时，用同样温柔的英文回应。
''';

final Random rnd = Random();

// =============================================================================
// 1. 通用工具
// =============================================================================

String two(int v) => v.toString().padLeft(2, '0');

String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime? parseYmd(String input) {
  final raw = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (raw.isEmpty) return null;
  final m =
  RegExp(r'^(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?$').firstMatch(raw);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (y < 1900 || y > 2200) return null;
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, mo, d);
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt;
}

bool isBirthdayToday(String birthday, [DateTime? now]) {
  final b = parseYmd(birthday);
  if (b == null) return false;
  final n = now ?? DateTime.now();
  return b.month == n.month && b.day == n.day;
}

int ageOn(DateTime birth, DateTime now) {
  var age = now.year - birth.year;
  if (now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day)) {
    age--;
  }
  return age;
}

String safeLang(String? code) {
  const supported = {'zh', 'en', 'ja', 'de', 'es', 'fr'};
  return supported.contains(code) ? code! : 'en';
}

const Map<String, List<String>> _weekdayFull = {
  'zh': ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
  'en': [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ],
  'ja': ['月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日', '日曜日'],
  'de': [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag'
  ],
  'es': [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo'
  ],
  'fr': [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche'
  ],
};

const Map<String, List<String>> _weekdayShort = {
  'zh': ['一', '二', '三', '四', '五', '六', '日'],
  'en': ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
  'ja': ['月', '火', '水', '木', '金', '土', '日'],
  'de': ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
  'es': ['L', 'M', 'X', 'J', 'V', 'S', 'D'],
  'fr': ['L', 'M', 'M', 'J', 'V', 'S', 'D'],
};

const Map<String, List<String>> _monthNames = {
  'zh': [
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月'
  ],
  'en': [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ],
  'ja': [
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月'
  ],
  'de': [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember'
  ],
  'es': [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre'
  ],
  'fr': [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre'
  ],
};

String wdFull(int w, String lang) => _weekdayFull[safeLang(lang)]![w - 1];

String wdShort(int w, String lang) => _weekdayShort[safeLang(lang)]![w - 1];

String monthLabel(DateTime d, String lang) {
  final code = safeLang(lang);
  switch (code) {
    case 'zh':
    case 'ja':
      return '${d.year}年${d.month}月';
    case 'es':
      return '${_monthNames[code]![d.month - 1]} de ${d.year}';
    default:
      return '${_monthNames[code]![d.month - 1]} ${d.year}';
  }
}

String bytesLabel(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
}

String descEn(String d) =>
    const {
      '晴': 'Clear',
      '多云': 'Cloudy',
      '阴': 'Overcast',
      '阵雨': 'Showers',
      '雷阵雨': 'Thunderstorm',
      '小雨': 'Light rain',
      '中雨': 'Rain',
      '大雨': 'Heavy rain',
      '暴雨': 'Storm',
      '雨夹雪': 'Sleet',
      '小雪': 'Light snow',
      '中雪': 'Snow',
      '大雪': 'Heavy snow',
      '雾': 'Fog',
      '霾': 'Haze',
      '浮尘': 'Dust',
      '扬沙': 'Sand',
    }[d] ??
        d;

String weatherDesc(String raw, String lang) =>
    safeLang(lang) == 'zh' ? raw : descEn(raw);

String hashText(String input) {
  var h = 0;
  for (final code in input.codeUnits) {
    h = 0x1fffffff & (h * 31 + code);
  }
  return h.toRadixString(16);
}

/// 服务端可能返回空 alias，取首字时统一兜底，避免 substring 越界。
String initialOf(String? value) {
  final text = (value ?? '').trim();
  return text.isEmpty ? 'A' : text.substring(0, 1);
}

// =============================================================================
// 2. 国际化词条（6 语言）
// =============================================================================

const Map<String, Map<String, String>> _strings = {
  'zh': <String, String>{
    'app': 'Not alone',
    'navHome': '首页',
    'navWeather': '天气',
    'navCalendar': '日历',
    'navTree': '树洞',
    'navSettings': '设置',
    'greetNight': '夜深了，早点睡，世界明天再应付',
    'greetMorning': '早上好，今天也会有人偷偷想你',
    'greetNoon': '下午好，记得喝口水',
    'greetEvening': '晚上好，今天辛苦了',
    'tapCalendar': '点击查看日历',
    'tapTime': '再点一下回到时间',
    'weather': '天气',
    'alarm': '闹钟',
    'alarmRinging': '闹钟 · 响铃中',
    'dailyAlarm': '每日提醒',
    'humidity': '湿度',
    'wind': '风',
    'uv': '紫外线',
    'feels': '体感',
    'wUnavailable': '天气暂不可用',
    'wNetwork': '网络异常，请检查连接后重试',
    'wRetry': '重试',
    'wDetail': '天气详情',
    'wCurrent': '实时天气',
    'wHourly': '未来 12 小时',
    'wDaily': '未来几天',
    'wExtras': '逐小时与紫外线来自 Open-Meteo',
    'wSource': '数据来源：高德开放平台',
    'calendarTitle': '日历',
    'holidaysMonth': '本月节日',
    'noHolidays': '本月没有节日',
    'today': '今天',
    'country': '国家',
    'selectCountry': '选择国家',
    'treeTitle': '树洞',
    'treeSub': '匿名 · 双向授权 · 只在这台手机',
    'modeAi': 'AI 树洞',
    'modeHuman': '真人聊天',
    'aiEmpty': '这里只有你和树洞。\n想说什么都可以，我在听。',
    'aiInputHint': '说点什么吧，我在听……',
    'aiTimeout': '我这边有点慢……再等我一下好吗？',
    'aiError': '连接不到树洞',
    'aiErrorHint': '请确认 Ollama 已启动，或稍后重试。',
    'aiThinking': '树洞正在听…',
    'retry': '重试',
    'humanIntro': '找一个同频的人',
    'humanIntroSub': '双方都同意后，才会开启匿名对话。',
    'startMatch': '开始匹配',
    'matching': '正在寻找同频的人…',
    'cancelMatch': '取消匹配',
    'waitingConsent': '对方想认识你',
    'waitingConsentSub': '双方都同意后，聊天才会开启。',
    'connected': '已互相授权',
    'sendRequest': '申请认识（双向授权）',
    'requestSent': '已发送匿名申请，等待对方同意',
    'noReply': '对方还没有回应，也许 ta 也在犹豫',
    'consentTitle': '对方同意了你的申请',
    'consentBody': '「{name}」接受了你的双向授权，你们可以匿名互相倾诉了。',
    'sayHi': '说点什么',
    'peerLeft': '对方已离开这次对话',
    'needServer': '匹配服务尚未配置',
    'needServerSub': '真人匹配需要一台服务器。请查看 README 中的接入说明。',
    'chatEmptyHuman': '你们已经互相授权。\n说点什么吧，ta 在等。',
    'chatInputHuman': '匿名地说点什么…',
    'humanTyping': '对方正在输入…',
    'leaveChat': '结束对话',
    'settingsTitle': '设置',
    'settingsSub': '所有数据保存在本机，卸载即删除',
    'language': '语言',
    'followSystem': '跟随系统',
    'theme': '主题',
    'themeDark': '深色',
    'themeLight': '浅色',
    'themeSystem': '跟随系统',
    'font': '字体',
    'fontSystem': '系统默认',
    'fontSerif': '衬线',
    'fontRounded': '圆润',
    'fontMono': '等宽',
    'changed': '已切换',
    'birthday': '生日',
    'notSet': '未设置',
    'bLocked': '今年已修改过，明年才能再改',
    'edit': '修改',
    'wallpaper': '壁纸',
    'wallpaperDefault': '默认花田壁纸',
    'wallpaperLocal': '来自本地相册',
    'ringtone': '闹钟铃声',
    'ringtoneDefault': '默认 Ring10.wav',
    'ringtoneLocal': '来自本地文件',
    'changeWallpaper': '更换壁纸',
    'changeRingtone': '更换铃声',
    'resetDefault': '恢复默认',
    'clearCache': '清除缓存',
    'cacheCleared': '缓存已清除',
    'cacheSize': '当前占用',
    'privacy': '隐私',
    'privacyBody': '完全匿名 · 无账号 · 数据只保存在本机',
    'about': '关于',
    'aboutSub': 'Not alone 3.0 · 把温柔留给你',
    'careBody': '如果你现实中真的很孤独，我想给你一点温暖。本应用完全匿名，请放心倾诉。',
    'agree': '我同意并进入',
    'bAsk': '告诉我们你的生日',
    'bAskSub': '只在生日当天，我们会送你一块电子蛋糕。',
    'bNote': '生日每年只能修改一次，请填写真实日期。',
    'bFormat': '请输入有效日期，如 1998-6-1 或 1998-06-01',
    'bFuture': '生日不能在未来',
    'bSave': '保存生日',
    'bPick': '选择日期',
    'save': '保存',
    'cancel': '取消',
    'hb': '生日快乐',
    'hbAdult': '恭喜成年',
    'hbSub': '愿新的一岁，你被世界温柔以待。',
    'hbSubAdult': '从今天起，请为自己而活，也请偶尔为自己软弱。',
    'bNth': '今天是你的第 {n} 个生日',
    'cakeBlow': '对着屏幕轻轻吹气，吹灭蜡烛',
    'cakeOut': '愿望会实现的',
    'cakeManual': '吹不动了？点这里吹灭',
    'micOff': '麦克风不可用，点击手动吹灭',
    'ringTitle': '该起床啦',
    'wokeUp': '我醒了',
    'alarmSaved': '闹钟已设置为 {t}',
    'riskTitle': '先停一下，你并不孤单',
    'riskBody': '我们检测到你可能正承受很大的痛苦。请先照顾好自己，和信任的人说说话，或拨打下面的热线。',
    'riskHotline': '紧急心理热线',
    'riskLogged': '本次对话已记录为最高级别安全日志（仅保存在本机）。',
    'riskStay': '我想继续倾诉',
    'emergencyTitle': '紧急心理热线',
    'emergencySub': '如果此刻很难撑住，请立刻联系他们。',
    'emergencyCall': '拨打',
    'emergencyClose': '收起',
    'emergencyCopied': '号码已复制',
    'moodTitle': '情绪卡片',
    'moodSub': '把此刻的心情，做成一张可以分享的卡片。',
    'moodPlaceholder': '写下一句此刻想说的话…',
    'moodShare': '生成并分享',
    'moodSaved': '卡片已生成',
    'shareText': '来自 Not alone 的一句话',
    'notifyTitle': '每日鼓励',
    'notifySub': '每天 8:00 / 12:00 / 16:00 / 20:00，给你一句不一样的话。',
    'notifOn': '已开启',
    'notifOff': '已关闭',
    'notifyPermission': '通知权限未开启，请在系统设置中允许通知。',
    'notifyHint': '通知由本机定时发送，不需要联网。',
    'onboardingTitle': '欢迎来到 Not alone',
    'onboardingSub': '先选择你的语言和国家，我们会为你准备对应的节日与问候。',
    'onboardingLang': '选择语言',
    'onboardingCountry': '选择国家',
    'onboardingStart': '开始使用',
    'onboardingNote': '国家决定日历里显示的节日，语言可以随时在设置里改。',
    'developer': '开发者',
    'devMottoTitle': '开发者座右铭',
    'devSecretTitle': '彩蛋三 · 留白',
    'devSecretHint':
    '这个位置留给开发者自己填写。\n在 main.dart 的 DeveloperSecretSlot 中写下你的代码。',
    'devName': 'ZephyrSeeker',
    'mottoCurrent': '当前语言',
    'allLanguages': '全部语言',
    'eggLocked': '再连续点击三次，解锁下一个彩蛋',
    'eggUnlocked': '彩蛋已解锁',
    'version': '版本',
    'ok': '好',
  },
  'en': <String, String>{
    'app': 'Not alone',
    'navHome': 'Home',
    'navWeather': 'Weather',
    'navCalendar': 'Calendar',
    'navTree': 'Hollow',
    'navSettings': 'Settings',
    'greetNight': 'Late night. Rest now; the world can wait until tomorrow.',
    'greetMorning': 'Good morning. Someone is quietly thinking of you.',
    'greetNoon': 'Good afternoon. Remember to drink some water.',
    'greetEvening': 'Good evening. You made it through today.',
    'tapCalendar': 'Tap for the calendar',
    'tapTime': 'Tap again for the clock',
    'weather': 'Weather',
    'alarm': 'Alarm',
    'alarmRinging': 'Alarm · ringing',
    'dailyAlarm': 'Every day',
    'humidity': 'Humidity',
    'wind': 'Wind',
    'uv': 'UV index',
    'feels': 'Feels like',
    'wUnavailable': 'Weather unavailable',
    'wNetwork': 'Network error. Please check your connection.',
    'wRetry': 'Retry',
    'wDetail': 'Weather details',
    'wCurrent': 'Right now',
    'wHourly': 'Next 12 hours',
    'wDaily': 'Next days',
    'wExtras': 'Hourly & UV from Open-Meteo',
    'wSource': 'Source: Amap Open Platform',
    'calendarTitle': 'Calendar',
    'holidaysMonth': 'Holidays this month',
    'noHolidays': 'No holidays this month',
    'today': 'Today',
    'country': 'Country',
    'selectCountry': 'Select a country',
    'treeTitle': 'Hollow',
    'treeSub': 'Anonymous · mutual consent · on this device',
    'modeAi': 'AI Hollow',
    'modeHuman': 'Real chat',
    'aiEmpty': 'Just you and the hollow.\nSay anything. I am listening.',
    'aiInputHint': 'Say something. I am listening…',
    'aiTimeout': 'A little slow… give me a moment?',
    'aiError': "Can't reach the hollow",
    'aiErrorHint': 'Make sure Ollama is running, then retry.',
    'aiThinking': 'The hollow is listening…',
    'retry': 'Retry',
    'humanIntro': 'Find someone on your wavelength',
    'humanIntroSub': 'An anonymous chat starts only after both of you agree.',
    'startMatch': 'Start matching',
    'matching': 'Looking for someone like you…',
    'cancelMatch': 'Cancel',
    'waitingConsent': 'Someone would like to meet you',
    'waitingConsentSub': 'The chat opens only when both sides agree.',
    'connected': 'Mutually approved',
    'sendRequest': 'Ask to connect (mutual consent)',
    'requestSent': 'Anonymous request sent. Waiting for them.',
    'noReply': 'No reply yet. Maybe they are hesitating too.',
    'consentTitle': 'They accepted your request',
    'consentBody':
    '“{name}” accepted the mutual consent. You can now talk anonymously.',
    'sayHi': 'Say something',
    'peerLeft': 'The other person left this chat',
    'needServer': 'Matching service is not configured',
    'needServerSub':
    'Real-person matching needs a server. See the README for setup.',
    'chatEmptyHuman':
    'You have both consented.\nSay something — they are waiting.',
    'chatInputHuman': 'Say something anonymously…',
    'humanTyping': 'They are typing…',
    'leaveChat': 'End chat',
    'settingsTitle': 'Settings',
    'settingsSub': 'Everything stays on this device',
    'language': 'Language',
    'followSystem': 'System',
    'theme': 'Theme',
    'themeDark': 'Dark',
    'themeLight': 'Light',
    'themeSystem': 'System',
    'font': 'Font',
    'fontSystem': 'System default',
    'fontSerif': 'Serif',
    'fontRounded': 'Rounded',
    'fontMono': 'Monospace',
    'changed': 'Updated',
    'birthday': 'Birthday',
    'notSet': 'Not set',
    'bLocked': 'Changed this year. Try next year.',
    'edit': 'Edit',
    'wallpaper': 'Wallpaper',
    'wallpaperDefault': 'Default flower field',
    'wallpaperLocal': 'From your device',
    'ringtone': 'Ringtone',
    'ringtoneDefault': 'Default Ring10.wav',
    'ringtoneLocal': 'From your device',
    'changeWallpaper': 'Change wallpaper',
    'changeRingtone': 'Change ringtone',
    'resetDefault': 'Reset',
    'clearCache': 'Clear cache',
    'cacheCleared': 'Cache cleared',
    'cacheSize': 'In use',
    'privacy': 'Privacy',
    'privacyBody': 'Fully anonymous · no account · stored only on this device',
    'about': 'About',
    'aboutSub': 'Not alone 3.0 · a little gentleness for you',
    'careBody':
    'If you are truly lonely out there, I want to give you a little warmth. This app is fully anonymous.',
    'agree': 'I agree and enter',
    'bAsk': 'Tell us your birthday',
    'bAskSub': 'On your birthday only, we will bake you a digital cake.',
    'bNote': 'The birthday can be changed once a year.',
    'bFormat': 'Enter a valid date, e.g. 1998-6-1',
    'bFuture': 'The birthday cannot be in the future',
    'bSave': 'Save birthday',
    'bPick': 'Pick a date',
    'save': 'Save',
    'cancel': 'Cancel',
    'hb': 'Happy birthday',
    'hbAdult': 'Happy adulthood',
    'hbSub': 'May the world be gentle with you this year.',
    'hbSubAdult': 'From today on, live for yourself. Be soft sometimes.',
    'bNth': 'This is birthday #{n}',
    'cakeBlow': 'Blow gently at the screen to put out the candles',
    'cakeOut': 'Your wish will come true',
    'cakeManual': 'Too tired to blow? Tap to put them out',
    'micOff': 'Microphone unavailable. Tap to put them out',
    'ringTitle': 'Time to wake up',
    'wokeUp': "I'm up",
    'alarmSaved': 'Alarm set for {t}',
    'riskTitle': 'Pause for a moment. You are not alone',
    'riskBody':
    'We noticed you may be carrying a lot of pain. Please take care of yourself, talk to someone you trust, or call a hotline below.',
    'riskHotline': 'Crisis hotlines',
    'riskLogged':
    'This conversation was recorded as a CRITICAL safety log (stored only on this device).',
    'riskStay': 'I want to keep talking',
    'emergencyTitle': 'Crisis hotlines',
    'emergencySub':
    'If you cannot hold on right now, please reach out immediately.',
    'emergencyCall': 'Call',
    'emergencyClose': 'Hide',
    'emergencyCopied': 'Number copied',
    'moodTitle': 'Mood card',
    'moodSub': 'Turn this moment into a card you can share.',
    'moodPlaceholder': 'Write one line about how you feel…',
    'moodShare': 'Create and share',
    'moodSaved': 'Card created',
    'shareText': 'A line from Not alone',
    'notifyTitle': 'Daily encouragement',
    'notifySub': 'A different line every day at 8:00 / 12:00 / 16:00 / 20:00.',
    'notifOn': 'On',
    'notifOff': 'Off',
    'notifyPermission':
    'Notifications are not allowed. Please enable them in system settings.',
    'notifyHint': 'Notifications are scheduled locally. No internet needed.',
    'onboardingTitle': 'Welcome to Not alone',
    'onboardingSub':
    'Choose your language and country first. We will prepare the right holidays and greetings.',
    'onboardingLang': 'Choose a language',
    'onboardingCountry': 'Choose a country',
    'onboardingStart': 'Get started',
    'onboardingNote':
    'The country controls calendar holidays. You can change the language anytime.',
    'developer': 'Developer',
    'devMottoTitle': "Developer's motto",
    'devSecretTitle': 'Easter egg 3 · blank space',
    'devSecretHint':
    'This spot is reserved for the developer.\nWrite your code in DeveloperSecretSlot inside main.dart.',
    'devName': 'ZephyrSeeker',
    'mottoCurrent': 'Current language',
    'allLanguages': 'All languages',
    'eggLocked': 'Tap three more times to unlock the next egg',
    'eggUnlocked': 'Easter egg unlocked',
    'version': 'Version',
    'ok': 'OK',
  },
  'ja': <String, String>{
    'app': 'Not alone',
    'navHome': 'ホーム',
    'navWeather': '天気',
    'navCalendar': 'カレンダー',
    'navTree': '樹洞',
    'navSettings': '設定',
    'greetNight': '夜更けです。早めに休んで、世界のことは明日に。',
    'greetMorning': 'おはよう。今日もどこかで、あなたを想う人がいます。',
    'greetNoon': 'こんにちは。お水を一杯どうぞ。',
    'greetEvening': 'こんばんは。今日もお疲れさまでした。',
    'tapCalendar': 'タップでカレンダー',
    'tapTime': 'もう一度タップで時計',
    'weather': '天気',
    'alarm': '目覚まし',
    'alarmRinging': '目覚まし · 鳴っています',
    'dailyAlarm': '毎日',
    'humidity': '湿度',
    'wind': '風',
    'uv': '紫外線',
    'feels': '体感',
    'wUnavailable': '天気を取得できません',
    'wNetwork': '通信エラーです。接続を確認してください。',
    'wRetry': '再試行',
    'wDetail': '天気の詳細',
    'wCurrent': '現在の天気',
    'wHourly': 'これから12時間',
    'wDaily': 'これからの日々',
    'wExtras': '時間別と紫外線は Open-Meteo より',
    'wSource': 'データ提供：高徳開放平台',
    'calendarTitle': 'カレンダー',
    'holidaysMonth': '今月の祝日',
    'noHolidays': '今月の祝日はありません',
    'today': '今日',
    'country': '国',
    'selectCountry': '国を選択',
    'treeTitle': '樹洞',
    'treeSub': '匿名 · 双方の同意 · この端末だけ',
    'modeAi': 'AI 樹洞',
    'modeHuman': 'リアルチャット',
    'aiEmpty': 'ここにはあなたと樹洞だけ。\n何でも話してください。聞いています。',
    'aiInputHint': '何か話してみて…聞いています。',
    'aiTimeout': '少し遅れています…もう少し待ってくれますか？',
    'aiError': '樹洞に接続できません',
    'aiErrorHint': 'Ollama が起動しているか確認してください。',
    'aiThinking': '樹洞が聞いています…',
    'retry': '再試行',
    'humanIntro': '同じ気持ちの人を探す',
    'humanIntroSub': 'お互いが同意したときだけ、匿名の会話が始まります。',
    'startMatch': 'マッチング開始',
    'matching': '同じ気持ちの人を探しています…',
    'cancelMatch': 'キャンセル',
    'waitingConsent': '相手があなたと話したがっています',
    'waitingConsentSub': '双方が同意するとチャットが始まります。',
    'connected': '相互に同意しました',
    'sendRequest': '知り合う（相互同意）',
    'requestSent': '匿名の申請を送りました。相手の同意を待っています。',
    'noReply': 'まだ返事がありません。相手も迷っているのかもしれません。',
    'consentTitle': '相手が申請を承認しました',
    'consentBody': '「{name}」が相互同意しました。匿名で話せます。',
    'sayHi': '何か話す',
    'peerLeft': '相手はこの会話を離れました',
    'needServer': 'マッチングサービスが未設定です',
    'needServerSub': 'リアルマッチにはサーバーが必要です。README の接続方法を見てください。',
    'chatEmptyHuman': '相互に同意しました。\n何か話してみてください。',
    'chatInputHuman': '匿名で何か話す…',
    'humanTyping': '相手が入力中…',
    'leaveChat': '会話を終了',
    'settingsTitle': '設定',
    'settingsSub': 'データはこの端末に保存されます',
    'language': '言語',
    'followSystem': 'システムに従う',
    'theme': 'テーマ',
    'themeDark': 'ダーク',
    'themeLight': 'ライト',
    'themeSystem': 'システムに従う',
    'font': 'フォント',
    'fontSystem': 'システム標準',
    'fontSerif': 'セリフ',
    'fontRounded': '丸み',
    'fontMono': '等幅',
    'changed': '変更しました',
    'birthday': '誕生日',
    'notSet': '未設定',
    'bLocked': '今年は変更済みです。来年までお待ちください。',
    'edit': '変更',
    'wallpaper': '壁紙',
    'wallpaperDefault': 'デフォルトの花畑',
    'wallpaperLocal': '端末の写真',
    'ringtone': '目覚まし音',
    'ringtoneDefault': 'デフォルト Ring10.wav',
    'ringtoneLocal': '端末のファイル',
    'changeWallpaper': '壁紙を変更',
    'changeRingtone': '音を変更',
    'resetDefault': '初期化',
    'clearCache': 'キャッシュを削除',
    'cacheCleared': 'キャッシュを削除しました',
    'cacheSize': '使用量',
    'privacy': 'プライバシー',
    'privacyBody': '完全匿名 · アカウントなし · 端末内だけ',
    'about': 'について',
    'aboutSub': 'Not alone 3.0 · やさしさをあなたに',
    'careBody': '現実で本当に孤独なら、少しだけ温もりをあげたい。このアプリは完全匿名です。',
    'agree': '同意して始める',
    'bAsk': '誕生日を教えてください',
    'bAskSub': '誕生日当日だけ、電子ケーキを贈ります。',
    'bNote': '誕生日は年に一度だけ変更できます。',
    'bFormat': '有効な日付を入力してください（例：1998-6-1）',
    'bFuture': '未来の日付は選べません',
    'bSave': '誕生日を保存',
    'bPick': '日付を選ぶ',
    'save': '保存',
    'cancel': 'キャンセル',
    'hb': 'お誕生日おめでとう',
    'hbAdult': '成人おめでとう',
    'hbSub': '新しい一年が、やさしさに包まれますように。',
    'hbSubAdult': '今日からは自分のために生きて。たまには弱さも許して。',
    'bNth': '今日はあなたの {n} 回目の誕生日',
    'cakeBlow': '画面に向かってそっと息を吹きかけて',
    'cakeOut': '願いは叶います',
    'cakeManual': '吹けない？ここをタップ',
    'micOff': 'マイクが使えません。タップで消してください',
    'ringTitle': '起きる時間です',
    'wokeUp': '起きた',
    'alarmSaved': '目覚ましを {t} に設定しました',
    'riskTitle': '少し止まって。ひとりじゃない',
    'riskBody': 'つらい状態かもしれないと検知しました。まず自分を大切にしてください。信頼できる人や下の相談窓口に連絡してください。',
    'riskHotline': '緊急相談窓口',
    'riskLogged': 'この会話は最高レベルの安全ログとして記録されました（端末内のみ）。',
    'riskStay': '話を続けたい',
    'emergencyTitle': '緊急心理相談',
    'emergencySub': '今は耐えられないなら、すぐに連絡してください。',
    'emergencyCall': '発信',
    'emergencyClose': '閉じる',
    'emergencyCopied': '番号をコピーしました',
    'moodTitle': '気持ちカード',
    'moodSub': '今の気持ちをシェアできるカードに。',
    'moodPlaceholder': '今の気持ちを一言…',
    'moodShare': '作成して共有',
    'moodSaved': 'カードを作成しました',
    'shareText': 'Not alone から一言',
    'notifyTitle': '毎日の励まし',
    'notifySub': '毎日 8:00 / 12:00 / 16:00 / 20:00 に、違う言葉を届けます。',
    'notifOn': 'オン',
    'notifOff': 'オフ',
    'notifyPermission': '通知が許可されていません。設定から許可してください。',
    'notifyHint': '通知は端末内で予約されます。通信は不要です。',
    'onboardingTitle': 'Not alone へようこそ',
    'onboardingSub': '言語と国を選んでください。祝日と挨拶を用意します。',
    'onboardingLang': '言語を選択',
    'onboardingCountry': '国を選択',
    'onboardingStart': 'はじめる',
    'onboardingNote': '国はカレンダーの祝日を決めます。言語は後で変更できます。',
    'developer': '開発者',
    'devMottoTitle': '開発者の座右の銘',
    'devSecretTitle': 'イースターエッグ 3 · 余白',
    'devSecretHint':
    'ここは開発者が自由に埋める場所です。\nmain.dart の DeveloperSecretSlot にコードを書いてください。',
    'devName': 'ZephyrSeeker',
    'mottoCurrent': '現在の言語',
    'allLanguages': 'すべての言語',
    'eggLocked': 'もう三回連続でタップすると次の彩蛋',
    'eggUnlocked': '彩蛋を解除しました',
    'version': 'バージョン',
    'ok': 'OK',
  },
  'de': <String, String>{
    'app': 'Not alone',
    'navHome': 'Start',
    'navWeather': 'Wetter',
    'navCalendar': 'Kalender',
    'navTree': 'Baumhöhle',
    'navSettings': 'Einstellungen',
    'greetNight': 'Es ist spät. Ruh dich aus, die Welt kann bis morgen warten.',
    'greetMorning': 'Guten Morgen. Jemand denkt gerade leise an dich.',
    'greetNoon': 'Guten Tag. Denk daran, etwas Wasser zu trinken.',
    'greetEvening': 'Guten Abend. Du hast den Tag geschafft.',
    'tapCalendar': 'Tippen für den Kalender',
    'tapTime': 'Nochmal tippen für die Uhr',
    'weather': 'Wetter',
    'alarm': 'Wecker',
    'alarmRinging': 'Wecker · klingelt',
    'dailyAlarm': 'Täglich',
    'humidity': 'Luftfeuchtigkeit',
    'wind': 'Wind',
    'uv': 'UV-Index',
    'feels': 'Gefühlt',
    'wUnavailable': 'Wetter nicht verfügbar',
    'wNetwork': 'Netzwerkfehler. Bitte Verbindung prüfen.',
    'wRetry': 'Erneut',
    'wDetail': 'Wetterdetails',
    'wCurrent': 'Jetzt',
    'wHourly': 'Nächste 12 Stunden',
    'wDaily': 'Nächste Tage',
    'wExtras': 'Stundenwerte & UV von Open-Meteo',
    'wSource': 'Quelle: Amap Open Platform',
    'calendarTitle': 'Kalender',
    'holidaysMonth': 'Feiertage diesen Monat',
    'noHolidays': 'Keine Feiertage diesen Monat',
    'today': 'Heute',
    'country': 'Land',
    'selectCountry': 'Land wählen',
    'treeTitle': 'Baumhöhle',
    'treeSub': 'Anonym · beidseitige Zustimmung · nur auf diesem Gerät',
    'modeAi': 'KI-Baumhöhle',
    'modeHuman': 'Echter Chat',
    'aiEmpty': 'Nur du und die Baumhöhle.\nSag, was du willst. Ich höre zu.',
    'aiInputHint': 'Sag etwas. Ich höre zu…',
    'aiTimeout': 'Etwas langsam… gib mir einen Moment?',
    'aiError': 'Die Baumhöhle ist nicht erreichbar',
    'aiErrorHint': 'Prüfe, ob Ollama läuft, und versuche es erneut.',
    'aiThinking': 'Die Baumhöhle hört zu…',
    'retry': 'Erneut',
    'humanIntro': 'Finde jemanden auf deiner Wellenlänge',
    'humanIntroSub': 'Ein anonymer Chat beginnt erst, wenn beide zustimmen.',
    'startMatch': 'Matching starten',
    'matching': 'Ich suche jemanden wie dich…',
    'cancelMatch': 'Abbrechen',
    'waitingConsent': 'Jemand möchte dich kennenlernen',
    'waitingConsentSub': 'Der Chat öffnet sich erst, wenn beide zustimmen.',
    'connected': 'Beidseitig bestätigt',
    'sendRequest': 'Kennenlernen (beidseitig)',
    'requestSent': 'Anonyme Anfrage gesendet. Warte auf Antwort.',
    'noReply': 'Noch keine Antwort. Vielleicht zögert die andere Person auch.',
    'consentTitle': 'Die andere Person hat zugestimmt',
    'consentBody':
    '„{name}“ hat der beidseitigen Zustimmung zugestimmt. Ihr könnt jetzt anonym sprechen.',
    'sayHi': 'Sag etwas',
    'peerLeft': 'Die andere Person hat den Chat verlassen',
    'needServer': 'Matching-Dienst ist nicht konfiguriert',
    'needServerSub': 'Echtzeit-Matching braucht einen Server. Siehe README.',
    'chatEmptyHuman':
    'Ihr habt beide zugestimmt.\nSag etwas — die andere Person wartet.',
    'chatInputHuman': 'Sag etwas Anonymes…',
    'humanTyping': 'Die andere Person tippt…',
    'leaveChat': 'Chat beenden',
    'settingsTitle': 'Einstellungen',
    'settingsSub': 'Alles bleibt auf diesem Gerät',
    'language': 'Sprache',
    'followSystem': 'System',
    'theme': 'Design',
    'themeDark': 'Dunkel',
    'themeLight': 'Hell',
    'themeSystem': 'System',
    'font': 'Schrift',
    'fontSystem': 'Systemstandard',
    'fontSerif': 'Serif',
    'fontRounded': 'Rund',
    'fontMono': 'Monospace',
    'changed': 'Geändert',
    'birthday': 'Geburtstag',
    'notSet': 'Nicht gesetzt',
    'bLocked': 'Dieses Jahr bereits geändert. Nächstes Jahr wieder.',
    'edit': 'Ändern',
    'wallpaper': 'Hintergrund',
    'wallpaperDefault': 'Standard-Blumenfeld',
    'wallpaperLocal': 'Von deinem Gerät',
    'ringtone': 'Klingelton',
    'ringtoneDefault': 'Standard Ring10.wav',
    'ringtoneLocal': 'Von deinem Gerät',
    'changeWallpaper': 'Hintergrund ändern',
    'changeRingtone': 'Ton ändern',
    'resetDefault': 'Zurücksetzen',
    'clearCache': 'Cache leeren',
    'cacheCleared': 'Cache geleert',
    'cacheSize': 'Belegt',
    'privacy': 'Datenschutz',
    'privacyBody': 'Vollständig anonym · kein Konto · nur lokal gespeichert',
    'about': 'Über',
    'aboutSub': 'Not alone 3.0 · etwas Sanftheit für dich',
    'careBody':
    'Wenn du da draußen wirklich einsam bist, möchte ich dir etwas Wärme geben. Diese App ist völlig anonym.',
    'agree': 'Ich stimme zu',
    'bAsk': 'Sag uns deinen Geburtstag',
    'bAskSub': 'Nur an deinem Geburtstag backen wir dir eine digitale Torte.',
    'bNote': 'Der Geburtstag kann einmal pro Jahr geändert werden.',
    'bFormat': 'Gültiges Datum eingeben, z. B. 1998-6-1',
    'bFuture': 'Der Geburtstag darf nicht in der Zukunft liegen',
    'bSave': 'Geburtstag speichern',
    'bPick': 'Datum wählen',
    'save': 'Speichern',
    'cancel': 'Abbrechen',
    'hb': 'Alles Gute zum Geburtstag',
    'hbAdult': 'Herzlichen Glückwunsch zum Erwachsenwerden',
    'hbSub': 'Möge die Welt in diesem Jahr sanft zu dir sein.',
    'hbSubAdult': 'Lebe ab heute für dich. Sei manchmal auch weich.',
    'bNth': 'Das ist dein {n}. Geburtstag',
    'cakeBlow': 'Puste sanft auf den Bildschirm',
    'cakeOut': 'Dein Wunsch wird wahr',
    'cakeManual': 'Zu müde zum Pusten? Tippe hier',
    'micOff': 'Mikrofon nicht verfügbar. Tippe zum Ausblasen',
    'ringTitle': 'Zeit aufzustehen',
    'wokeUp': 'Ich bin wach',
    'alarmSaved': 'Wecker auf {t} gestellt',
    'riskTitle': 'Halt kurz inne. Du bist nicht allein',
    'riskBody':
    'Wir haben bemerkt, dass du vielleicht großen Schmerz trägst. Bitte sorge für dich, sprich mit jemandem, dem du vertraust, oder rufe unten an.',
    'riskHotline': 'Krisentelefone',
    'riskLogged':
    'Dieses Gespräch wurde als CRITICAL-Sicherheitslog gespeichert (nur lokal).',
    'riskStay': 'Ich möchte weiterreden',
    'emergencyTitle': 'Krisentelefone',
    'emergencySub': 'Wenn du es gerade nicht aushältst, melde dich sofort.',
    'emergencyCall': 'Anrufen',
    'emergencyClose': 'Ausblenden',
    'emergencyCopied': 'Nummer kopiert',
    'moodTitle': 'Stimmungskarte',
    'moodSub': 'Mach aus diesem Moment eine teilbare Karte.',
    'moodPlaceholder': 'Schreibe eine Zeile über dein Gefühl…',
    'moodShare': 'Erstellen und teilen',
    'moodSaved': 'Karte erstellt',
    'shareText': 'Eine Zeile von Not alone',
    'notifyTitle': 'Tägliche Ermutigung',
    'notifySub': 'Jeden Tag um 8:00 / 12:00 / 16:00 / 20:00 ein anderer Satz.',
    'notifOn': 'An',
    'notifOff': 'Aus',
    'notifyPermission':
    'Benachrichtigungen sind nicht erlaubt. Bitte in den Systemeinstellungen aktivieren.',
    'notifyHint':
    'Benachrichtigungen werden lokal geplant. Kein Internet nötig.',
    'onboardingTitle': 'Willkommen bei Not alone',
    'onboardingSub':
    'Wähle zuerst Sprache und Land. Wir bereiten passende Feiertage und Grüße vor.',
    'onboardingLang': 'Sprache wählen',
    'onboardingCountry': 'Land wählen',
    'onboardingStart': 'Loslegen',
    'onboardingNote':
    'Das Land bestimmt die Feiertage. Die Sprache kannst du jederzeit ändern.',
    'developer': 'Entwickler',
    'devMottoTitle': 'Motto des Entwicklers',
    'devSecretTitle': 'Easter Egg 3 · Leerraum',
    'devSecretHint':
    'Dieser Platz ist für den Entwickler reserviert.\nSchreibe deinen Code in DeveloperSecretSlot in main.dart.',
    'devName': 'ZephyrSeeker',
    'mottoCurrent': 'Aktuelle Sprache',
    'allLanguages': 'Alle Sprachen',
    'eggLocked': 'Noch dreimal tippen für das nächste Ei',
    'eggUnlocked': 'Easter Egg freigeschaltet',
    'version': 'Version',
    'ok': 'OK',
  },
  'es': <String, String>{
    'app': 'Not alone',
    'navHome': 'Inicio',
    'navWeather': 'Clima',
    'navCalendar': 'Calendario',
    'navTree': 'Refugio',
    'navSettings': 'Ajustes',
    'greetNight': 'Es tarde. Descansa; el mundo puede esperar a mañana.',
    'greetMorning': 'Buenos días. Alguien está pensando en ti en silencio.',
    'greetNoon': 'Buenas tardes. Recuerda beber agua.',
    'greetEvening': 'Buenas noches. Hoy lo lograste.',
    'tapCalendar': 'Toca para ver el calendario',
    'tapTime': 'Toca otra vez para ver la hora',
    'weather': 'Clima',
    'alarm': 'Alarma',
    'alarmRinging': 'Alarma · sonando',
    'dailyAlarm': 'Cada día',
    'humidity': 'Humedad',
    'wind': 'Viento',
    'uv': 'Índice UV',
    'feels': 'Sensación',
    'wUnavailable': 'Clima no disponible',
    'wNetwork': 'Error de red. Revisa tu conexión.',
    'wRetry': 'Reintentar',
    'wDetail': 'Detalles del clima',
    'wCurrent': 'Ahora',
    'wHourly': 'Próximas 12 horas',
    'wDaily': 'Próximos días',
    'wExtras': 'Horas y UV de Open-Meteo',
    'wSource': 'Fuente: Amap Open Platform',
    'calendarTitle': 'Calendario',
    'holidaysMonth': 'Festivos de este mes',
    'noHolidays': 'No hay festivos este mes',
    'today': 'Hoy',
    'country': 'País',
    'selectCountry': 'Elegir país',
    'treeTitle': 'Refugio',
    'treeSub': 'Anónimo · consentimiento mutuo · solo en este dispositivo',
    'modeAi': 'Refugio IA',
    'modeHuman': 'Chat real',
    'aiEmpty': 'Solo tú y el refugio.\nDi lo que quieras. Te escucho.',
    'aiInputHint': 'Di algo. Te escucho…',
    'aiTimeout': 'Voy un poco lento… ¿me das un momento?',
    'aiError': 'No puedo conectar con el refugio',
    'aiErrorHint': 'Comprueba que Ollama esté en marcha y reintenta.',
    'aiThinking': 'El refugio está escuchando…',
    'retry': 'Reintentar',
    'humanIntro': 'Encuentra a alguien en tu misma onda',
    'humanIntroSub': 'El chat anónimo solo empieza cuando ambos aceptan.',
    'startMatch': 'Empezar a buscar',
    'matching': 'Buscando a alguien como tú…',
    'cancelMatch': 'Cancelar',
    'waitingConsent': 'Alguien quiere conocerte',
    'waitingConsentSub': 'El chat se abre solo cuando ambos aceptan.',
    'connected': 'Consentimiento mutuo',
    'sendRequest': 'Conocer (consentimiento mutuo)',
    'requestSent': 'Solicitud anónima enviada. Esperando respuesta.',
    'noReply': 'Aún no hay respuesta. Quizá también dude.',
    'consentTitle': 'La otra persona aceptó tu solicitud',
    'consentBody':
    '«{name}» aceptó el consentimiento mutuo. Ya pueden hablar en anónimo.',
    'sayHi': 'Di algo',
    'peerLeft': 'La otra persona salió de la conversación',
    'needServer': 'El servicio de emparejamiento no está configurado',
    'needServerSub': 'El chat real necesita un servidor. Consulta el README.',
    'chatEmptyHuman': 'Ambos han aceptado.\nDi algo: te está esperando.',
    'chatInputHuman': 'Di algo de forma anónima…',
    'humanTyping': 'La otra persona está escribiendo…',
    'leaveChat': 'Terminar chat',
    'settingsTitle': 'Ajustes',
    'settingsSub': 'Todo se queda en este dispositivo',
    'language': 'Idioma',
    'followSystem': 'Sistema',
    'theme': 'Tema',
    'themeDark': 'Oscuro',
    'themeLight': 'Claro',
    'themeSystem': 'Sistema',
    'font': 'Fuente',
    'fontSystem': 'Predeterminada',
    'fontSerif': 'Serif',
    'fontRounded': 'Redondeada',
    'fontMono': 'Monoespaciada',
    'changed': 'Cambiado',
    'birthday': 'Cumpleaños',
    'notSet': 'Sin definir',
    'bLocked': 'Ya se cambió este año. Inténtalo el próximo.',
    'edit': 'Editar',
    'wallpaper': 'Fondo',
    'wallpaperDefault': 'Campo de flores predeterminado',
    'wallpaperLocal': 'De tu dispositivo',
    'ringtone': 'Tono',
    'ringtoneDefault': 'Ring10.wav predeterminado',
    'ringtoneLocal': 'De tu dispositivo',
    'changeWallpaper': 'Cambiar fondo',
    'changeRingtone': 'Cambiar tono',
    'resetDefault': 'Restablecer',
    'clearCache': 'Borrar caché',
    'cacheCleared': 'Caché borrada',
    'cacheSize': 'En uso',
    'privacy': 'Privacidad',
    'privacyBody': 'Totalmente anónimo · sin cuenta · solo en este dispositivo',
    'about': 'Acerca de',
    'aboutSub': 'Not alone 3.0 · un poco de ternura para ti',
    'careBody':
    'Si de verdad te sientes solo, quiero darte un poco de calor. Esta app es totalmente anónima.',
    'agree': 'Acepto y entro',
    'bAsk': 'Dinos tu cumpleaños',
    'bAskSub': 'Solo el día de tu cumpleaños te horneamos una tarta digital.',
    'bNote': 'El cumpleaños solo se puede cambiar una vez al año.',
    'bFormat': 'Introduce una fecha válida, p. ej. 1998-6-1',
    'bFuture': 'El cumpleaños no puede estar en el futuro',
    'bSave': 'Guardar cumpleaños',
    'bPick': 'Elegir fecha',
    'save': 'Guardar',
    'cancel': 'Cancelar',
    'hb': 'Feliz cumpleaños',
    'hbAdult': 'Feliz mayoría de edad',
    'hbSub': 'Que el mundo sea amable contigo este año.',
    'hbSubAdult': 'Desde hoy, vive para ti. Permítete ser blando a veces.',
    'bNth': 'Es tu cumpleaños número {n}',
    'cakeBlow': 'Sopla suavemente hacia la pantalla',
    'cakeOut': 'Tu deseo se cumplirá',
    'cakeManual': '¿Cansado de soplar? Toca aquí',
    'micOff': 'Micrófono no disponible. Toca para apagar',
    'ringTitle': 'Hora de despertar',
    'wokeUp': 'Ya me levanté',
    'alarmSaved': 'Alarma ajustada a las {t}',
    'riskTitle': 'Detente un momento. No estás solo',
    'riskBody':
    'Hemos notado que quizá cargas con mucho dolor. Cuídate, habla con alguien de confianza o llama a una línea de abajo.',
    'riskHotline': 'Líneas de crisis',
    'riskLogged':
    'Esta conversación se registró como un log CRITICAL (solo en este dispositivo).',
    'riskStay': 'Quiero seguir hablando',
    'emergencyTitle': 'Líneas de crisis',
    'emergencySub': 'Si ahora no puedes sostenerte, contacta de inmediato.',
    'emergencyCall': 'Llamar',
    'emergencyClose': 'Ocultar',
    'emergencyCopied': 'Número copiado',
    'moodTitle': 'Tarjeta de ánimo',
    'moodSub': 'Convierte este momento en una tarjeta para compartir.',
    'moodPlaceholder': 'Escribe una línea sobre cómo te sientes…',
    'moodShare': 'Crear y compartir',
    'moodSaved': 'Tarjeta creada',
    'shareText': 'Una línea de Not alone',
    'notifyTitle': 'Ánimo diario',
    'notifySub':
    'Una frase distinta cada día a las 8:00 / 12:00 / 16:00 / 20:00.',
    'notifOn': 'Activado',
    'notifOff': 'Desactivado',
    'notifyPermission':
    'Las notificaciones no están permitidas. Actívalas en los ajustes del sistema.',
    'notifyHint':
    'Las notificaciones se programan localmente. No hace falta internet.',
    'onboardingTitle': 'Bienvenido a Not alone',
    'onboardingSub':
    'Elige primero tu idioma y país. Prepararemos los festivos y saludos adecuados.',
    'onboardingLang': 'Elegir idioma',
    'onboardingCountry': 'Elegir país',
    'onboardingStart': 'Empezar',
    'onboardingNote':
    'El país decide los festivos del calendario. Puedes cambiar el idioma cuando quieras.',
    'developer': 'Desarrollador',
    'devMottoTitle': 'Lema del desarrollador',
    'devSecretTitle': 'Huevo de Pascua 3 · espacio en blanco',
    'devSecretHint':
    'Este espacio está reservado para el desarrollador.\nEscribe tu código en DeveloperSecretSlot dentro de main.dart.',
    'devName': 'ZephyrSeeker',
    'mottoCurrent': 'Idioma actual',
    'allLanguages': 'Todos los idiomas',
    'eggLocked': 'Toca tres veces más para el siguiente huevo',
    'eggUnlocked': 'Huevo desbloqueado',
    'version': 'Versión',
    'ok': 'OK',
  },
  'fr': <String, String>{
    'app': 'Not alone',
    'navHome': 'Accueil',
    'navWeather': 'Météo',
    'navCalendar': 'Calendrier',
    'navTree': 'Refuge',
    'navSettings': 'Réglages',
    'greetNight': 'Il est tard. Repose-toi, le monde attendra demain.',
    'greetMorning': 'Bonjour. Quelqu’un pense à toi en silence.',
    'greetNoon': 'Bon après-midi. Pense à boire un peu d’eau.',
    'greetEvening': 'Bonsoir. Tu as tenu bon aujourd’hui.',
    'tapCalendar': 'Touche pour le calendrier',
    'tapTime': 'Touche encore pour l’heure',
    'weather': 'Météo',
    'alarm': 'Réveil',
    'alarmRinging': 'Réveil · sonne',
    'dailyAlarm': 'Chaque jour',
    'humidity': 'Humidité',
    'wind': 'Vent',
    'uv': 'Indice UV',
    'feels': 'Ressenti',
    'wUnavailable': 'Météo indisponible',
    'wNetwork': 'Erreur réseau. Vérifie ta connexion.',
    'wRetry': 'Réessayer',
    'wDetail': 'Détails météo',
    'wCurrent': 'Maintenant',
    'wHourly': 'Prochaines 12 heures',
    'wDaily': 'Prochains jours',
    'wExtras': 'Heures et UV via Open-Meteo',
    'wSource': 'Source : Amap Open Platform',
    'calendarTitle': 'Calendrier',
    'holidaysMonth': 'Jours fériés ce mois-ci',
    'noHolidays': 'Aucun jour férié ce mois-ci',
    'today': 'Aujourd’hui',
    'country': 'Pays',
    'selectCountry': 'Choisir un pays',
    'treeTitle': 'Refuge',
    'treeSub': 'Anonyme · consentement mutuel · sur cet appareil',
    'modeAi': 'Refuge IA',
    'modeHuman': 'Chat réel',
    'aiEmpty': 'Juste toi et le refuge.\nDis ce que tu veux. J’écoute.',
    'aiInputHint': 'Dis quelque chose. J’écoute…',
    'aiTimeout': 'Un peu lent… tu me laisses un instant ?',
    'aiError': 'Impossible de joindre le refuge',
    'aiErrorHint': 'Vérifie qu’Ollama est lancé, puis réessaie.',
    'aiThinking': 'Le refuge écoute…',
    'retry': 'Réessayer',
    'humanIntro': 'Trouve quelqu’un sur la même longueur d’onde',
    'humanIntroSub':
    'Le chat anonyme ne s’ouvre que si vous êtes d’accord tous les deux.',
    'startMatch': 'Lancer la recherche',
    'matching': 'Recherche de quelqu’un comme toi…',
    'cancelMatch': 'Annuler',
    'waitingConsent': 'Quelqu’un aimerait te connaître',
    'waitingConsentSub':
    'Le chat s’ouvre seulement quand vous acceptez tous les deux.',
    'connected': 'Consentement mutuel',
    'sendRequest': 'Faire connaissance (accord mutuel)',
    'requestSent': 'Demande anonyme envoyée. En attente.',
    'noReply': 'Pas encore de réponse. L’autre hésite peut-être aussi.',
    'consentTitle': 'L’autre personne a accepté',
    'consentBody':
    '« {name} » a accepté le consentement mutuel. Vous pouvez parler anonymement.',
    'sayHi': 'Dis quelque chose',
    'peerLeft': 'L’autre personne a quitté la conversation',
    'needServer': 'Le service de mise en relation n’est pas configuré',
    'needServerSub': 'Le chat réel nécessite un serveur. Voir le README.',
    'chatEmptyHuman':
    'Vous avez tous les deux accepté.\nDis quelque chose — l’autre attend.',
    'chatInputHuman': 'Dis quelque chose anonymement…',
    'humanTyping': 'L’autre personne écrit…',
    'leaveChat': 'Terminer le chat',
    'settingsTitle': 'Réglages',
    'settingsSub': 'Tout reste sur cet appareil',
    'language': 'Langue',
    'followSystem': 'Système',
    'theme': 'Thème',
    'themeDark': 'Sombre',
    'themeLight': 'Clair',
    'themeSystem': 'Système',
    'font': 'Police',
    'fontSystem': 'Par défaut',
    'fontSerif': 'Serif',
    'fontRounded': 'Arrondie',
    'fontMono': 'Monospace',
    'changed': 'Modifié',
    'birthday': 'Anniversaire',
    'notSet': 'Non défini',
    'bLocked': 'Déjà modifié cette année. Réessaie l’an prochain.',
    'edit': 'Modifier',
    'wallpaper': 'Fond d’écran',
    'wallpaperDefault': 'Champ de fleurs par défaut',
    'wallpaperLocal': 'Depuis ton appareil',
    'ringtone': 'Sonnerie',
    'ringtoneDefault': 'Ring10.wav par défaut',
    'ringtoneLocal': 'Depuis ton appareil',
    'changeWallpaper': 'Changer le fond',
    'changeRingtone': 'Changer la sonnerie',
    'resetDefault': 'Réinitialiser',
    'clearCache': 'Vider le cache',
    'cacheCleared': 'Cache vidé',
    'cacheSize': 'Utilisé',
    'privacy': 'Confidentialité',
    'privacyBody': 'Totalement anonyme · sans compte · stocké uniquement ici',
    'about': 'À propos',
    'aboutSub': 'Not alone 3.0 · un peu de douceur pour toi',
    'careBody':
    'Si tu te sens vraiment seul, je veux t’offrir un peu de chaleur. Cette app est totalement anonyme.',
    'agree': 'J’accepte et j’entre',
    'bAsk': 'Dis-nous ton anniversaire',
    'bAskSub':
    'Le jour de ton anniversaire seulement, nous te préparons un gâteau numérique.',
    'bNote': 'L’anniversaire ne peut être modifié qu’une fois par an.',
    'bFormat': 'Saisis une date valide, par ex. 1998-6-1',
    'bFuture': 'L’anniversaire ne peut pas être dans le futur',
    'bSave': 'Enregistrer l’anniversaire',
    'bPick': 'Choisir une date',
    'save': 'Enregistrer',
    'cancel': 'Annuler',
    'hb': 'Joyeux anniversaire',
    'hbAdult': 'Joyeux passage à l’âge adulte',
    'hbSub': 'Que le monde soit doux avec toi cette année.',
    'hbSubAdult': 'À partir d’aujourd’hui, vis pour toi. Sois doux parfois.',
    'bNth': 'C’est ton anniversaire n° {n}',
    'cakeBlow': 'Souffle doucement vers l’écran',
    'cakeOut': 'Ton vœu se réalisera',
    'cakeManual': 'Trop fatigué pour souffler ? Touche ici',
    'micOff': 'Micro indisponible. Touche pour éteindre',
    'ringTitle': 'C’est l’heure de se lever',
    'wokeUp': 'Je suis réveillé',
    'alarmSaved': 'Réveil réglé à {t}',
    'riskTitle': 'Arrête-toi un instant. Tu n’es pas seul',
    'riskBody':
    'Nous avons remarqué que tu portes peut-être une grande douleur. Prends soin de toi, parle à quelqu’un de confiance ou appelle une ligne ci-dessous.',
    'riskHotline': 'Lignes de crise',
    'riskLogged':
    'Cette conversation a été enregistrée comme journal CRITICAL (uniquement sur cet appareil).',
    'riskStay': 'Je veux continuer à parler',
    'emergencyTitle': 'Lignes de crise',
    'emergencySub':
    'Si tu ne tiens plus maintenant, contacte-les tout de suite.',
    'emergencyCall': 'Appeler',
    'emergencyClose': 'Masquer',
    'emergencyCopied': 'Numéro copié',
    'moodTitle': 'Carte d’humeur',
    'moodSub': 'Transforme cet instant en carte à partager.',
    'moodPlaceholder': 'Écris une phrase sur ce que tu ressens…',
    'moodShare': 'Créer et partager',
    'moodSaved': 'Carte créée',
    'shareText': 'Une phrase de Not alone',
    'notifyTitle': 'Encouragement quotidien',
    'notifySub':
    'Une phrase différente chaque jour à 8:00 / 12:00 / 16:00 / 20:00.',
    'notifOn': 'Activé',
    'notifOff': 'Désactivé',
    'notifyPermission':
    'Les notifications ne sont pas autorisées. Active-les dans les réglages.',
    'notifyHint':
    'Les notifications sont programmées localement. Pas besoin d’internet.',
    'onboardingTitle': 'Bienvenue dans Not alone',
    'onboardingSub':
    'Choisis d’abord ta langue et ton pays. Nous préparerons les jours fériés et les salutations.',
    'onboardingLang': 'Choisir une langue',
    'onboardingCountry': 'Choisir un pays',
    'onboardingStart': 'Commencer',
    'onboardingNote':
    'Le pays détermine les jours fériés. Tu peux changer la langue à tout moment.',
    'developer': 'Développeur',
    'devMottoTitle': 'Devise du développeur',
    'devSecretTitle': 'Easter egg 3 · espace vide',
    'devSecretHint':
    'Cet espace est réservé au développeur.\nÉcris ton code dans DeveloperSecretSlot dans main.dart.',
    'devName': 'ZephyrSeeker',
    'mottoCurrent': 'Langue actuelle',
    'allLanguages': 'Toutes les langues',
    'eggLocked': 'Encore trois touchers pour l’œuf suivant',
    'eggUnlocked': 'Easter egg débloqué',
    'version': 'Version',
    'ok': 'OK',
  },
};

// =============================================================================
// 3. 国际化入口
// =============================================================================

class L10n {
  const L10n(this.locale);

  final Locale locale;

  String get lang => safeLang(locale.languageCode);

  bool get isZh => lang == 'zh';

  String t(String key, [Map<String, String>? args]) {
    final table = _strings[lang] ?? _strings['en']!;
    var value = table[key] ?? _strings['en']![key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }

  static L10n of(BuildContext context) =>
      Localizations.of<L10n>(context, L10n) ?? const L10n(Locale('en'));

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh'),
    Locale('ja'),
    Locale('de'),
    Locale('es'),
    Locale('fr'),
  ];
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  bool isSupported(Locale locale) => _strings.containsKey(locale.languageCode);

  @override
  Future<L10n> load(Locale locale) => SynchronousFuture<L10n>(L10n(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<L10n> old) => false;
}

extension AppCtx on BuildContext {
  L10n get l10n => L10n.of(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
  String t(String key, [Map<String, String>? args]) =>
      L10n.of(this).t(key, args);
}

// =============================================================================
// 4. 国家与语言
// =============================================================================

class CountryInfo {
  const CountryInfo(this.code, this.flag, this.nativeName, this.lang);

  final String code;
  final String flag;
  final String nativeName;
  final String lang;
}

const List<CountryInfo> kCountries = [
  CountryInfo('CN', '🇨🇳', '中国', 'zh'),
  CountryInfo('US', '🇺🇸', 'United States', 'en'),
  CountryInfo('DE', '🇩🇪', 'Deutschland', 'de'),
  CountryInfo('JP', '🇯🇵', '日本', 'ja'),
  CountryInfo('ES', '🇪🇸', 'España', 'es'),
  CountryInfo('FR', '🇫🇷', 'France', 'fr'),
];

CountryInfo countryByCode(String code) => kCountries.firstWhere(
      (c) => c.code == code,
  orElse: () => kCountries.first,
);

// =============================================================================
// 5. 本地状态
// =============================================================================

class AppStore extends ChangeNotifier {
  AppStore._(this._prefs);

  static late AppStore I;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('anonId') == null) {
      const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final id =
      List.generate(14, (_) => alphabet[rnd.nextInt(alphabet.length)])
          .join();
      await prefs.setString('anonId', 'anon-$id');
    }
    I = AppStore._(prefs);
  }

  final SharedPreferences _prefs;

  // ---------- 语言 ----------
  String get localeCode => _prefs.getString('locale') ?? 'system';

  Locale? get locale =>
      localeCode == 'system' ? null : Locale(safeLang(localeCode));

  /// 给业务层（节日、通知、话术）使用的具体语言代码
  String get langCode {
    if (localeCode != 'system') return safeLang(localeCode);
    final system = ui.PlatformDispatcher.instance.locale.languageCode;
    return safeLang(system);
  }

  Future<void> setLocale(String code) async {
    await _prefs.setString('locale', code);
    notifyListeners();
  }

  // ---------- 国家 ----------
  String get countryCode {
    final code = _prefs.getString('country') ?? 'CN';
    return kCountries.any((c) => c.code == code) ? code : 'CN';
  }

  CountryInfo get country => countryByCode(countryCode);

  Future<void> setCountry(String code) async {
    await _prefs.setString('country', code);
    notifyListeners();
  }

  // ---------- 首次引导 ----------
  bool get onboardingDone => _prefs.getBool('onboardingDone') ?? false;

  Future<void> completeOnboarding(String country, String lang) async {
    await _prefs.setString('country', country);
    await _prefs.setString('locale', lang);
    await _prefs.setBool('onboardingDone', true);
    notifyListeners();
  }

  // ---------- 主题 ----------
  String get themeCode => _prefs.getString('theme') ?? 'dark';

  ThemeMode get themeMode {
    switch (themeCode) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  Future<void> setTheme(String code) async {
    await _prefs.setString('theme', code);
    notifyListeners();
  }

  // ---------- 字体 ----------
  String get fontCode => _prefs.getString('font') ?? 'system';

  AppFont get appFont => AppFont.values.firstWhere(
        (f) => f.name == fontCode,
    orElse: () => AppFont.system,
  );

  Future<void> setFont(String code) async {
    await _prefs.setString('font', code);
    notifyListeners();
  }

  // ---------- 关怀确认 ----------
  bool get careAccepted => _prefs.getBool('careAccepted') ?? false;

  Future<void> acceptCare() async {
    await _prefs.setBool('careAccepted', true);
    notifyListeners();
  }

  // ---------- 闹钟 ----------
  int get alarmHour => _prefs.getInt('alarmHour') ?? 7;
  int get alarmMinute => _prefs.getInt('alarmMinute') ?? 0;

  Future<void> setAlarm(int hour, int minute) async {
    await _prefs.setInt('alarmHour', hour);
    await _prefs.setInt('alarmMinute', minute);
    notifyListeners();
  }

  // ---------- 生日 ----------
  String? get birthday => _prefs.getString('birthday');

  int get birthdayEditYear => _prefs.getInt('birthdayEditYear') ?? 0;

  bool get canEditBirthday =>
      birthday == null || birthdayEditYear < DateTime.now().year;

  Future<void> setBirthday(String value) async {
    await _prefs.setString('birthday', value);
    await _prefs.setInt('birthdayEditYear', DateTime.now().year);
    notifyListeners();
  }

  String? get cakeShownOn => _prefs.getString('cakeShownOn');

  Future<void> markCakeShown() async {
    await _prefs.setString('cakeShownOn', ymd(DateTime.now()));
  }

  // ---------- 壁纸 / 铃声 ----------
  String? get wallpaper => _prefs.getString('wallpaper');
  String? get ringtone => _prefs.getString('ringtone');

  Future<void> setWallpaper(String? path) async {
    if (path == null) {
      await _prefs.remove('wallpaper');
    } else {
      await _prefs.setString('wallpaper', path);
    }
    notifyListeners();
  }

  Future<void> setRingtone(String? path) async {
    if (path == null) {
      await _prefs.remove('ringtone');
    } else {
      await _prefs.setString('ringtone', path);
    }
    notifyListeners();
  }

  // ---------- 通知 ----------
  bool get notificationsEnabled => _prefs.getBool('notifications') ?? true;

  Future<void> setNotifications(bool enabled) async {
    await _prefs.setBool('notifications', enabled);
    notifyListeners();
  }

  // ---------- 彩蛋 ----------
  int get eggStage => _prefs.getInt('eggStage') ?? 0;

  Future<void> setEggStage(int stage) async {
    await _prefs.setInt('eggStage', stage.clamp(0, 3));
    notifyListeners();
  }

  // ---------- 匿名 ID ----------
  String get anonId => _prefs.getString('anonId') ?? 'anon-local';
}

// =============================================================================
// 6. 字体与主题
// =============================================================================

enum AppFont {
  system(null, null),
  serif('serif', ['Noto Serif', 'Songti SC', 'Times New Roman']),
  rounded(
      'sans-serif-rounded', ['Arial Rounded MT Bold', 'Noto Sans', 'Segoe UI']),
  mono('monospace', ['Menlo', 'Courier New', 'Consolas']);

  const AppFont(this.family, this.fallbacks);

  final String? family;
  final List<String>? fallbacks;

  String label(L10n l) => switch (this) {
    AppFont.system => l.t('fontSystem'),
    AppFont.serif => l.t('fontSerif'),
    AppFont.rounded => l.t('fontRounded'),
    AppFont.mono => l.t('fontMono'),
  };
}

class AppTheme {
  const AppTheme._();

  static ThemeData build(Brightness brightness, AppFont font) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8EC5FF),
      brightness: brightness,
    ).copyWith(
      surface: dark ? const Color(0xFF11141C) : const Color(0xFFFFFFFF),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
      dark ? const Color(0xFF090B11) : const Color(0xFFF5F6FA),
      splashFactory: InkSparkle.splashFactory,
    );

    final text = base.textTheme.apply(
      fontFamily: font.family,
      fontFamilyFallback: font.fallbacks,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: font.family,
            fontFamilyFallback: font.fallbacks,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.18)),
          textStyle: TextStyle(
            fontWeight: FontWeight.w500,
            fontFamily: font.family,
            fontFamilyFallback: font.fallbacks,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: 0.05),
        hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.32)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

// =============================================================================
// 7. 每日鼓励话术（按语言 × 时段，共 350+ 条）
// =============================================================================

enum NotifySlot {
  morning(8),
  noon(12),
  afternoon(16),
  evening(20);

  const NotifySlot(this.hour);

  final int hour;
}

class QuoteBank {
  const QuoteBank._();

  static const Map<String, Map<NotifySlot, List<String>>> _pools = {
    'zh': {
      NotifySlot.morning: [
        '早安，今天不用完美，只要真实地活着就好。',
        '新的一天，先给自己倒一杯温水。',
        '醒来的这一刻，你已经比昨天更勇敢了。',
        '慢慢睁眼，世界不着急，你也不用。',
        '今天的光很温柔，记得抬头看看。',
        '你不需要一醒来就充满力量，先呼吸就好。',
        '早安，愿今天的风替你吹散一点疲惫。',
        '如果起床很难，那就先坐一会儿，也没关系。',
        '今天也请把自己放在第一位。',
        '你值得一个不慌不忙的早晨。',
        '早安，今天的你依然值得被好好对待。',
        '先伸个懒腰，再决定今天要做什么。',
        '不用急着证明什么，你已经很好了。',
        '今天的太阳，是为你升起的。',
        '早安，愿你有热饭，也有好心情。',
        '就算昨晚没睡好，今天也可以慢慢来。',
        '你醒来了，这就是一件值得庆祝的事。',
        '今天不必光芒万丈，温暖自己就好。',
        '早安，记得吃早餐，胃和心都需要。',
        '新的一天，允许一切慢慢发生。',
      ],
      NotifySlot.noon: [
        '中午了，先去吃饭，别让工作把你吞掉。',
        '记得喝水，你的身体一直在替你撑着。',
        '午休十分钟，也是一种了不起的自爱。',
        '上午辛苦了，下午可以轻一点。',
        '放下手机，好好吃一口热饭。',
        '你不需要一直高效，休息也是正事。',
        '中午的阳光很好，出去走两步吧。',
        '吃点喜欢的，不必计算那么多。',
        '今天的午饭，愿它温暖你的胃。',
        '停一下，问问自己：累不累？',
        '你已经做了很多，先歇一会儿。',
        '午安，愿你有片刻的安静。',
        '不用和别人比进度，你有自己的节奏。',
        '吃完饭，给自己五分钟发呆的时间。',
        '记得抬头，看看天，世界还很大。',
        '中午了，把紧绷的肩膀放下来。',
        '你值得一顿不被打扰的饭。',
        '上午的难，已经过去了。',
        '午安，愿你下午被温柔以待。',
        '喝水、吃饭、呼吸，今天先做好这三件事。',
      ],
      NotifySlot.afternoon: [
        '下午容易疲惫，给自己泡杯热茶吧。',
        '撑不住的时候，靠一会儿也不是失败。',
        '你已经走了很远，别急着否定自己。',
        '四点啦，起来伸个懒腰，喝口水。',
        '今天的进度不重要，你还在就很好。',
        '如果心里很吵，就闭上眼睛听一次呼吸。',
        '你不必今天解决所有问题。',
        '下午的光开始变软，你也可以。',
        '允许自己慢一点，路不会跑掉。',
        '你已经很努力了，真的。',
        '累了就停，不是每件事都要硬扛。',
        '下午好，愿有一阵风替你松一口气。',
        '别把别人的节奏，当成自己的标准。',
        '做不完的事，明天还有明天。',
        '你今天已经足够好了。',
        '给自己一个微笑，哪怕只是敷衍的。',
        '四点以后，把自己调成省电模式。',
        '你不是机器，累了就需要休息。',
        '今天的难，不会定义你的一生。',
        '慢慢来，比较快。',
      ],
      NotifySlot.evening: [
        '晚上好，今天辛苦了，早点休息。',
        '把今天没做完的事，留给明天吧。',
        '你已经撑过今天了，这很了不起。',
        '睡前别想太多，明天的事明天再说。',
        '今晚请把手机放远一点，让自己安静下来。',
        '你不需要复盘每一个错误。',
        '晚安之前，先原谅今天的自己。',
        '今天也谢谢你，没有放弃。',
        '洗个热水澡，把疲惫冲掉。',
        '夜里容易多想，记得对自己温柔一点。',
        '你已经很努力了，可以休息了。',
        '今晚的月亮，也在替你守夜。',
        '不用带着愧疚入睡，你已经尽力了。',
        '晚上好，愿你有柔软的枕头和安稳的梦。',
        '今天的不开心，就到这里为止。',
        '关灯之前，对自己说一声：我做到了。',
        '你值得一夜好眠。',
        '明天醒来，又是新的一页。',
        '别怕，今天已经结束了。',
        '晚安，世界很吵，但你可以安静。',
      ],
    },
    'en': {
      NotifySlot.morning: [
        "Good morning. You don't have to be perfect today — just be here.",
        'New day. Start with a glass of warm water.',
        'The moment you woke up, you were already braver than yesterday.',
        "Open your eyes slowly. The world isn't rushing you.",
        "Today's light is gentle. Remember to look up.",
        "You don't need instant strength. Just breathe first.",
        "Good morning. May today's wind blow away a little tiredness.",
        "If getting up is hard, sit for a while. That's allowed.",
        'Put yourself first today, too.',
        'You deserve an unhurried morning.',
        'Good morning. You still deserve to be treated kindly.',
        'Stretch first, then decide what today looks like.',
        'You have nothing to prove. You are already enough.',
        "Today's sun rose for you.",
        'Good morning. May you have warm food and a softer mood.',
        'Even if you slept badly, today can move slowly.',
        'You woke up. That is worth celebrating.',
        "You don't have to shine today. Just keep yourself warm.",
        'Good morning. Eat something — your stomach and heart both need it.',
        'A new day. Let things happen slowly.',
      ],
      NotifySlot.noon: [
        "It's noon. Eat first; don't let work swallow you.",
        'Drink some water. Your body has been carrying you all along.',
        'A ten-minute rest is a remarkable act of self-care.',
        'Morning was hard work. Afternoon can be lighter.',
        'Put the phone down and take one warm bite.',
        "You don't have to be productive all the time. Rest counts.",
        'The noon light is lovely. Step outside for a moment.',
        'Eat something you like. No need to calculate everything.',
        "May today's lunch warm your stomach.",
        'Pause and ask yourself: am I tired?',
        "You've done a lot. Rest for a bit.",
        'Good noon. May you have a quiet moment.',
        "Don't compare your pace with anyone else's.",
        'After lunch, give yourself five minutes to stare into space.',
        'Look up. The sky is still wide.',
        "It's noon. Let your shoulders drop.",
        'You deserve one uninterrupted meal.',
        'The hard part of the morning is over.',
        'Good noon. May the afternoon be gentle with you.',
        'Water, food, breath. Those three are enough for now.',
      ],
      NotifySlot.afternoon: [
        'Afternoons are heavy. Make yourself a cup of tea.',
        'Leaning on something for a while is not failure.',
        "You've come a long way. Don't dismiss yourself.",
        "Four o'clock. Stand up, stretch, drink water.",
        "Progress doesn't matter today. You being here does.",
        'If your mind is loud, close your eyes and listen to one breath.',
        "You don't have to solve everything today.",
        'The afternoon light is softening. You can too.',
        "Let yourself be slower. The road won't run away.",
        'You have tried so hard. Really.',
        "If you're tired, stop. Not everything needs to be forced.",
        'Good afternoon. May a breeze loosen your chest.',
        "Don't use someone else's pace as your standard.",
        "What isn't finished can wait for tomorrow.",
        'You are already enough today.',
        'Give yourself a smile, even a tired one.',
        'After four, switch yourself to low-power mode.',
        'You are not a machine. Tired means rest.',
        "Today's difficulty does not define your whole life.",
        'Slow is sometimes faster.',
      ],
      NotifySlot.evening: [
        'Good evening. You worked hard today. Rest early.',
        "Leave what's unfinished for tomorrow.",
        "You made it through today. That's remarkable.",
        "Don't overthink before sleep. Tomorrow can wait.",
        'Put your phone a little farther away tonight.',
        "You don't need to replay every mistake.",
        "Before saying goodnight, forgive today's version of you.",
        'Thank you for not giving up today.',
        'Take a warm shower and wash some of the tiredness away.',
        'Nights make thoughts louder. Be gentle with yourself.',
        "You've tried hard enough. You can rest.",
        'The moon is keeping watch for you tonight.',
        "Don't fall asleep guilty. You did your best.",
        'Good evening. May you have a soft pillow and steady dreams.',
        "Let today's unhappiness end here.",
        'Before turning off the light, tell yourself: I did it.',
        "You deserve a good night's sleep.",
        'Tomorrow is another page.',
        "Don't be afraid. Today is over.",
        'Goodnight. The world is loud, but you can be quiet.',
      ],
    },
    'ja': {
      NotifySlot.morning: [
        'おはよう。今日は完璧じゃなくていい。ただ生きていればいい。',
        '新しい一日。まず温かいお水を一杯。',
        '目が覚めた瞬間、あなたはもう昨日より勇敢です。',
        'ゆっくり目を開けて。世界は急いでいない。',
        '今日の光はやさしい。空を見上げてみて。',
        '起きた瞬間から強くなくていい。まず呼吸して。',
        'おはよう。今日の風が疲れを少し運んでくれますように。',
        '起きるのがつらいなら、しばらく座っていてもいい。',
        '今日も自分を一番に大切にして。',
        '急がない朝が、あなたには似合う。',
        'おはよう。今日のあなたも大切にされる価値があります。',
        '伸びをしてから、今日のことを決めよう。',
      ],
      NotifySlot.noon: [
        'お昼です。まずごはんを食べて。仕事に飲み込まれないで。',
        'お水を飲んで。体はずっとあなたを支えてくれています。',
        '十分の昼休みも、立派な自己愛です。',
        '午前中お疲れさま。午後は少し軽くいこう。',
        'スマホを置いて、温かいごはんを一口。',
        'ずっと効率的でなくていい。休むことも大事な仕事。',
        'お昼の光が気持ちいい。少し外を歩こう。',
        '好きなものを食べて。計算しなくていい。',
        '今日の昼食が、胃を温めてくれますように。',
        '一度止まって、自分に聞いてみて：疲れてる？',
        'もうたくさん頑張った。少し休もう。',
        'こんにちは。少し静かな時間がありますように。',
      ],
      NotifySlot.afternoon: [
        '午後は疲れやすい。温かいお茶を淹れよう。',
        '寄りかかって休むのは、失敗じゃない。',
        'ここまでよく歩いてきた。自分を否定しないで。',
        '四時です。立ち上がって伸びをして、お水を。',
        '今日の進み具合より、あなたがいることが大事。',
        '心がうるさいなら、目を閉じて呼吸を一つ。',
        '今日すべてを解決しなくていい。',
        '午後の光は柔らかくなる。あなたも柔らかくなっていい。',
        'ゆっくりでいい。道は逃げない。',
        'あなたは本当によく頑張っている。',
        '疲れたら止まろう。全部を無理しなくていい。',
        'こんにちは。風が肩の力を抜いてくれますように。',
      ],
      NotifySlot.evening: [
        'こんばんは。今日もお疲れさま。早めに休んで。',
        '今日終わらなかったことは、明日に置いていこう。',
        '今日を乗り越えた。それはすごいこと。',
        '寝る前に考えすぎないで。明日のことは明日。',
        '今夜はスマホを少し遠くに置いて。',
        'すべての間違いを振り返らなくていい。',
        'おやすみの前に、今日の自分を許してあげて。',
        '今日も諦めなかったあなたに、ありがとう。',
        '温かいお風呂で、疲れを流そう。',
        '夜は考えすぎやすい。自分にやさしく。',
        'もう十分頑張った。休んでいい。',
        'こんばんは。柔らかい枕と穏やかな夢を。',
      ],
    },
    'de': {
      NotifySlot.morning: [
        'Guten Morgen. Heute muss nicht perfekt sein. Nur echt.',
        'Ein neuer Tag. Fang mit einem Glas warmem Wasser an.',
        'In dem Moment, in dem du aufwachst, bist du mutiger als gestern.',
        'Öffne die Augen langsam. Die Welt hetzt dich nicht.',
        'Das Licht ist heute sanft. Schau einmal nach oben.',
        'Du musst nicht sofort stark sein. Atme zuerst.',
        'Guten Morgen. Möge der Wind heute etwas Müdigkeit fortblasen.',
        'Wenn Aufstehen schwerfällt, setz dich erst hin. Das ist okay.',
        'Stell dich heute auch an erste Stelle.',
        'Du verdienst einen Morgen ohne Eile.',
        'Guten Morgen. Du verdienst auch heute Freundlichkeit.',
        'Streck dich erst, dann entscheide, was heute kommt.',
      ],
      NotifySlot.noon: [
        'Es ist Mittag. Iss zuerst; lass die Arbeit dich nicht verschlucken.',
        'Trink Wasser. Dein Körper trägt dich schon die ganze Zeit.',
        'Zehn Minuten Pause sind echte Selbstfürsorge.',
        'Der Vormittag war anstrengend. Der Nachmittag darf leichter sein.',
        'Leg das Handy weg und nimm einen warmen Bissen.',
        'Du musst nicht ständig produktiv sein. Pause zählt auch.',
        'Das Mittagslicht ist schön. Geh kurz raus.',
        'Iss etwas, das du magst. Ohne Rechnen.',
        'Möge das Mittagessen deinen Magen wärmen.',
        'Halte inne und frag dich: Bin ich müde?',
        'Du hast viel geschafft. Ruh dich kurz aus.',
        'Guten Tag. Möge dir ein stiller Moment geschenkt sein.',
      ],
      NotifySlot.afternoon: [
        'Nachmittage sind schwer. Mach dir einen Tee.',
        'Sich anzulehnen ist kein Versagen.',
        'Du bist weit gekommen. Mach dich nicht klein.',
        'Vier Uhr. Steh auf, streck dich, trink Wasser.',
        'Der Fortschritt ist heute egal. Dass du da bist, zählt.',
        'Wenn es im Kopf laut ist, schließ die Augen und höre einem Atemzug zu.',
        'Du musst nicht heute alles lösen.',
        'Das Nachmittagslicht wird weicher. Du darfst auch weicher werden.',
        'Sei langsamer. Der Weg läuft nicht weg.',
        'Du hast dich wirklich bemüht.',
        'Wenn du müde bist, halt an. Nicht alles muss erzwungen werden.',
        'Guten Nachmittag. Möge eine Brise deine Brust lockern.',
      ],
      NotifySlot.evening: [
        'Guten Abend. Du hast heute viel geschafft. Ruh dich früh aus.',
        'Lass das Unfertige bis morgen liegen.',
        'Du hast den heutigen Tag überstanden. Das ist viel.',
        'Denk vor dem Schlafen nicht zu viel. Morgen ist morgen.',
        'Leg das Handy heute Nacht etwas weiter weg.',
        'Du musst nicht jeden Fehler noch einmal durchgehen.',
        'Vergib vor dem Gutenacht dem heutigen Ich.',
        'Danke, dass du heute nicht aufgegeben hast.',
        'Nimm eine warme Dusche und spül etwas Müdigkeit ab.',
        'Nachts werden Gedanken laut. Sei sanft mit dir.',
        'Du hast genug versucht. Du darfst ruhen.',
        'Guten Abend. Mögen Kissen weich und Träume ruhig sein.',
      ],
    },
    'es': {
      NotifySlot.morning: [
        'Buenos días. Hoy no hace falta ser perfecto, solo estar.',
        'Un día nuevo. Empieza con un vaso de agua tibia.',
        'Al despertar, ya eres más valiente que ayer.',
        'Abre los ojos despacio. El mundo no te apura.',
        'La luz de hoy es suave. Recuerda mirar hacia arriba.',
        'No necesitas fuerza instantánea. Primero respira.',
        'Buenos días. Que el viento se lleve un poco del cansancio.',
        'Si levantarte cuesta, siéntate un rato. Está permitido.',
        'Hoy también, ponte en primer lugar.',
        'Mereces una mañana sin prisa.',
        'Buenos días. Sigues mereciendo un trato amable.',
        'Estírate primero y luego decide cómo será el día.',
      ],
      NotifySlot.noon: [
        'Es mediodía. Come primero; no dejes que el trabajo te trague.',
        'Bebe agua. Tu cuerpo te sostiene desde hace mucho.',
        'Diez minutos de descanso son un gran acto de autocuidado.',
        'La mañana fue dura. La tarde puede ser más ligera.',
        'Deja el móvil y toma un bocado caliente.',
        'No tienes que ser productivo todo el tiempo. Descansar cuenta.',
        'La luz del mediodía es linda. Sal un momento.',
        'Come algo que te guste. Sin calcular tanto.',
        'Que el almuerzo te caliente el estómago.',
        'Detente y pregúntate: ¿estoy cansado?',
        'Ya hiciste mucho. Descansa un poco.',
        'Buen mediodía. Ojalá tengas un momento de calma.',
      ],
      NotifySlot.afternoon: [
        'Las tardes pesan. Prepárate un té caliente.',
        'Apoyarte un rato no es fracasar.',
        'Has llegado lejos. No te niegues.',
        'Son las cuatro. Levántate, estírate, bebe agua.',
        'El progreso no importa hoy. Que sigas aquí sí.',
        'Si la mente hace ruido, cierra los ojos y escucha una respiración.',
        'No tienes que resolverlo todo hoy.',
        'La luz de la tarde se suaviza. Tú también puedes.',
        'Ve más despacio. El camino no se escapa.',
        'Te has esforzado de verdad.',
        'Si estás cansado, para. No todo hay que forzarlo.',
        'Buenas tardes. Que una brisa te afloje el pecho.',
      ],
      NotifySlot.evening: [
        'Buenas noches. Hoy trabajaste mucho. Descansa temprano.',
        'Deja lo que no terminaste para mañana.',
        'Superaste el día de hoy. Eso es enorme.',
        'No pienses demasiado antes de dormir. Mañana es mañana.',
        'Esta noche, deja el móvil un poco más lejos.',
        'No necesitas repasar cada error.',
        'Antes de dormir, perdona al tú de hoy.',
        'Gracias por no rendirte hoy.',
        'Toma una ducha caliente y quítate algo de cansancio.',
        'Por la noche la mente se alborota. Sé amable contigo.',
        'Ya intentaste bastante. Puedes descansar.',
        'Buenas noches. Ojalá tengas una almohada suave y sueños tranquilos.',
      ],
    },
    'fr': {
      NotifySlot.morning: [
        'Bonjour. Aujourd’hui, pas besoin d’être parfait — juste présent.',
        'Un nouveau jour. Commence par un verre d’eau tiède.',
        'À l’instant où tu ouvres les yeux, tu es plus courageux qu’hier.',
        'Ouvre les yeux doucement. Le monde ne te presse pas.',
        'La lumière est douce aujourd’hui. Lève les yeux un instant.',
        'Pas besoin d’être fort tout de suite. Respire d’abord.',
        'Bonjour. Que le vent emporte un peu de ta fatigue.',
        'Si te lever est difficile, assieds-toi un moment. C’est permis.',
        'Aujourd’hui encore, mets-toi en premier.',
        'Tu mérites un matin sans hâte.',
        'Bonjour. Tu mérites encore qu’on te traite avec douceur.',
        'Étire-toi d’abord, puis décide de ta journée.',
      ],
      NotifySlot.noon: [
        'Midi. Mange d’abord ; ne laisse pas le travail t’avaler.',
        'Bois de l’eau. Ton corps te porte depuis longtemps.',
        'Dix minutes de pause, c’est un vrai soin de soi.',
        'La matinée a été dure. L’après-midi peut être plus léger.',
        'Pose le téléphone et prends une bouchée chaude.',
        'Tu n’as pas à être productif tout le temps. Le repos compte.',
        'La lumière de midi est belle. Sors un instant.',
        'Mange quelque chose que tu aimes. Sans tout calculer.',
        'Que le déjeuner te réchauffe le ventre.',
        'Arrête-toi et demande-toi : suis-je fatigué ?',
        'Tu as déjà beaucoup fait. Repose-toi un peu.',
        'Bon midi. Qu’un moment calme te soit offert.',
      ],
      NotifySlot.afternoon: [
        'Les après-midi sont lourds. Prépare-toi un thé chaud.',
        'T’appuyer un moment n’est pas un échec.',
        'Tu as fait du chemin. Ne te rabaisse pas.',
        'Seize heures. Lève-toi, étire-toi, bois de l’eau.',
        'Le progrès n’importe pas aujourd’hui. Ta présence, si.',
        'Si ta tête fait du bruit, ferme les yeux et écoute une respiration.',
        'Tu n’as pas à tout résoudre aujourd’hui.',
        'La lumière de l’après-midi s’adoucit. Toi aussi, tu peux.',
        'Ralentis. La route ne s’enfuit pas.',
        'Tu t’es vraiment donné du mal.',
        'Si tu es fatigué, arrête-toi. Tout ne doit pas être forcé.',
        'Bon après-midi. Qu’une brise desserre ta poitrine.',
      ],
      NotifySlot.evening: [
        'Bonsoir. Tu as beaucoup donné aujourd’hui. Repose-toi tôt.',
        'Laisse l’inachevé pour demain.',
        'Tu as traversé cette journée. C’est immense.',
        'Ne réfléchis pas trop avant de dormir. Demain sera demain.',
        'Ce soir, éloigne un peu ton téléphone.',
        'Tu n’as pas besoin de repasser chaque erreur.',
        'Avant de dormir, pardonne au toi d’aujourd’hui.',
        'Merci de ne pas avoir abandonné aujourd’hui.',
        'Prends une douche chaude et lave un peu de fatigue.',
        'La nuit rend les pensées bruyantes. Sois doux avec toi.',
        'Tu as assez essayé. Tu peux te reposer.',
        'Bonne nuit. Qu’un oreiller doux et des rêves calmes t’attendent.',
      ],
    },
  };

  static List<String> forSlot(String lang, NotifySlot slot) {
    final code = safeLang(lang);
    return _pools[code]?[slot] ?? _pools['en']![slot]!;
  }

  static String pick(String lang, NotifySlot slot, int seed) {
    final list = forSlot(lang, slot);
    return list[seed.abs() % list.length];
  }

  static String homeQuote(String lang, int seed) {
    final code = safeLang(lang);
    final table = _pools[code];
    final pool = <String>[
      ...(table?[NotifySlot.morning] ?? const <String>[]),
      ...(table?[NotifySlot.noon] ?? const <String>[]),
      ...(table?[NotifySlot.afternoon] ?? const <String>[]),
      ...(table?[NotifySlot.evening] ?? const <String>[]),
    ];
    if (pool.isEmpty) return '';
    return pool[seed.abs() % pool.length];
  }
}

// =============================================================================
// 8. 本机通知
// =============================================================================

class AppNotifications {
  AppNotifications._();

  static final AppNotifications instance = AppNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _ready = false;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // 桌面端/不支持时区插件时退回默认时区
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(android: android, iOS: ios);
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      debugPrint('notifications init failed: $e');
      _ready = false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final androidGranted = await android?.requestNotificationsPermission();

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      return androidGranted ?? iosGranted ?? true;
    } catch (e) {
      debugPrint('notification permission failed: $e');
      return false;
    }
  }

  Future<void> sync({required String lang, required bool enabled}) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!enabled) return;

      final l = L10n(Locale(safeLang(lang)));
      final title = 'Not alone · ${l.t('notifyTitle')}';

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_care',
          'Daily encouragement',
          channelDescription: 'Gentle reminders at 8, 12, 16 and 20',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );

      final now = tz.TZDateTime.now(tz.local);
      for (var day = 0; day < 7; day++) {
        for (final slot in NotifySlot.values) {
          final when = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day + day,
            slot.hour,
          );
          if (!when.isAfter(now)) continue;

          final text = QuoteBank.pick(
            lang,
            slot,
            now.day * 7 + day * 4 + slot.index,
          );

          await _plugin.zonedSchedule(
            day * 10 + slot.index,
            title,
            text,
            when,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
            payload: 'daily:${slot.name}',
          );
        }
      }
    } catch (e) {
      debugPrint('notification sync failed: $e');
    }
  }
}

// =============================================================================
// 9. 风控：极端词汇拦截与 CRITICAL 日志
// =============================================================================

enum RiskCategory { suicide, selfHarm, insult }

class RiskHit {
  const RiskHit(this.category, this.term);

  final RiskCategory category;
  final String term;

  String get level => 'CRITICAL';
}

class RiskGuard {
  const RiskGuard._();

  static const Map<RiskCategory, List<String>> _terms = {
    RiskCategory.suicide: [
      '自杀',
      '想死',
      '不想活',
      '活着没意思',
      '结束生命',
      '一了百了',
      '跳楼',
      '割腕',
      '烧炭',
      '安眠药自尽',
      '轻生',
      'suicide',
      'kill myself',
      'end my life',
      'want to die',
      'better off dead',
      'no reason to live',
      '死にたい',
      '自殺',
      '消えたい',
      'sich umbringen',
      'suizid',
      'will nicht mehr leben',
      'quitarme la vida',
      'suicidio',
      'no quiero vivir',
      'envie de mourir',
      'veux mourir',
      'me tuer',
    ],
    RiskCategory.selfHarm: [
      '自残',
      '自伤',
      '割自己',
      '伤害自己',
      '划手腕',
      'self-harm',
      'self harm',
      'cut myself',
      'hurting myself',
      '自傷',
      'リストカット',
      'selbstverletzung',
      'ritzen',
      'autolesión',
      'me corto',
      'automutilation',
      'me blesser',
    ],
    RiskCategory.insult: [
      '去死',
      '你去死',
      '你该死',
      '傻逼',
      '贱人',
      '婊子',
      '杂种',
      '畜生',
      '废物东西',
      'kys',
      'kill yourself',
      'you should die',
      'go die',
      'du solltest sterben',
      'verpiss dich',
      'ojalá te mueras',
      'ojala te mueras',
      'tu devrais mourir',
    ],
  };

  /// 短词必须整词匹配，避免 "skyscraper" 命中 "kys"。
  static const Set<String> _wholeWordTerms = {'kys', 'go die'};

  /// 常见口语误报：想死你了 / 不想干活 / 跳楼机。
  static bool _isBenign(String text, String term) {
    if (term == '想死' && (text.contains('想死你') || text.contains('想死我'))) {
      return true;
    }
    if (term == '不想活' && (text.contains('不想活动') || text.contains('不想干活'))) {
      return true;
    }
    if (term == '跳楼' && text.contains('跳楼机')) return true;
    return false;
  }

  static bool _containsTerm(String text, String term) {
    if (_wholeWordTerms.contains(term)) {
      final pattern = RegExp(
        '(^|[^a-z])${RegExp.escape(term)}([^a-z]|\$)',
      );
      return pattern.hasMatch(text);
    }
    return text.contains(term);
  }

  static RiskHit? scan(String raw) {
    final text = raw.toLowerCase();
    for (final entry in _terms.entries) {
      for (final term in entry.value) {
        if (_isBenign(text, term)) continue;
        if (_containsTerm(text, term)) return RiskHit(entry.key, term);
      }
    }
    return null;
  }
}

class RiskLogger {
  const RiskLogger._();

  static Future<void> critical(
      RiskHit hit,
      String message, {
        required String source,
        required String lang,
        required String country,
      }) async {
    final payload = <String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'level': 'CRITICAL',
      'category': hit.category.name,
      'term': hit.term,
      'source': source,
      'lang': lang,
      'country': country,
      'chars': message.length,
      'hash': hashText(message),
      'message': message,
    };

    debugPrint(
      '[RISK][CRITICAL] ${jsonEncode({...payload, 'message': '***'})}',
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/risk_events.log');
      await file.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('risk log write failed: $e');
    }
  }
}

// =============================================================================
// 10. 紧急心理热线
// =============================================================================

class Hotline {
  const Hotline(this.label, this.number);

  final String label;
  final String number;
}

const Map<String, List<Hotline>> kHotlines = {
  'CN': [
    Hotline('希望24热线', '400-161-9995'),
    Hotline('北京心理危机研究与干预中心', '010-82951332'),
    Hotline('急救 / 报警', '120'),
  ],
  'US': [
    Hotline('988 Suicide & Crisis Lifeline', '988'),
    Hotline('Emergency', '911'),
  ],
  'DE': [
    Hotline('Telefonseelsorge', '0800-1110111'),
    Hotline('Telefonseelsorge', '0800-1110222'),
    Hotline('Notruf', '112'),
  ],
  'JP': [
    Hotline('いのちの電話', '0120-783-556'),
    Hotline('よりそいホットライン', '0120-279-338'),
    Hotline('救急 / 警察', '119'),
  ],
  'ES': [
    Hotline('Teléfono de la Esperanza', '024'),
    Hotline('Emergencias', '112'),
  ],
  'FR': [
    Hotline('Numéro national prévention suicide', '3114'),
    Hotline('Urgences', '112'),
  ],
};

List<Hotline> hotlinesFor(String country) =>
    kHotlines[country] ?? kHotlines['US']!;

// =============================================================================
// 11. 天气
// =============================================================================

enum WeatherError { network, api }

class WeatherNow {
  const WeatherNow({
    required this.city,
    required this.desc,
    required this.temp,
    required this.humidity,
    required this.windDir,
    required this.windPower,
    required this.reportTime,
  });

  final String city;
  final String desc;
  final String windDir;
  final String windPower;
  final String reportTime;
  final int temp;
  final int humidity;
}

class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.dayDesc,
    required this.high,
    required this.low,
  });

  final DateTime date;
  final String dayDesc;
  final int high;
  final int low;
}

class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.temp,
    required this.rain,
  });

  final DateTime time;
  final double temp;
  final int rain;
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.now,
    this.days = const [],
    this.hours = const [],
    this.uv,
    this.feels,
  });

  final WeatherNow now;
  final List<WeatherDay> days;
  final List<WeatherHour> hours;
  final double? uv;
  final double? feels;
}

class _Extras {
  const _Extras({required this.hours, this.uv, this.feels});

  final List<WeatherHour> hours;
  final double? uv;
  final double? feels;
}

String _str(Object? v) => v is String ? v : (v is num ? '$v' : '');
int _int(Object? v) => v is num ? v.toInt() : int.tryParse(_str(v)) ?? 0;
double _dbl(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(_str(v)) ?? 0;

class WeatherController extends ChangeNotifier {
  WeatherController() : _client = http.Client();

  final http.Client _client;

  WeatherSnapshot? snapshot;
  WeatherError? error;
  bool loading = false;
  DateTime? _lastSuccess;

  Future<void> refresh({bool force = false}) async {
    if (loading) return;
    if (!force &&
        _lastSuccess != null &&
        DateTime.now().difference(_lastSuccess!) <
            const Duration(minutes: 10)) {
      return;
    }
    loading = true;
    error = null;
    notifyListeners();

    try {
      final now = await _fetchNow();
      var days = const <WeatherDay>[];
      try {
        days = await _fetchDays();
      } catch (_) {
        days = const <WeatherDay>[];
      }
      _Extras? extras;
      try {
        extras = await _fetchExtras();
      } catch (_) {
        extras = null;
      }
      snapshot = WeatherSnapshot(
        now: now,
        days: days,
        hours: extras?.hours ?? const <WeatherHour>[],
        uv: extras?.uv,
        feels: extras?.feels,
      );
      error = null;
      _lastSuccess = DateTime.now();
    } on WeatherException catch (e) {
      error = e.kind;
    } catch (_) {
      error = WeatherError.network;
    }

    loading = false;
    notifyListeners();
  }

  Future<WeatherNow> _fetchNow() async {
    final map = await _getJson(
      Uri.https('restapi.amap.com', '/v3/weather/weatherInfo', {
        'key': kAmapKey,
        'city': kCityCode,
        'extensions': 'base',
      }),
    );
    if (_str(map['status']) != '1')
      throw const WeatherException(WeatherError.api);
    final lives = map['lives'];
    if (lives is! List || lives.isEmpty) {
      throw const WeatherException(WeatherError.api);
    }
    final live = Map<String, dynamic>.from(lives.first as Map);
    return WeatherNow(
      city: _str(live['city']),
      desc: _str(live['weather']),
      temp: _int(live['temperature']),
      humidity: _int(live['humidity']),
      windDir: _str(live['winddirection']),
      windPower: _str(live['windpower']),
      reportTime: _str(live['reporttime']),
    );
  }

  Future<List<WeatherDay>> _fetchDays() async {
    final map = await _getJson(
      Uri.https('restapi.amap.com', '/v3/weather/weatherInfo', {
        'key': kAmapKey,
        'city': kCityCode,
        'extensions': 'all',
      }),
    );
    final forecasts = map['forecasts'];
    if (forecasts is! List || forecasts.isEmpty) return const <WeatherDay>[];
    final casts = (forecasts.first as Map)['casts'];
    if (casts is! List) return const <WeatherDay>[];
    final out = <WeatherDay>[];
    for (final raw in casts.whereType<Map>()) {
      final m = Map<String, dynamic>.from(raw);
      out.add(
        WeatherDay(
          date: DateTime.tryParse(_str(m['date'])) ?? DateTime.now(),
          dayDesc: _str(m['dayweather']),
          high: _int(m['daytemp']),
          low: _int(m['nighttemp']),
        ),
      );
    }
    return out;
  }

  Future<_Extras?> _fetchExtras() async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$kLat',
      'longitude': '$kLon',
      'current': 'apparent_temperature,uv_index',
      'hourly': 'temperature_2m,precipitation_probability',
      'timezone': 'Asia/Shanghai',
      'forecast_days': '2',
    });
    final response =
    await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) return null;

    final hours = <WeatherHour>[];
    final hourly = decoded['hourly'];
    if (hourly is Map<String, dynamic>) {
      final times = hourly['time'] as List? ?? const [];
      final temps = hourly['temperature_2m'] as List? ?? const [];
      final rains = hourly['precipitation_probability'] as List? ?? const [];
      final now = DateTime.now();
      final floor = DateTime(now.year, now.month, now.day, now.hour);
      for (var i = 0; i < times.length; i++) {
        final t = DateTime.tryParse('${times[i]}');
        if (t == null || t.isBefore(floor)) continue;
        hours.add(
          WeatherHour(
            time: t,
            temp: _dbl(i < temps.length ? temps[i] : null),
            rain: _int(i < rains.length ? rains[i] : null),
          ),
        );
        if (hours.length >= 12) break;
      }
    }

    final current = decoded['current'];
    if (current is! Map<String, dynamic>) {
      return _Extras(hours: hours);
    }
    return _Extras(
      hours: hours,
      uv: _dbl(current['uv_index']),
      feels: _dbl(current['apparent_temperature']),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const WeatherException(WeatherError.network);
    }
    if (response.statusCode != 200) {
      throw const WeatherException(WeatherError.network);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      throw const WeatherException(WeatherError.api);
    } on WeatherException {
      rethrow;
    } catch (_) {
      throw const WeatherException(WeatherError.api);
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

class WeatherException implements Exception {
  const WeatherException(this.kind);

  final WeatherError kind;

  @override
  String toString() => 'WeatherException($kind)';
}

// =============================================================================
// 12. 节日引擎（按国家筛选）
// =============================================================================

class HolidayRule {
  const HolidayRule.fixed(int month, int day)
      : month = month,
        day = day,
        easterOffset = null,
        weekday = null,
        nth = null;

  const HolidayRule.easter(int easterOffset)
      : month = null,
        day = null,
        easterOffset = easterOffset,
        weekday = null,
        nth = null;

  const HolidayRule.nth(int month, int weekday, int nth)
      : month = month,
        day = null,
        easterOffset = null,
        weekday = weekday,
        nth = nth;

  final int? month;
  final int? day;
  final int? easterOffset;
  final int? weekday;
  final int? nth;
}

class Holiday {
  const Holiday(this.country, this.names);

  final String country;
  final Map<String, String> names;

  String nameFor(String lang) {
    final code = safeLang(lang);
    return names[code] ?? names['en'] ?? names.values.first;
  }
}

class _HolidayDef {
  const _HolidayDef(this.country, this.rule, this.names);

  final String country;
  final HolidayRule rule;
  final Map<String, String> names;
}

const List<_HolidayDef> _holidayDefs = [
  // ---------- 中国 ----------
  _HolidayDef(
      'CN', HolidayRule.fixed(1, 1), {'zh': '元旦', 'en': "New Year's Day"}),
  _HolidayDef(
      'CN', HolidayRule.fixed(4, 4), {'zh': '清明节', 'en': 'Qingming Festival'}),
  _HolidayDef('CN', HolidayRule.fixed(5, 1), {'zh': '劳动节', 'en': 'Labour Day'}),
  _HolidayDef(
      'CN', HolidayRule.fixed(10, 1), {'zh': '国庆节', 'en': 'National Day'}),

  // ---------- 美国 ----------
  _HolidayDef(
      'US', HolidayRule.fixed(1, 1), {'en': "New Year's Day", 'zh': '新年'}),
  _HolidayDef('US', HolidayRule.nth(1, 1, 3),
      {'en': 'Martin Luther King Jr. Day', 'zh': '马丁·路德·金纪念日'}),
  _HolidayDef(
      'US', HolidayRule.nth(2, 1, 3), {'en': "Presidents' Day", 'zh': '总统日'}),
  _HolidayDef(
      'US', HolidayRule.nth(5, 1, -1), {'en': 'Memorial Day', 'zh': '阵亡将士纪念日'}),
  _HolidayDef(
      'US', HolidayRule.fixed(6, 19), {'en': 'Juneteenth', 'zh': '六月节'}),
  _HolidayDef(
      'US', HolidayRule.fixed(7, 4), {'en': 'Independence Day', 'zh': '独立日'}),
  _HolidayDef('US', HolidayRule.nth(9, 1, 1), {'en': 'Labor Day', 'zh': '劳动节'}),
  _HolidayDef(
      'US', HolidayRule.nth(10, 1, 2), {'en': 'Columbus Day', 'zh': '哥伦布日'}),
  _HolidayDef(
      'US', HolidayRule.fixed(11, 11), {'en': 'Veterans Day', 'zh': '退伍军人节'}),
  _HolidayDef(
      'US', HolidayRule.nth(11, 4, 4), {'en': 'Thanksgiving', 'zh': '感恩节'}),
  _HolidayDef(
      'US', HolidayRule.fixed(12, 25), {'en': 'Christmas Day', 'zh': '圣诞节'}),

  // ---------- 德国 ----------
  _HolidayDef('DE', HolidayRule.fixed(1, 1),
      {'de': 'Neujahr', 'zh': '元旦', 'en': "New Year's Day"}),
  _HolidayDef('DE', HolidayRule.fixed(1, 6),
      {'de': 'Heilige Drei Könige', 'zh': '主显节', 'en': 'Epiphany'}),
  _HolidayDef('DE', HolidayRule.easter(-2),
      {'de': 'Karfreitag', 'zh': '耶稣受难日', 'en': 'Good Friday'}),
  _HolidayDef('DE', HolidayRule.easter(1),
      {'de': 'Ostermontag', 'zh': '复活节星期一', 'en': 'Easter Monday'}),
  _HolidayDef('DE', HolidayRule.fixed(5, 1),
      {'de': 'Tag der Arbeit', 'zh': '劳动节', 'en': 'Labour Day'}),
  _HolidayDef('DE', HolidayRule.easter(39),
      {'de': 'Christi Himmelfahrt', 'zh': '耶稣升天节', 'en': 'Ascension Day'}),
  _HolidayDef('DE', HolidayRule.easter(50),
      {'de': 'Pfingstmontag', 'zh': '圣灵降临节星期一', 'en': 'Whit Monday'}),
  _HolidayDef('DE', HolidayRule.fixed(10, 3), {
    'de': 'Tag der Deutschen Einheit',
    'zh': '德国统一日',
    'en': 'German Unity Day'
  }),
  _HolidayDef('DE', HolidayRule.fixed(10, 31),
      {'de': 'Reformationstag', 'zh': '宗教改革日', 'en': 'Reformation Day'}),
  _HolidayDef('DE', HolidayRule.fixed(11, 1),
      {'de': 'Allerheiligen', 'zh': '万圣节', 'en': "All Saints' Day"}),
  _HolidayDef('DE', HolidayRule.fixed(12, 25),
      {'de': '1. Weihnachtstag', 'zh': '圣诞第一节', 'en': 'Christmas Day'}),
  _HolidayDef('DE', HolidayRule.fixed(12, 26),
      {'de': '2. Weihnachtstag', 'zh': '圣诞第二节', 'en': 'Boxing Day'}),

  // ---------- 日本 ----------
  _HolidayDef('JP', HolidayRule.fixed(1, 1),
      {'ja': '元日', 'zh': '元旦', 'en': "New Year's Day"}),
  _HolidayDef('JP', HolidayRule.nth(1, 1, 2),
      {'ja': '成人の日', 'zh': '成人节', 'en': 'Coming of Age Day'}),
  _HolidayDef('JP', HolidayRule.fixed(2, 11),
      {'ja': '建国記念の日', 'zh': '建国纪念日', 'en': 'National Foundation Day'}),
  _HolidayDef('JP', HolidayRule.fixed(2, 23),
      {'ja': '天皇誕生日', 'zh': '天皇诞辰', 'en': "Emperor's Birthday"}),
  _HolidayDef('JP', HolidayRule.fixed(3, 20),
      {'ja': '春分の日', 'zh': '春分', 'en': 'Vernal Equinox Day'}),
  _HolidayDef('JP', HolidayRule.fixed(4, 29),
      {'ja': '昭和の日', 'zh': '昭和之日', 'en': 'Showa Day'}),
  _HolidayDef('JP', HolidayRule.fixed(5, 3),
      {'ja': '憲法記念日', 'zh': '宪法纪念日', 'en': 'Constitution Memorial Day'}),
  _HolidayDef('JP', HolidayRule.fixed(5, 4),
      {'ja': 'みどりの日', 'zh': '绿之日', 'en': 'Greenery Day'}),
  _HolidayDef('JP', HolidayRule.fixed(5, 5),
      {'ja': 'こどもの日', 'zh': '儿童节', 'en': "Children's Day"}),
  _HolidayDef('JP', HolidayRule.nth(7, 1, 3),
      {'ja': '海の日', 'zh': '海之日', 'en': 'Marine Day'}),
  _HolidayDef('JP', HolidayRule.fixed(8, 11),
      {'ja': '山の日', 'zh': '山之日', 'en': 'Mountain Day'}),
  _HolidayDef('JP', HolidayRule.nth(9, 1, 3),
      {'ja': '敬老の日', 'zh': '敬老日', 'en': 'Respect for the Aged Day'}),
  _HolidayDef('JP', HolidayRule.fixed(9, 23),
      {'ja': '秋分の日', 'zh': '秋分', 'en': 'Autumnal Equinox Day'}),
  _HolidayDef('JP', HolidayRule.nth(10, 1, 2),
      {'ja': 'スポーツの日', 'zh': '体育日', 'en': 'Sports Day'}),
  _HolidayDef('JP', HolidayRule.fixed(11, 3),
      {'ja': '文化の日', 'zh': '文化日', 'en': 'Culture Day'}),
  _HolidayDef('JP', HolidayRule.fixed(11, 23),
      {'ja': '勤労感謝の日', 'zh': '劳动感谢日', 'en': 'Labour Thanksgiving Day'}),

  // ---------- 西班牙 ----------
  _HolidayDef('ES', HolidayRule.fixed(1, 1),
      {'es': 'Año Nuevo', 'zh': '元旦', 'en': "New Year's Day"}),
  _HolidayDef('ES', HolidayRule.fixed(1, 6),
      {'es': 'Día de Reyes', 'zh': '三王节', 'en': 'Epiphany'}),
  _HolidayDef('ES', HolidayRule.easter(-2),
      {'es': 'Viernes Santo', 'zh': '耶稣受难日', 'en': 'Good Friday'}),
  _HolidayDef('ES', HolidayRule.fixed(5, 1),
      {'es': 'Día del Trabajo', 'zh': '劳动节', 'en': 'Labour Day'}),
  _HolidayDef('ES', HolidayRule.fixed(8, 15),
      {'es': 'Asunción', 'zh': '圣母升天节', 'en': 'Assumption'}),
  _HolidayDef('ES', HolidayRule.fixed(10, 12),
      {'es': 'Fiesta Nacional', 'zh': '国庆日', 'en': 'National Day'}),
  _HolidayDef('ES', HolidayRule.fixed(11, 1),
      {'es': 'Todos los Santos', 'zh': '万圣节', 'en': "All Saints' Day"}),
  _HolidayDef('ES', HolidayRule.fixed(12, 6),
      {'es': 'Día de la Constitución', 'zh': '宪法日', 'en': 'Constitution Day'}),
  _HolidayDef('ES', HolidayRule.fixed(12, 8), {
    'es': 'Inmaculada Concepción',
    'zh': '圣母无染原罪节',
    'en': 'Immaculate Conception'
  }),
  _HolidayDef('ES', HolidayRule.fixed(12, 25),
      {'es': 'Navidad', 'zh': '圣诞节', 'en': 'Christmas Day'}),

  // ---------- 法国 ----------
  _HolidayDef('FR', HolidayRule.fixed(1, 1),
      {'fr': 'Jour de l’an', 'zh': '元旦', 'en': "New Year's Day"}),
  _HolidayDef('FR', HolidayRule.easter(1),
      {'fr': 'Lundi de Pâques', 'zh': '复活节星期一', 'en': 'Easter Monday'}),
  _HolidayDef('FR', HolidayRule.fixed(5, 1),
      {'fr': 'Fête du Travail', 'zh': '劳动节', 'en': 'Labour Day'}),
  _HolidayDef('FR', HolidayRule.fixed(5, 8),
      {'fr': 'Victoire 1945', 'zh': '二战胜利日', 'en': 'Victory Day'}),
  _HolidayDef('FR', HolidayRule.easter(39),
      {'fr': 'Ascension', 'zh': '耶稣升天节', 'en': 'Ascension Day'}),
  _HolidayDef('FR', HolidayRule.easter(50),
      {'fr': 'Lundi de Pentecôte', 'zh': '圣灵降临节星期一', 'en': 'Whit Monday'}),
  _HolidayDef('FR', HolidayRule.fixed(7, 14),
      {'fr': 'Fête Nationale', 'zh': '法国国庆日', 'en': 'Bastille Day'}),
  _HolidayDef('FR', HolidayRule.fixed(8, 15),
      {'fr': 'Assomption', 'zh': '圣母升天节', 'en': 'Assumption'}),
  _HolidayDef('FR', HolidayRule.fixed(11, 1),
      {'fr': 'Toussaint', 'zh': '万圣节', 'en': "All Saints' Day"}),
  _HolidayDef('FR', HolidayRule.fixed(11, 11),
      {'fr': 'Armistice', 'zh': '停战纪念日', 'en': 'Armistice Day'}),
  _HolidayDef('FR', HolidayRule.fixed(12, 25),
      {'fr': 'Noël', 'zh': '圣诞节', 'en': 'Christmas Day'}),
];

const Map<int, Map<String, List<int>>> _lunarDates = {
  2024: {
    'spring': [2, 10],
    'lantern': [2, 24],
    'dragon': [6, 10],
    'mid': [9, 17],
    'double': [10, 11],
  },
  2025: {
    'spring': [1, 29],
    'lantern': [2, 12],
    'dragon': [5, 31],
    'mid': [10, 6],
    'double': [10, 29],
  },
  2026: {
    'spring': [2, 17],
    'lantern': [3, 3],
    'dragon': [6, 19],
    'mid': [9, 25],
    'double': [10, 18],
  },
  2027: {
    'spring': [2, 6],
    'lantern': [2, 20],
    'dragon': [6, 9],
    'mid': [9, 15],
    'double': [10, 8],
  },
};

const Map<String, List<String>> _lunarNames = {
  'spring': ['春节', 'Spring Festival'],
  'lantern': ['元宵节', 'Lantern Festival'],
  'dragon': ['端午节', 'Dragon Boat Festival'],
  'mid': ['中秋节', 'Mid-Autumn Festival'],
  'double': ['重阳节', 'Double Ninth Festival'],
};

class HolidayEngine {
  const HolidayEngine();

  List<Holiday> forDate(DateTime date, String country) {
    final out = <Holiday>[];

    for (final def in _holidayDefs) {
      if (def.country != country) continue;
      if (_matches(def.rule, date)) out.add(Holiday(def.country, def.names));
    }

    if (country == 'CN') {
      final lunar = _lunarDates[date.year];
      if (lunar != null) {
        lunar.forEach((key, md) {
          if (md[0] == date.month && md[1] == date.day) {
            final names = _lunarNames[key];
            if (names != null) {
              out.add(Holiday('CN', {'zh': names[0], 'en': names[1]}));
            }
          }
        });
      }
    }

    return out;
  }

  Map<int, List<Holiday>> forMonth(int year, int month, String country) {
    final result = <int, List<Holiday>>{};
    final total = DateTime(year, month + 1, 0).day;
    for (var day = 1; day <= total; day++) {
      final list = forDate(DateTime(year, month, day), country);
      if (list.isNotEmpty) result[day] = list;
    }
    return result;
  }

  bool _matches(HolidayRule rule, DateTime date) {
    if (rule.easterOffset != null) {
      final target = easter(date.year).add(Duration(days: rule.easterOffset!));
      return target.month == date.month && target.day == date.day;
    }
    if (rule.weekday != null) {
      if (date.month != rule.month) return false;
      return _nthWeekday(date.year, rule.month!, rule.weekday!, rule.nth!) ==
          date.day;
    }
    return date.month == rule.month && date.day == rule.day;
  }

  DateTime easter(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = (h + l - 7 * m + 114) % 31 + 1;
    return DateTime(year, month, day);
  }

  int _nthWeekday(int year, int month, int weekday, int nth) {
    if (nth > 0) {
      final first = DateTime(year, month, 1);
      final delta = (weekday - first.weekday) % 7;
      return 1 + delta + (nth - 1) * 7;
    }
    final last = DateTime(year, month + 1, 0);
    final delta = (last.weekday - weekday) % 7;
    return last.day - delta + (nth + 1) * 7;
  }

  String countryLabel(String code) {
    final country = countryByCode(code);
    return '${country.flag} ${country.nativeName}';
  }
}

const HolidayEngine holidayEngine = HolidayEngine();

// =============================================================================
// 13. App 入口
// =============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStore.load();
  await AppNotifications.instance.init();
  runApp(const NotAloneApp());
}

class NotAloneApp extends StatelessWidget {
  const NotAloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.I,
      builder: (context, _) {
        final store = AppStore.I;
        return MaterialApp(
          title: 'Not alone',
          debugShowCheckedModeBanner: false,
          locale: store.locale,
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            L10n.delegate,
          ],
          themeMode: store.themeMode,
          theme: AppTheme.build(Brightness.light, store.appFont),
          darkTheme: AppTheme.build(Brightness.dark, store.appFont),
          home:
          store.onboardingDone ? const RootPage() : const OnboardingPage(),
        );
      },
    );
  }
}

// =============================================================================
// 14. 首次引导：强制选择语言与国家
// =============================================================================

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late String _lang = AppStore.I.langCode;
  String? _country;
  bool _langTouched = false;

  void _selectLang(String code) {
    setState(() {
      _lang = code;
      _langTouched = true;
    });
  }

  void _selectCountry(CountryInfo country) {
    setState(() {
      _country = country.code;
      if (!_langTouched) _lang = country.lang;
    });
  }

  Future<void> _start() async {
    final country = _country;
    if (country == null) return;
    await AppStore.I.completeOnboarding(country, _lang);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n(Locale(_lang));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A0D18),
                  Color(0xFF16233D),
                  Color(0xFF0B0E16),
                ],
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -70,
            child: _GlowOrb(
              size: 260,
              color: cs.primary.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -80,
            child: _GlowOrb(
              size: 300,
              color: const Color(0xFFFFB4C1).withValues(alpha: 0.18),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo(size: 58),
                  const SizedBox(height: 24),
                  Text(
                    l.t('onboardingTitle'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.t('onboardingSub'),
                    style: const TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _GuideLabel(text: l.t('onboardingLang')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final code in const [
                        'zh',
                        'en',
                        'ja',
                        'de',
                        'es',
                        'fr'
                      ])
                        _ChoiceChip(
                          label: _langNativeName(code),
                          selected: _lang == code,
                          onTap: () => _selectLang(code),
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _GuideLabel(text: l.t('onboardingCountry')),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.35,
                    children: [
                      for (final country in kCountries)
                        _CountryCard(
                          country: country,
                          selected: _country == country.code,
                          onTap: () => _selectCountry(country),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.t('onboardingNote'),
                    style: const TextStyle(
                      color: Color(0x80FFFFFF),
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0B0E16),
                        disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.16),
                        disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.35),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(27),
                        ),
                      ),
                      onPressed: _country == null ? null : _start,
                      child: Text(
                        l.t('onboardingStart'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _langNativeName(String code) => const {
    'zh': '中文',
    'en': 'English',
    'ja': '日本語',
    'de': 'Deutsch',
    'es': 'Español',
    'fr': 'Français',
  }[code]!;
}

class _GuideLabel extends StatelessWidget {
  const _GuideLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0x99FFFFFF),
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color:
            selected ? Colors.white : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF0B0E16) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({
    required this.country,
    required this.selected,
    required this.onTap,
  });

  final CountryInfo country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.94)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
            selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                country.nativeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? const Color(0xFF0B0E16) : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: Color(0xFF3B6FE0),
              ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

// =============================================================================
// 15. 主框架
// =============================================================================

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> with WidgetsBindingObserver {
  final WeatherController _weather = WeatherController();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _weather.refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupGates());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _weather.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _weather.refresh();
  }

  Future<void> _runStartupGates() async {
    final store = AppStore.I;

    if (!store.careAccepted) {
      await showCareDialog(context);
      await store.acceptCare();
    }
    if (!mounted) return;

    if (store.birthday == null) {
      final value = await showBirthdayDialog(context);
      if (value != null) await store.setBirthday(value);
    }
    if (!mounted) return;

    final birthday = store.birthday;
    if (birthday != null &&
        isBirthdayToday(birthday) &&
        store.cakeShownOn != ymd(DateTime.now())) {
      await showCakeDialog(context, birthday);
      await store.markCakeShown();
    }
    if (!mounted) return;

    await _syncNotifications();
  }

  Future<void> _syncNotifications() async {
    final store = AppStore.I;
    if (!store.notificationsEnabled) {
      await AppNotifications.instance.sync(
        lang: store.langCode,
        enabled: false,
      );
      return;
    }

    final granted = await AppNotifications.instance.requestPermission();
    if (!granted) {
      await store.setNotifications(false);
      if (mounted) {
        _snack(context.t('notifyPermission'));
      }
      return;
    }

    await AppNotifications.instance.sync(
      lang: store.langCode,
      enabled: true,
    );
  }

  Future<void> _openAlarmSheet() async {
    final result = await showAlarmSheet(
      context,
      AppStore.I.alarmHour,
      AppStore.I.alarmMinute,
    );
    if (result == null) return;
    await AppStore.I.setAlarm(result.$1, result.$2);
    if (!mounted) return;
    final label = '${two(result.$1)}:${two(result.$2)}';
    _snack(context.t('alarmSaved', {'t': label}));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    return ListenableBuilder(
      listenable: AppStore.I,
      builder: (context, _) {
        final store = AppStore.I;
        return Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: _tab,
            children: [
              HomePage(
                weather: _weather,
                alarmHour: store.alarmHour,
                alarmMinute: store.alarmMinute,
                wallpaper: store.wallpaper,
                ringtone: store.ringtone,
                onOpenAlarm: _openAlarmSheet,
              ),
              WeatherPage(weather: _weather),
              const CalendarPage(),
              const TreeHolePage(),
              SettingsPage(onOpenAlarm: _openAlarmSheet),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.94),
              border: Border(
                top: BorderSide(
                  color: cs.onSurface.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              backgroundColor: Colors.transparent,
              elevation: 0,
              height: 66,
              indicatorColor: cs.primary.withValues(alpha: 0.16),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.nightlight_outlined),
                  selectedIcon: const Icon(Icons.nightlight_round),
                  label: l.t('navHome'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.cloud_outlined),
                  selectedIcon: const Icon(Icons.cloud),
                  label: l.t('navWeather'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.calendar_month_outlined),
                  selectedIcon: const Icon(Icons.calendar_month),
                  label: l.t('navCalendar'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.forest_outlined),
                  selectedIcon: const Icon(Icons.forest),
                  label: l.t('navTree'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: l.t('navSettings'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// 16. 共享组件
// =============================================================================

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Image.asset(
        kAppLogo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFA9D6FF), Color(0xFF6E8BFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6E8BFF).withValues(alpha: 0.35),
            blurRadius: size * 0.5,
            offset: Offset(0, size * 0.15),
          ),
        ],
      ),
      child: Icon(
        Icons.nightlight_round,
        size: size * 0.5,
        color: Colors.white,
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.onTap,
    this.onImage = true,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final base = onImage ? Colors.white : cs.onSurface;

    final Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: onImage
                ? Colors.white.withValues(alpha: 0.14)
                : cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: base.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: onImage ? 0.16 : 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: base.withValues(alpha: 0.72)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: base.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 13,
                      color: base.withValues(alpha: 0.45),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: base,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: base.withValues(alpha: 0.45),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  final cs = context.cs;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(child: builder(ctx)),
            ],
          ),
        ),
      );
    },
  );
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: context.cs.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class MiniCalendar extends StatelessWidget {
  const MiniCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.onFocused,
    required this.onSelected,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onFocused;
  final void Function(DateTime selected, DateTime focused) onSelected;

  @override
  Widget build(BuildContext context) {
    final lang = context.l10n.lang;
    final country = AppStore.I.countryCode;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => onFocused(
                  DateTime(focusedDay.year, focusedDay.month - 1, 1),
                ),
                icon: const Icon(Icons.chevron_left,
                    size: 18, color: Colors.white),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    monthLabel(focusedDay, lang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => onFocused(
                  DateTime(focusedDay.year, focusedDay.month + 1, 1),
                ),
                icon: const Icon(Icons.chevron_right,
                    size: 18, color: Colors.white),
              ),
            ],
          ),
          TableCalendar<Holiday>(
            firstDay: DateTime.utc(1970, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: focusedDay,
            headerVisible: false,
            rowHeight: 30,
            daysOfWeekHeight: 18,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: ''},
            eventLoader: (day) => holidayEngine.forDate(day, country),
            selectedDayPredicate: (day) => isSameDay(day, selectedDay),
            onDaySelected: onSelected,
            onPageChanged: onFocused,
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              cellMargin: const EdgeInsets.all(2),
              defaultTextStyle: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 11,
              ),
              weekendTextStyle: const TextStyle(
                color: Color(0x80FFFFFF),
                fontSize: 11,
              ),
              todayDecoration: const BoxDecoration(
                color: Color(0x3DFFFFFF),
                shape: BoxShape.circle,
              ),
              todayTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
              selectedDecoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(
                color: Colors.black,
                fontSize: 11,
              ),
            ),
            calendarBuilders: CalendarBuilders<Holiday>(
              dowBuilder: (c, day) {
                return Center(
                  child: Text(
                    wdShort(day.weekday, lang),
                    style: const TextStyle(
                      color: Color(0x66FFFFFF),
                      fontSize: 9,
                    ),
                  ),
                );
              },
              markerBuilder: (c, day, events) {
                if (events.isEmpty) return null;
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFD54F),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 17. 天气组件
// =============================================================================

class WeatherMetrics extends StatelessWidget {
  const WeatherMetrics({super.key, required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    final items = <List<String>>[
      [l.t('humidity'), '${snapshot.now.humidity}%'],
      [l.t('wind'), '${snapshot.now.windDir} ${snapshot.now.windPower}'],
      [l.t('uv'), snapshot.uv == null ? '—' : snapshot.uv!.toStringAsFixed(1)],
      [
        l.t('feels'),
        snapshot.feels == null ? '—' : '${snapshot.feels!.round()}°C',
      ],
    ];

    const icons = [
      Icons.water_drop_outlined,
      Icons.air,
      Icons.wb_sunny_outlined,
      Icons.thermostat_outlined,
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.5,
      children: [
        for (var i = 0; i < items.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  icons[i],
                  size: 15,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i][0],
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        items[i][1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class HourStrip extends StatelessWidget {
  const HourStrip({super.key, required this.hours});

  final List<WeatherHour> hours;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final hour = hours[index];
          return Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${two(hour.time.hour)}:00',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
                Icon(
                  hour.rain >= 50
                      ? Icons.umbrella_outlined
                      : Icons.wb_sunny_outlined,
                  size: 15,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
                Text(
                  '${hour.temp.round()}°',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${hour.rain}%',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class DailyList extends StatelessWidget {
  const DailyList({super.key, required this.days});

  final List<WeatherDay> days;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    return Column(
      children: [
        for (final day in days)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 108,
                  child: Text(
                    '${day.date.month}/${day.date.day} ${wdFull(day.date.weekday, l.lang)}',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    weatherDesc(day.dayDesc, l.lang),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '${day.low}° / ${day.high}°',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class WeatherErrorBox extends StatelessWidget {
  const WeatherErrorBox({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final WeatherError? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            error == WeatherError.api ? Icons.cloud_off : Icons.wifi_off,
            size: 26,
            color: cs.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 10),
          Text(
            l.t(error == WeatherError.api ? 'wUnavailable' : 'wNetwork'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.65),
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          TextButton(onPressed: onRetry, child: Text(l.t('wRetry'))),
        ],
      ),
    );
  }
}

Future<void> showWeatherSheet(
    BuildContext context,
    WeatherController controller,
    ) {
  return showAppSheet<void>(context, (ctx) {
    final l = ctx.l10n;
    final cs = ctx.cs;

    return ListenableBuilder(
      listenable: controller,
      builder: (ctx, _) {
        final data = controller.snapshot;

        if (data == null) {
          if (controller.loading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return WeatherErrorBox(
            error: controller.error,
            onRetry: () => controller.refresh(force: true),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${data.now.temp}°',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 44,
                      height: 1,
                      fontWeight: FontWeight.w200,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${weatherDesc(data.now.desc, l.lang)} · ${data.now.city}',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      data.now.reportTime,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.35),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              WeatherMetrics(snapshot: data),
              if (data.hours.isNotEmpty) ...[
                const SizedBox(height: 18),
                SheetTitle(l.t('wHourly')),
                HourStrip(hours: data.hours),
              ],
              if (data.days.isNotEmpty) ...[
                const SizedBox(height: 18),
                SheetTitle(l.t('wDaily')),
                DailyList(days: data.days),
              ],
              const SizedBox(height: 12),
              Text(
                l.t('wExtras'),
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.28),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        );
      },
    );
  });
}

// =============================================================================
// 18. 首页
// =============================================================================

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.weather,
    required this.alarmHour,
    required this.alarmMinute,
    required this.wallpaper,
    required this.ringtone,
    required this.onOpenAlarm,
  });

  final WeatherController weather;
  final int alarmHour;
  final int alarmMinute;
  final String? wallpaper;
  final String? ringtone;
  final VoidCallback onOpenAlarm;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerSub;
  Timer? _ticker;

  DateTime _now = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  PlayerState _playerState = PlayerState.stopped;
  bool _showCalendar = false;
  bool _ringing = false;
  String? _firedKey;
  final int _quoteSeed = rnd.nextInt(997);

  @override
  void initState() {
    super.initState();
    _playerSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alarmHour != widget.alarmHour ||
        oldWidget.alarmMinute != widget.alarmMinute) {
      _firedKey = null;
    }
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _playerSub = null;
    _ticker?.cancel();
    _ticker = null;
    _player.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() => _now = now);
    _checkAlarm(now);
  }

  void _checkAlarm(DateTime now) {
    if (now.hour != widget.alarmHour || now.minute != widget.alarmMinute) {
      return;
    }
    final key = '${ymd(now)} ${now.hour}:${now.minute}';
    if (_firedKey == key) return;
    _firedKey = key;
    unawaited(_ring());
  }

  Future<void> _ring() async {
    if (_ringing || !mounted) return;
    _ringing = true;

    final lang = context.l10n.lang;
    final quote = QuoteBank.pick(
      lang,
      NotifySlot.morning,
      _now.day + _now.hour,
    );
    await _startAudio();

    if (!mounted) {
      _ringing = false;
      await _stopAudio();
      return;
    }

    await showWakeUpOverlay(context, quote);
    _ringing = false;
    await _stopAudio();
  }

  Future<void> _startAudio() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1);
      final path = widget.ringtone;
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        await _player.play(DeviceFileSource(path));
      } else {
        await _player.play(AssetSource('Ring10.wav'));
      }
    } catch (e) {
      debugPrint('alarm audio failed: $e');
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('stop alarm failed: $e');
    }
  }

  String _greeting(L10n l) {
    final hour = _now.hour;
    if (hour < 6) return l.t('greetNight');
    if (hour < 12) return l.t('greetMorning');
    if (hour < 18) return l.t('greetNoon');
    return l.t('greetEvening');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final night = _now.hour >= 18 || _now.hour < 6;
    final quote = QuoteBank.homeQuote(l.lang, _quoteSeed + _now.day);

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(night),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: night
                  ? const [
                Color(0xA6000000),
                Color(0x38000000),
                Color(0xE6000000),
              ]
                  : const [
                Color(0x73000000),
                Color(0x1F000000),
                Color(0xB3000000),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.t('app'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _greeting(l),
                            style: const TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l.t('moodTitle'),
                      onPressed: () =>
                          showMoodCard(context, initialText: quote),
                      icon: const Icon(
                        Icons.auto_awesome_outlined,
                        color: Colors.white,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: l.t('alarm'),
                      onPressed: widget.onOpenAlarm,
                      icon: const Icon(
                        Icons.alarm_add_outlined,
                        color: Colors.white,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _showCalendar = !_showCalendar),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(
                                  begin: 0.92,
                                  end: 1,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _showCalendar
                              ? MiniCalendar(
                            key: const ValueKey('mini-calendar'),
                            focusedDay: _focusedDay,
                            selectedDay: _selectedDay,
                            onFocused: (day) =>
                                setState(() => _focusedDay = day),
                            onSelected: (selected, focused) {
                              setState(() {
                                _selectedDay = selected;
                                _focusedDay = focused;
                              });
                            },
                          )
                              : _buildClock(l),
                        ),
                      ),
                    ),
                  ),
                ),
                _buildQuoteStrip(l, quote),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildWeatherCard(l)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassCard(
                        icon: _playerState == PlayerState.playing
                            ? Icons.notifications_active
                            : Icons.alarm,
                        title: _playerState == PlayerState.playing
                            ? l.t('alarmRinging')
                            : l.t('alarm'),
                        value:
                        '${two(widget.alarmHour)}:${two(widget.alarmMinute)}',
                        subtitle: l.t('dailyAlarm'),
                        onTap: widget.onOpenAlarm,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackground(bool night) {
    final path = widget.wallpaper;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          key: ValueKey(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultBackground(night),
        );
      }
    }
    return _defaultBackground(night);
  }

  Widget _defaultBackground(bool night) {
    return Image.asset(
      kDefaultWallpaper,
      key: const ValueKey('default-wallpaper'),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7FB9FF), Color(0xFFA8D8B9), Color(0xFF4C6FFF)],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClock(L10n l) {
    return Column(
      key: const ValueKey('clock'),
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${two(_now.hour)}:${two(_now.minute)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 74,
                  height: 1,
                  letterSpacing: -2,
                  fontWeight: FontWeight.w200,
                ),
              ),
              Text(
                ':${two(_now.second)}',
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${_now.year}-${two(_now.month)}-${two(_now.day)} ${wdFull(_now.weekday, l.lang)}',
          style: const TextStyle(
            color: Color(0xB3FFFFFF),
            fontSize: 13,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.touch_app_outlined,
              size: 12,
              color: Color(0x80FFFFFF),
            ),
            const SizedBox(width: 4),
            Text(
              l.t(_showCalendar ? 'tapTime' : 'tapCalendar'),
              style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuoteStrip(L10n l, String quote) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.favorite,
                size: 13,
                color: Color(0xFFFFB4C1),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  quote,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l.t('moodShare'),
                onPressed: () => showMoodCard(context, initialText: quote),
                icon: const Icon(
                  Icons.ios_share_rounded,
                  size: 16,
                  color: Color(0xAAFFFFFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard(L10n l) {
    return ListenableBuilder(
      listenable: widget.weather,
      builder: (context, _) {
        final data = widget.weather.snapshot;

        if (data == null) {
          return GlassCard(
            icon: Icons.wb_cloudy_outlined,
            title: l.t('weather'),
            value: l.t(
              widget.weather.error == WeatherError.api
                  ? 'wUnavailable'
                  : 'wNetwork',
            ),
            subtitle: l.t('wRetry'),
            onTap: () => showWeatherSheet(context, widget.weather),
          );
        }

        return GlassCard(
          icon: Icons.wb_cloudy_outlined,
          title: l.t('weather'),
          value: '${data.now.temp}°C  ${weatherDesc(data.now.desc, l.lang)}',
          subtitle:
          '${l.t('humidity')} ${data.now.humidity}% · ${data.now.windDir} ${data.now.windPower}',
          onTap: () => showWeatherSheet(context, widget.weather),
        );
      },
    );
  }
}

// =============================================================================
// 19. 天气页
// =============================================================================

class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key, required this.weather});

  final WeatherController weather;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    return SafeArea(
      child: ListenableBuilder(
        listenable: weather,
        builder: (context, _) {
          final data = weather.snapshot;

          return RefreshIndicator(
            onRefresh: () => weather.refresh(force: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.t('wDetail'),
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.t('wSource'),
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (weather.loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (data == null && weather.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (data == null)
                  WeatherErrorBox(
                    error: weather.error,
                    onRetry: () => weather.refresh(force: true),
                  )
                else ...[
                    GlassCard(
                      icon: Icons.wb_sunny_outlined,
                      title: l.t('wCurrent'),
                      value:
                      '${data.now.temp}°C  ${weatherDesc(data.now.desc, l.lang)}',
                      subtitle: '${data.now.city} · ${data.now.reportTime}',
                      onImage: false,
                    ),
                    const SizedBox(height: 14),
                    WeatherMetrics(snapshot: data),
                    if (data.hours.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        l.t('wHourly'),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      HourStrip(hours: data.hours),
                    ],
                    if (data.days.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        l.t('wDaily'),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DailyList(days: data.days),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      l.t('wExtras'),
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.28),
                        fontSize: 9,
                      ),
                    ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// 20. 日历页（国家下拉 + 只显示该国节日）
// =============================================================================

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    final store = AppStore.I;
    final country = store.countryCode;

    final monthHolidays = holidayEngine.forMonth(
      _focusedDay.year,
      _focusedDay.month,
      country,
    );
    final days = monthHolidays.keys.toList()..sort();
    final dayHolidays = holidayEngine.forDate(_selectedDay, country);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.t('calendarTitle'),
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ymd(_selectedDay)} ${wdFull(_selectedDay.weekday, l.lang)}',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime.now();
                    _selectedDay = DateTime.now();
                  });
                },
                child: Text(l.t('today')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l.t('country'),
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.45),
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: country,
                isExpanded: true,
                borderRadius: BorderRadius.circular(18),
                dropdownColor: cs.surfaceContainerHigh,
                icon: Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
                style: TextStyle(color: cs.onSurface, fontSize: 13),
                items: [
                  for (final item in kCountries)
                    DropdownMenuItem<String>(
                      value: item.code,
                      child: Row(
                        children: [
                          Text(item.flag, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.nativeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) AppStore.I.setCountry(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month - 1,
                            1,
                          );
                        });
                      },
                      icon: Icon(
                        Icons.chevron_left,
                        size: 18,
                        color: cs.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          monthLabel(_focusedDay, l.lang),
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month + 1,
                            1,
                          );
                        });
                      },
                      icon: Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                TableCalendar<Holiday>(
                  firstDay: DateTime.utc(1970, 1, 1),
                  lastDay: DateTime.utc(2100, 12, 31),
                  focusedDay: _focusedDay,
                  headerVisible: false,
                  rowHeight: 40,
                  daysOfWeekHeight: 22,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {CalendarFormat.month: ''},
                  eventLoader: (day) => holidayEngine.forDate(day, country),
                  selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    });
                  },
                  onPageChanged: (focused) {
                    setState(() => _focusedDay = focused);
                  },
                  calendarStyle: CalendarStyle(
                    outsideDaysVisible: false,
                    cellMargin: const EdgeInsets.all(2),
                    defaultTextStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                    weekendTextStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                    todayDecoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.28),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 13,
                    ),
                  ),
                  calendarBuilders: CalendarBuilders<Holiday>(
                    dowBuilder: (c, day) {
                      return Center(
                        child: Text(
                          wdShort(day.weekday, l.lang),
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.35),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                    markerBuilder: (c, day, events) {
                      if (events.isEmpty) return null;
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFB74D),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (dayHolidays.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.celebration_outlined,
                    size: 16,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dayHolidays.map((h) => h.nameFor(l.lang)).join(' · '),
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            l.t('holidaysMonth'),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (days.isEmpty)
            Text(
              l.t('noHolidays'),
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            )
          else
            for (final day in days)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final holiday in monthHolidays[day]!)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      holiday.nameFor(l.lang),
                                      style: TextStyle(
                                        color: cs.onSurface
                                            .withValues(alpha: 0.85),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    countryByCode(holiday.country).flag,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// =============================================================================
// 21. 树洞：模型与真人聊天控制器
// =============================================================================

enum TreeMode { human, ai }

enum HumanPhase {
  idle,
  searching,
  consent,
  waitingPeer,
  connected,
  ended,
  error
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.mine,
    required this.at,
    this.system = false,
  });

  final String text;
  final bool mine;
  final DateTime at;
  final bool system;
}

class HumanChatController extends ChangeNotifier {
  HumanPhase phase = HumanPhase.idle;
  String? errorKey;
  String? peerAlias;
  String? peerMeta;
  bool peerTyping = false;
  final List<ChatMessage> messages = [];

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _timeout;
  String? _requestId;
  bool _localAccepted = false;
  bool _disposed = false;

  bool get serverConfigured => kTreeHoleApiBase.trim().isNotEmpty;

  Future<void> findMatch() async {
    if (phase == HumanPhase.searching) return;

    if (!serverConfigured) {
      phase = HumanPhase.error;
      errorKey = 'needServer';
      _safeNotify();
      return;
    }

    _resetConnection();
    phase = HumanPhase.searching;
    errorKey = null;
    peerAlias = null;
    peerMeta = null;
    peerTyping = false;
    _localAccepted = false;
    messages.clear();
    _safeNotify();

    try {
      final base = kTreeHoleApiBase.replaceAll(RegExp(r'/$'), '');
      final response = await http
          .post(
        Uri.parse('$base/v1/match'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'anonId': AppStore.I.anonId,
          'lang': AppStore.I.langCode,
          'country': AppStore.I.countryCode,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final map =
      decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final wsUrl = map['ws'] as String?;
      final token = map['token'] as String?;
      _requestId = map['requestId'] as String?;

      if (wsUrl == null || token == null) {
        throw Exception('bad match response');
      }

      final baseUri = Uri.parse(wsUrl);
      final uri = baseUri.replace(
        queryParameters: {
          ...baseUri.queryParameters,
          'token': token,
          'anonId': AppStore.I.anonId,
        },
      );

      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 15));
      _channel = channel;
      _sub = channel.stream.listen(
        _onEvent,
        onDone: _onDone,
        onError: (Object error) {
          debugPrint('tree hole socket error: $error');
          _onError();
        },
      );

      _timeout = Timer(const Duration(seconds: 60), () {
        if (phase == HumanPhase.searching) {
          phase = HumanPhase.error;
          errorKey = 'wNetwork';
          _resetConnection();
          _safeNotify();
        }
      });
    } catch (e) {
      debugPrint('match failed: $e');
      phase = HumanPhase.error;
      errorKey = serverConfigured ? 'wNetwork' : 'needServer';
      _safeNotify();
    }
  }

  void accept() {
    if (phase != HumanPhase.consent) return;
    _localAccepted = true;
    phase = HumanPhase.waitingPeer;
    _send({'type': 'consent_accept', 'requestId': _requestId});
    _safeNotify();
  }

  void send(String text) {
    if (phase != HumanPhase.connected || text.trim().isEmpty) return;
    messages.add(
      ChatMessage(text: text, mine: true, at: DateTime.now()),
    );
    _send({'type': 'message', 'text': text});
    _safeNotify();
  }

  void cancel() {
    _resetConnection();
    phase = HumanPhase.idle;
    errorKey = null;
    peerAlias = null;
    peerMeta = null;
    peerTyping = false;
    messages.clear();
    _safeNotify();
  }

  void leave() {
    _send({'type': 'leave'});
    cancel();
  }

  void _send(Map<String, Object?> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('socket send failed: $e');
    }
  }

  void _onEvent(dynamic raw) {
    if (_disposed) return;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'];

      switch (type) {
        case 'matched':
          final peer = decoded['peer'];
          if (peer is Map) {
            peerAlias = peer['alias']?.toString();
            peerMeta = peer['meta']?.toString();
          }
          peerTyping = false;
          _timeout?.cancel();
          phase = HumanPhase.consent;
          break;
        case 'waiting':
          phase = HumanPhase.searching;
          break;
        case 'consent_accepted':
          if (_localAccepted) phase = HumanPhase.connected;
          break;
        case 'connected':
          phase = HumanPhase.connected;
          _timeout?.cancel();
          break;
        case 'message':
          final text = decoded['text'] as String? ?? '';
          if (text.isNotEmpty) {
            messages.add(
              ChatMessage(text: text, mine: false, at: DateTime.now()),
            );
          }
          peerTyping = false;
          break;
        case 'typing':
          peerTyping = decoded['on'] == true;
          break;
        case 'peer_left':
          phase = HumanPhase.ended;
          peerTyping = false;
          break;
        case 'error':
          errorKey = 'wNetwork';
          phase = HumanPhase.error;
          break;
        default:
          break;
      }
      _safeNotify();
    } catch (e) {
      debugPrint('socket event parse failed: $e');
    }
  }

  void _onDone() {
    if (_disposed) return;
    if (phase == HumanPhase.connected ||
        phase == HumanPhase.consent ||
        phase == HumanPhase.waitingPeer) {
      phase = HumanPhase.ended;
      _safeNotify();
    }
  }

  void _onError() {
    if (_disposed) return;
    if (phase != HumanPhase.ended) {
      phase = HumanPhase.error;
      errorKey = 'wNetwork';
      _safeNotify();
    }
  }

  void _resetConnection() {
    _timeout?.cancel();
    _timeout = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {
      // ignore
    }
    _channel = null;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _resetConnection();
    super.dispose();
  }
}

// =============================================================================
// 22. 树洞页面
// =============================================================================

class TreeHolePage extends StatefulWidget {
  const TreeHolePage({super.key});

  @override
  State<TreeHolePage> createState() => _TreeHolePageState();
}

class _TreeHolePageState extends State<TreeHolePage> {
  final HumanChatController _human = HumanChatController();
  TreeMode _mode = TreeMode.human;
  bool _showEmergency = false;

  @override
  void dispose() {
    _human.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    final store = AppStore.I;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomPad = keyboard ? 8.0 : 84.0;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(top: 12, bottom: bottomPad),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.t('treeTitle'),
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l.t('treeSub'),
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l.t('moodTitle'),
                    onPressed: () => showMoodCard(context),
                    icon: Icon(
                      Icons.ios_share_rounded,
                      size: 19,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  IconButton(
                    tooltip: l.t('emergencyTitle'),
                    onPressed: () {
                      setState(() => _showEmergency = !_showEmergency);
                    },
                    icon: Icon(
                      Icons.favorite_rounded,
                      size: 20,
                      color: _showEmergency
                          ? const Color(0xFFFF6B81)
                          : cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              child: _showEmergency
                  ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: EmergencyBanner(
                  country: store.countryCode,
                  onClose: () => setState(() => _showEmergency = false),
                ),
              )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ModeSwitch(
                mode: _mode,
                onChanged: (mode) => setState(() => _mode = mode),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: IndexedStack(
                index: _mode.index,
                sizing: StackFit.expand,
                children: [
                  HumanChatView(controller: _human),
                  const AiChatView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final TreeMode mode;
  final ValueChanged<TreeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    Widget item(TreeMode value, String label, IconData icon) {
      final active = mode == value;
      final fg = active ? cs.surface : cs.onSurface.withValues(alpha: 0.55);
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? cs.onSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          item(TreeMode.human, l.t('modeHuman'), Icons.people_alt_outlined),
          item(TreeMode.ai, l.t('modeAi'), Icons.auto_awesome_outlined),
        ],
      ),
    );
  }
}

// =============================================================================
// 23. 真人聊天视图
// =============================================================================

class HumanChatView extends StatelessWidget {
  const HumanChatView({super.key, required this.controller});

  final HumanChatController controller;

  Future<bool> _sendHuman(BuildContext context, String text) async {
    final hit = RiskGuard.scan(text);
    if (hit != null) {
      await showRiskDialog(
        context,
        hit,
        message: text,
        source: 'tree_hole.human',
      );
      return false;
    }
    controller.send(text);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.phase) {
          case HumanPhase.idle:
            return _HumanIntro(
              onStart: controller.findMatch,
            );
          case HumanPhase.searching:
            return _CenteredState(
              icon: Icons.radar_rounded,
              title: l.t('matching'),
              subtitle: l.t('humanIntroSub'),
              loading: true,
              actionLabel: l.t('cancelMatch'),
              onAction: controller.cancel,
            );
          case HumanPhase.consent:
            return _ConsentState(controller: controller);
          case HumanPhase.waitingPeer:
            return _CenteredState(
              icon: Icons.hourglass_top_rounded,
              title: l.t('requestSent'),
              subtitle: l.t('waitingConsentSub'),
              loading: true,
              actionLabel: l.t('cancelMatch'),
              onAction: controller.cancel,
            );
          case HumanPhase.connected:
            return _ConnectedChat(
              controller: controller,
              onSend: (text) => _sendHuman(context, text),
            );
          case HumanPhase.ended:
            return _CenteredState(
              icon: Icons.nights_stay_outlined,
              title: l.t('peerLeft'),
              subtitle: l.t('treeEmpty'),
              actionLabel: l.t('startMatch'),
              onAction: controller.findMatch,
            );
          case HumanPhase.error:
            final needsServer = controller.errorKey == 'needServer';
            return _CenteredState(
              icon: needsServer ? Icons.dns_outlined : Icons.wifi_off_rounded,
              title: l.t(needsServer ? 'needServer' : 'wNetwork'),
              subtitle: l.t(needsServer ? 'needServerSub' : 'wRetry'),
              actionLabel: l.t(needsServer ? 'retry' : 'retry'),
              onAction: controller.findMatch,
            );
        }
      },
    );
  }
}

class _HumanIntro extends StatelessWidget {
  const _HumanIntro({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_alt_outlined,
                size: 34,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l.t('humanIntro'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.t('humanIntroSub'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: Text(l.t('startMatch')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentState extends StatelessWidget {
  const _ConsentState({required this.controller});

  final HumanChatController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    final rawAlias = controller.peerAlias?.trim() ?? '';
    final alias = rawAlias.isEmpty ? l.t('anon') : rawAlias;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primary.withValues(alpha: 0.14),
                child: Text(
                  initialOf(alias),
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                alias,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (controller.peerMeta != null) ...[
                const SizedBox(height: 3),
                Text(
                  controller.peerMeta!,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                l.t('waitingConsent'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l.t('waitingConsentSub'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: controller.accept,
                  child: Text(l.t('sendRequest')),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: controller.cancel,
                child: Text(l.t('cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.loading = false,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool loading;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            else
              Icon(icon, size: 44, color: cs.onSurface.withValues(alpha: 0.28)),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.48),
                fontSize: 12,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedChat extends StatelessWidget {
  const _ConnectedChat({required this.controller, required this.onSend});

  final HumanChatController controller;
  final ChatSendHandler onSend;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    final rawAlias = controller.peerAlias?.trim() ?? '';
    final alias = rawAlias.isEmpty ? l.t('anon') : rawAlias;

    final items = <Widget>[
      if (controller.peerTyping) const TypingBubble(),
      for (final message in controller.messages.reversed)
        ChatBubble(message: message),
    ];

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: cs.primary.withValues(alpha: 0.14),
                child: Text(
                  initialOf(alias),
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alias,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      l.t('connected'),
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: controller.leave,
                child: Text(
                  l.t('leaveChat'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                l.t('chatEmptyHuman'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 13,
                  height: 1.8,
                ),
              ),
            ),
          )
              : ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            itemCount: items.length,
            itemBuilder: (context, index) => items[index],
          ),
        ),
        ChatComposer(
          hint: l.t('chatInputHuman'),
          onSend: onSend,
        ),
      ],
    );
  }
}

// =============================================================================
// 24. AI 树洞视图（无假兜底）
// =============================================================================

class AiChatView extends StatefulWidget {
  const AiChatView({super.key});

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _sending = false;
  bool _failed = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<bool> _send(String text) async {
    if (_sending) return false;

    final hit = RiskGuard.scan(text);
    if (hit != null) {
      await showRiskDialog(
        context,
        hit,
        message: text,
        source: 'tree_hole.ai',
      );
      return false;
    }

    setState(() {
      _messages.add(
        ChatMessage(text: text, mine: true, at: DateTime.now()),
      );
      _sending = true;
      _failed = false;
    });
    _scrollToBottom();
    unawaited(_requestReply());
    return true;
  }

  Future<void> _requestReply() async {
    setState(() {
      _sending = true;
      _failed = false;
      while (_messages.isNotEmpty && _messages.last.system) {
        _messages.removeLast();
      }
    });

    final l = context.l10n;

    try {
      final reply = await _askOllama();
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(text: reply, mine: false, at: DateTime.now()),
        );
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: l.t('aiTimeout'),
            mine: false,
            at: DateTime.now(),
            system: true,
          ),
        );
        _failed = true;
      });
    } catch (e) {
      debugPrint('ollama failed: $e');
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: '${l.t('aiError')}\n${l.t('aiErrorHint')}',
            mine: false,
            at: DateTime.now(),
            system: true,
          ),
        );
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<String> _askOllama() async {
    final recent = _messages.where((m) => !m.system).toList();
    final slice =
    recent.length > 10 ? recent.sublist(recent.length - 10) : recent;

    final buffer = StringBuffer();
    for (final message in slice) {
      buffer.writeln(
        '${message.mine ? 'User' : 'Hollow'}: ${message.text}',
      );
    }
    buffer.writeln('Hollow:');

    final response = await http
        .post(
      Uri.parse('$kOllamaBaseUrl/api/generate'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': kOllamaModel,
        'system': kTreeHoleSystemPrompt,
        'prompt': buffer.toString(),
        'stream': false,
        'think': false,
        'keep_alive': '30m',
        'options': {
          'temperature': 0.85,
          'top_p': 0.9,
          'num_predict': 120,
        },
      }),
    )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final reply = (data['response'] as String? ?? '').trim();
    if (reply.isEmpty) throw Exception('empty response');

    return reply;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyHint(l, cs)
              : ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: _messages.length + (_sending ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _messages.length) {
                return const TypingBubble();
              }
              return ChatBubble(message: _messages[index]);
            },
          ),
        ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _sending ? null : _requestReply,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(l.t('retry')),
                ),
              ],
            ),
          ),
        ChatComposer(
          hint: l.t('aiInputHint'),
          onSend: _send,
        ),
      ],
    );
  }

  Widget _buildEmptyHint(L10n l, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.spa_outlined, size: 44, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              l.t('aiEmpty'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.7,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 25. 聊天气泡与输入框
// =============================================================================

typedef ChatSendHandler = Future<bool> Function(String text);

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;

    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.45),
            fontSize: 11,
            height: 1.6,
          ),
        ),
      );
    }

    final mine = message.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: mine ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: mine ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.hint,
    required this.onSend,
  });

  final String hint;
  final ChatSendHandler onSend;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() => _busy = true);
    final sent = await widget.onSend(text);
    if (!mounted) return;
    if (sent) _controller.clear();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: TextStyle(color: cs.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.hint,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.onPrimary,
              ),
            )
                : const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 26. 紧急热线与风险弹窗
// =============================================================================

class EmergencyBanner extends StatelessWidget {
  const EmergencyBanner({
    super.key,
    required this.country,
    required this.onClose,
  });

  final String country;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    final hotlines = hotlinesFor(country);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B81).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF6B81).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                size: 16,
                color: Color(0xFFFF6B81),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.t('emergencyTitle'),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.t('emergencySub'),
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontSize: 10,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          for (final hotline in hotlines)
            _HotlineTile(hotline: hotline, compact: true),
        ],
      ),
    );
  }
}

class _HotlineTile extends StatelessWidget {
  const _HotlineTile({required this.hotline, this.compact = false});

  final Hotline hotline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hotline.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontSize: compact ? 10.5 : 12,
                  ),
                ),
                Text(
                  hotline.number,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => callHotline(context, hotline.number),
            icon: const Icon(Icons.call_outlined, size: 14),
            label: Text(
              l.t('emergencyCall'),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> callHotline(BuildContext context, String number) async {
  final dial = number.replaceAll(RegExp(r'[^0-9+]'), '');
  try {
    final ok = await launchUrl(Uri(scheme: 'tel', path: dial));
    if (ok) return;
  } catch (_) {
    // 桌面端或不支持电话时，退回复制
  }
  await Clipboard.setData(ClipboardData(text: number));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(context.t('emergencyCopied'))),
    );
}

Future<void> showRiskDialog(
    BuildContext context,
    RiskHit hit, {
      required String message,
      required String source,
    }) async {
  await RiskLogger.critical(
    hit,
    message,
    source: source,
    lang: AppStore.I.langCode,
    country: AppStore.I.countryCode,
  );

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final l = ctx.l10n;
      final cs = ctx.cs;
      final hotlines = hotlinesFor(AppStore.I.countryCode);

      return PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFF6B81),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.t('riskTitle'),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.t('riskBody'),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontSize: 12.5,
                    height: 1.75,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B81).withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFF6B81).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.t('riskHotline'),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      for (final hotline in hotlines)
                        _HotlineTile(hotline: hotline, compact: true),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l.t('riskLogged'),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.32),
                    fontSize: 9,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.t('riskStay')),
            ),
          ],
        ),
      );
    },
  );
}

// =============================================================================
// 27. 设置页
// =============================================================================

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onOpenAlarm});

  final VoidCallback onOpenAlarm;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<int> _directorySize(Directory dir) async {
    var total = 0;
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          continue;
        }
      }
    }
    return total;
  }

  Future<void> _refreshCacheSize() async {
    try {
      final dir = await getTemporaryDirectory();
      final size = await _directorySize(dir);
      if (mounted) setState(() => _cacheBytes = size);
    } catch (_) {
      if (mounted) setState(() => _cacheBytes = 0);
    }
  }

  Future<String> _persist(String source, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final dot = source.lastIndexOf('.');
    final ext = dot >= 0 ? source.substring(dot) : '';
    final target = File(
      '${dir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await File(source).copy(target.path);
    return target.path;
  }

  Future<String?> _pickFile(FileType type) async {
    final result = await FilePicker.platform.pickFiles(type: type);
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.path;
  }

  Future<void> _pickWallpaper() async {
    try {
      final path = await _pickFile(FileType.image);
      if (path == null) return;
      final saved = await _persist(path, 'wallpaper');
      await AppStore.I.setWallpaper(saved);
      if (mounted) _snack(context.t('wallpaperLocal'));
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _pickRingtone() async {
    try {
      final path = await _pickFile(FileType.audio);
      if (path == null) return;
      final saved = await _persist(path, 'ringtone');
      await AppStore.I.setRingtone(saved);
      if (mounted) _snack(context.t('ringtoneLocal'));
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _clearCache() async {
    final store = AppStore.I;
    final keep = <String>{};
    if (store.wallpaper != null) keep.add(store.wallpaper!);
    if (store.ringtone != null) keep.add(store.ringtone!);

    try {
      final directories = <Directory>[
        await getTemporaryDirectory(),
        await getApplicationDocumentsDirectory(),
      ];
      for (final dir in directories) {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          if (keep.contains(entity.path)) continue;
          try {
            await entity.delete();
          } catch (_) {
            continue;
          }
        }
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (mounted) {
        setState(() => _cacheBytes = 0);
        _snack(context.t('cacheCleared'));
      }
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _pickLanguage() async {
    final store = AppStore.I;
    await showAppSheet<void>(context, (ctx) {
      final l = ctx.l10n;
      final options = <List<String>>[
        ['system', l.t('followSystem')],
        ['zh', '中文'],
        ['en', 'English'],
        ['ja', '日本語'],
        ['de', 'Deutsch'],
        ['es', 'Español'],
        ['fr', 'Français'],
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(l.t('language')),
          for (final option in options)
            ListTile(
              title: Text(
                option[1],
                style: TextStyle(color: ctx.cs.onSurface),
              ),
              trailing: store.localeCode == option[0]
                  ? Icon(Icons.check, size: 18, color: ctx.cs.primary)
                  : null,
              onTap: () async {
                await store.setLocale(option[0]);
                await AppNotifications.instance.sync(
                  lang: store.langCode,
                  enabled: store.notificationsEnabled,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 10),
        ],
      );
    });
  }

  Future<void> _pickTheme() async {
    final store = AppStore.I;
    await showAppSheet<void>(context, (ctx) {
      final l = ctx.l10n;
      final options = <List<String>>[
        ['dark', l.t('themeDark')],
        ['light', l.t('themeLight')],
        ['system', l.t('themeSystem')],
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(l.t('theme')),
          for (final option in options)
            ListTile(
              title: Text(
                option[1],
                style: TextStyle(color: ctx.cs.onSurface),
              ),
              trailing: store.themeCode == option[0]
                  ? Icon(Icons.check, size: 18, color: ctx.cs.primary)
                  : null,
              onTap: () async {
                await store.setTheme(option[0]);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 10),
        ],
      );
    });
  }

  Future<void> _pickFont() async {
    final store = AppStore.I;
    await showAppSheet<void>(context, (ctx) {
      final l = ctx.l10n;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(l.t('font')),
          for (final font in AppFont.values)
            ListTile(
              title: Text(
                font.label(l),
                style: TextStyle(
                  color: ctx.cs.onSurface,
                  fontFamily: font.family,
                  fontFamilyFallback: font.fallbacks,
                ),
              ),
              subtitle: Text(
                'Aa 你好 こんにちは Bonjour',
                style: TextStyle(
                  color: ctx.cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontFamily: font.family,
                  fontFamilyFallback: font.fallbacks,
                ),
              ),
              trailing: store.fontCode == font.name
                  ? Icon(Icons.check, size: 18, color: ctx.cs.primary)
                  : null,
              onTap: () async {
                await store.setFont(font.name);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 10),
        ],
      );
    });
  }

  Future<void> _pickCountry() async {
    final store = AppStore.I;
    await showAppSheet<void>(context, (ctx) {
      final l = ctx.l10n;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(l.t('selectCountry')),
          for (final country in kCountries)
            ListTile(
              leading: Text(country.flag, style: const TextStyle(fontSize: 20)),
              title: Text(
                country.nativeName,
                style: TextStyle(color: ctx.cs.onSurface),
              ),
              trailing: store.countryCode == country.code
                  ? Icon(Icons.check, size: 18, color: ctx.cs.primary)
                  : null,
              onTap: () async {
                await store.setCountry(country.code);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 10),
        ],
      );
    });
  }

  Future<void> _toggleNotifications() async {
    final store = AppStore.I;
    final next = !store.notificationsEnabled;
    final l = context.l10n;

    if (next) {
      final granted = await AppNotifications.instance.requestPermission();
      if (!granted) {
        if (mounted) _snack(l.t('notifyPermission'));
        return;
      }
    }

    await store.setNotifications(next);
    await AppNotifications.instance.sync(
      lang: store.langCode,
      enabled: next,
    );
    if (mounted) _snack(next ? l.t('notifOn') : l.t('notifOff'));
  }

  Future<void> _editBirthday() async {
    final store = AppStore.I;
    if (!store.canEditBirthday) {
      _snack(context.t('bLocked'));
      return;
    }
    final value = await showBirthdayDialog(
      context,
      initial: store.birthday,
      allowCancel: true,
    );
    if (value == null) return;
    await store.setBirthday(value);
    if (mounted) _snack(value);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    final store = AppStore.I;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          Text(
            l.t('settingsTitle'),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.t('settingsSub'),
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          SettingsTile(
            icon: Icons.translate,
            title: l.t('language'),
            value: store.localeCode == 'system'
                ? l.t('followSystem')
                : const {
              'zh': '中文',
              'en': 'English',
              'ja': '日本語',
              'de': 'Deutsch',
              'es': 'Español',
              'fr': 'Français',
            }[store.localeCode] ??
                store.localeCode,
            onTap: _pickLanguage,
          ),
          SettingsTile(
            icon: Icons.flag_outlined,
            title: l.t('country'),
            value: '${store.country.flag} ${store.country.nativeName}',
            onTap: _pickCountry,
          ),
          SettingsTile(
            icon: Icons.brightness_6_outlined,
            title: l.t('theme'),
            value: store.themeCode == 'light'
                ? l.t('themeLight')
                : store.themeCode == 'system'
                ? l.t('themeSystem')
                : l.t('themeDark'),
            onTap: _pickTheme,
          ),
          SettingsTile(
            icon: Icons.text_fields_rounded,
            title: l.t('font'),
            value: store.appFont.label(l),
            onTap: _pickFont,
          ),
          SettingsTile(
            icon: Icons.notifications_none_rounded,
            title: l.t('notifyTitle'),
            value: l.t(store.notificationsEnabled ? 'notifOn' : 'notifOff'),
            footnote: l.t('notifyHint'),
            onTap: _toggleNotifications,
          ),
          SettingsTile(
            icon: Icons.alarm,
            title: l.t('alarm'),
            value:
            '${two(store.alarmHour)}:${two(store.alarmMinute)} · ${l.t('dailyAlarm')}',
            onTap: widget.onOpenAlarm,
          ),
          SettingsTile(
            icon: Icons.cake_outlined,
            title: l.t('birthday'),
            value: store.birthday ?? l.t('notSet'),
            footnote: store.canEditBirthday ? null : l.t('bLocked'),
            actionLabel: store.canEditBirthday ? l.t('edit') : null,
            onTap: store.canEditBirthday ? _editBirthday : null,
          ),
          SettingsTile(
            icon: Icons.wallpaper_outlined,
            title: l.t('wallpaper'),
            value: store.wallpaper == null
                ? l.t('wallpaperDefault')
                : l.t('wallpaperLocal'),
            buttons: [
              (l.t('changeWallpaper'), _pickWallpaper),
              (l.t('resetDefault'), () => AppStore.I.setWallpaper(null)),
            ],
          ),
          SettingsTile(
            icon: Icons.music_note_outlined,
            title: l.t('ringtone'),
            value: store.ringtone == null
                ? l.t('ringtoneDefault')
                : l.t('ringtoneLocal'),
            buttons: [
              (l.t('changeRingtone'), _pickRingtone),
              (l.t('resetDefault'), () => AppStore.I.setRingtone(null)),
            ],
          ),
          SettingsTile(
            icon: Icons.cleaning_services_outlined,
            title: l.t('clearCache'),
            value: '${l.t('cacheSize')} ${bytesLabel(_cacheBytes)}',
            actionLabel: l.t('clearCache'),
            onTap: _clearCache,
          ),
          SettingsTile(
            icon: Icons.shield_outlined,
            title: l.t('privacy'),
            value: l.t('privacyBody'),
          ),
          SettingsTile(
            icon: Icons.info_outline_rounded,
            title: l.t('about'),
            value: l.t('aboutSub'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AboutPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Not alone $kAppVersion',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.22),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
    this.actionLabel,
    this.footnote,
    this.buttons,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final String? actionLabel;
  final String? footnote;
  final List<(String, VoidCallback)>? buttons;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: onTap,
                  child: Text(
                    actionLabel!,
                    style: TextStyle(color: cs.primary, fontSize: 12),
                  ),
                )
              else if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: 0.35),
                ),
            ],
          ),
          const SizedBox(height: 5),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    footnote!,
                    style: TextStyle(
                      color: cs.primary.withValues(alpha: 0.8),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (buttons != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final button in buttons!)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.onSurface,
                            side: BorderSide(
                              color: cs.onSurface.withValues(alpha: 0.18),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: button.$2,
                          child: Text(
                            button.$1,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// 28. 关于页与开发者彩蛋
// =============================================================================

const Map<String, String> kDeveloperMotto = {
  'zh': '死亡只会杀死你的一天，而焦虑会杀死你的每一天。',
  'en': 'Death only kills one of your days; anxiety kills every one of them.',
  'ja': '死はあなたの一日を奪うだけだが、不安はあなたの毎日を奪う。',
  'de':
  'Der Tod tötet nur einen deiner Tage; die Angst tötet jeden deiner Tage.',
  'es': 'La muerte solo mata uno de tus días; la ansiedad mata todos tus días.',
  'fr':
  'La mort ne tue qu’un seul de tes jours ; l’angoisse tue chacun de tes jours.',
};

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  int _taps = 0;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _onVersionTap() {
    _resetTimer?.cancel();
    _taps++;

    if (_taps >= 3) {
      _taps = 0;
      _unlockEgg();
      return;
    }

    _resetTimer = Timer(const Duration(milliseconds: 1600), () {
      _taps = 0;
    });
  }

  Future<void> _unlockEgg() async {
    final next = min(AppStore.I.eggStage + 1, 3);
    await AppStore.I.setEggStage(next);
    if (!mounted) return;

    switch (next) {
      case 1:
        await _showEggOne();
        break;
      case 2:
        await _showEggTwo();
        break;
      default:
        await _showEggThree();
        break;
    }
  }

  Future<void> _showEggOne() {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final l = ctx.l10n;
        return _EggShell(
          title: l.t('developer'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: Color(0x226E8BFF),
                child: Icon(
                  Icons.code_rounded,
                  size: 28,
                  color: Color(0xFF8EC5FF),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                kDeveloperName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.t('eggUnlocked'),
                style: const TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEggTwo() {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final l = ctx.l10n;
        final current = l.lang;
        return _EggShell(
          title: l.t('devMottoTitle'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  kDeveloperMotto[current] ?? kDeveloperMotto['en']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.t('allLanguages'),
                style: const TextStyle(
                  color: Color(0x66FFFFFF),
                  fontSize: 10,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in kDeveloperMotto.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          entry.key.toUpperCase(),
                          style: TextStyle(
                            color: entry.key == current
                                ? const Color(0xFF8EC5FF)
                                : const Color(0x66FFFFFF),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            color: entry.key == current
                                ? Colors.white
                                : const Color(0x99FFFFFF),
                            fontSize: 11,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEggThree() {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final l = ctx.l10n;
        return _EggShell(
          title: l.t('devSecretTitle'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.t('devSecretHint'),
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 12,
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 16),
              const DeveloperSecretSlot(),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    final store = AppStore.I;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('about')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
        children: [
          const Center(child: AppLogo(size: 76)),
          const SizedBox(height: 20),
          Center(
            child: Text(
              l.t('app'),
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              l.t('aboutSub'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 28),
          _AboutRow(
            label: l.t('version'),
            value: kAppVersion,
            valueKey: const ValueKey('version-tap'),
            onTap: _onVersionTap,
          ),
          _AboutRow(
            label: l.t('developer'),
            value: store.eggStage >= 1 ? kDeveloperName : '•••',
          ),
          _AboutRow(
            label: l.t('country'),
            value: '${store.country.flag} ${store.country.nativeName}',
          ),
          _AboutRow(
            label: l.t('font'),
            value: store.appFont.label(l),
          ),
          const SizedBox(height: 30),
          Text(
            'Made with care.\nNot alone $kAppVersion',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.25),
              fontSize: 10,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.label,
    required this.value,
    this.onTap,
    this.valueKey,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              value,
              key: valueKey,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EggShell extends StatelessWidget {
  const _EggShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF121620),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6E8BFF).withValues(alpha: 0.18),
              blurRadius: 50,
              spreadRadius: 4,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              child,
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// 彩蛋三：这里是留给开发者自己的位置。
///
/// 使用方式：把下面 `return Container(...)` 整段替换成你的 Widget。
/// 例如：
///   return const Text(
///     '你的秘密',
///     style: TextStyle(color: Colors.white),
///   );
/// 不需要改其它任何文件。
/// ============================================================================
class DeveloperSecretSlot extends StatelessWidget {
  const DeveloperSecretSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        '// TODO: write your secret here\n// ZephyrSeeker',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: cs.primary.withValues(alpha: 0.65),
          fontSize: 11,
          height: 1.8,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

// =============================================================================
// 29. 关怀 / 生日弹窗
// =============================================================================

Future<void> showCareDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: ctx.cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.favorite_rounded,
                color: Color(0xFFFF8A9B),
                size: 26,
              ),
              const SizedBox(height: 16),
              Text(
                ctx.t('careBody'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ctx.cs.onSurface.withValues(alpha: 0.8),
                  fontSize: 14,
                  height: 1.9,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ctx.cs.onSurface,
                    foregroundColor: ctx.cs.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    ctx.t('agree'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<String?> showBirthdayDialog(
    BuildContext context, {
      String? initial,
      bool allowCancel = false,
    }) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return PopScope(
        canPop: allowCancel,
        child: BirthdayDialog(initial: initial, allowCancel: allowCancel),
      );
    },
  );
}

class BirthdayDialog extends StatefulWidget {
  const BirthdayDialog({
    super.key,
    this.initial,
    this.allowCancel = false,
  });

  final String? initial;
  final bool allowCancel;

  @override
  State<BirthdayDialog> createState() => _BirthdayDialogState();
}

class _BirthdayDialogState extends State<BirthdayDialog> {
  late final TextEditingController _controller =
  TextEditingController(text: widget.initial ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    final parsed = parseYmd(raw);
    if (parsed == null) {
      setState(() => _error = context.t('bFormat'));
      return;
    }
    if (parsed.isAfter(DateTime.now())) {
      setState(() => _error = context.t('bFuture'));
      return;
    }
    Navigator.of(context).pop(ymd(parsed));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final parsed = parseYmd(_controller.text) ?? DateTime(1998, 6, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed.isAfter(now) ? now : parsed,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: context.t('bPick'),
      cancelText: context.t('cancel'),
      confirmText: context.t('bSave'),
    );
    if (picked == null) return;
    _controller.text = ymd(picked);
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;

    return AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        context.t('bAsk'),
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.t('bAskSub')}\n${context.t('bNote')}',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontSize: 12,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: '1998-6-1',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: context.t('bPick'),
                onPressed: _pickDate,
                icon: Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('bFormat'),
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.35),
              fontSize: 10,
              height: 1.5,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.allowCancel)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('cancel')),
          ),
        TextButton(
          onPressed: _submit,
          child: Text(
            context.t('bSave'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 30. 闹钟与起床覆盖层
// =============================================================================

Future<(int, int)?> showAlarmSheet(
    BuildContext context,
    int hour,
    int minute,
    ) {
  return showModalBottomSheet<(int, int)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AlarmSheet(hour: hour, minute: minute),
  );
}

class AlarmSheet extends StatefulWidget {
  const AlarmSheet({super.key, required this.hour, required this.minute});

  final int hour;
  final int minute;

  @override
  State<AlarmSheet> createState() => _AlarmSheetState();
}

class _AlarmSheetState extends State<AlarmSheet> {
  late int _hour = widget.hour.clamp(0, 23);
  late int _minute = widget.minute.clamp(0, 59);
  late final FixedExtentScrollController _hourController =
  FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteController =
  FixedExtentScrollController(initialItem: _minute);

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  Widget _buildWheel(
      int count,
      FixedExtentScrollController controller,
      ValueChanged<int> onChanged,
      ) {
    final color = context.cs.onSurface;
    return SizedBox(
      width: 84,
      height: 172,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 46,
        diameterRatio: 1.6,
        perspective: 0.003,
        useMagnifier: true,
        magnification: 1.2,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, index) {
            return Center(
              child: Text(
                two(index),
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('alarm'),
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildWheel(
                  24,
                  _hourController,
                      (value) => setState(() => _hour = value),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    ':',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _buildWheel(
                  60,
                  _minuteController,
                      (value) => setState(() => _minute = value),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${two(_hour)}:${two(_minute)}',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.onSurface,
                  foregroundColor: cs.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop((_hour, _minute)),
                child: Text(
                  context.t('save'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showWakeUpOverlay(BuildContext context, String quote) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'alarm',
    barrierColor: Colors.white,
    transitionDuration: const Duration(milliseconds: 420),
    transitionBuilder: (ctx, animation, _, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    pageBuilder: (ctx, _, __) {
      return Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFDF7), Colors.white, Color(0xFFFFEFD5)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x44FFB300),
                          blurRadius: 40,
                          spreadRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.wb_sunny_rounded,
                      size: 52,
                      color: Color(0xFFFFB300),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    ctx.t('ringTitle'),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A2118),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    quote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.8,
                      color: Color(0xFF6B5B49),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2A2118),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(27),
                        ),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        ctx.t('wokeUp'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

// =============================================================================
// 31. 生日蛋糕（图片版 + 吹气检测）
// =============================================================================

Future<void> showCakeDialog(BuildContext context, String birthday) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return PopScope(
        canPop: false,
        child: CakeDialog(birthday: birthday),
      );
    },
  );
}

class CakeDialog extends StatefulWidget {
  const CakeDialog({super.key, required this.birthday});

  final String birthday;

  @override
  State<CakeDialog> createState() => _CakeDialogState();
}

class _CakeDialogState extends State<CakeDialog> {
  static const int _tickMs = 80;
  static const double _thresholdDb = -22;
  static const int _needMs = 480;

  final AudioRecorder _recorder = AudioRecorder();
  final ValueNotifier<double> _meter = ValueNotifier<double>(0);

  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _tempPath;
  bool _micReady = false;
  bool _candlesOut = false;
  bool _closed = false;
  int _loudMs = 0;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    unawaited(_shutdownRecorder());
    _meter.dispose();
    super.dispose();
  }

  Future<void> _shutdownRecorder() async {
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {
      // ignore
    }
    try {
      await _recorder.dispose();
    } catch (_) {
      // ignore
    }
    final path = _tempPath;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _startListening() async {
    try {
      final granted = await _recorder.hasPermission();
      if (!granted) {
        if (mounted) setState(() => _micReady = false);
        return;
      }
      final dir = await getTemporaryDirectory();
      _tempPath =
      '${dir.path}/blow_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _tempPath!,
      );
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: _tickMs))
          .listen(_onAmplitude);
      if (mounted) setState(() => _micReady = true);
    } catch (e) {
      debugPrint('microphone unavailable: $e');
      if (mounted) setState(() => _micReady = false);
    }
  }

  void _onAmplitude(Amplitude amplitude) {
    if (_candlesOut || !mounted) return;
    final normalized = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
    _meter.value = normalized;

    if (amplitude.current >= _thresholdDb) {
      _loudMs += _tickMs;
    } else {
      _loudMs = max(0, _loudMs - _tickMs ~/ 2);
    }

    if (_loudMs >= _needMs) {
      unawaited(_extinguish());
    }
  }

  Future<void> _extinguish() async {
    if (_candlesOut) return;
    setState(() => _candlesOut = true);
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _meter.value = 0;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {
      // ignore
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || _closed) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final birth = parseYmd(widget.birthday);
    final age = birth == null ? 0 : ageOn(birth, DateTime.now());
    final adult = age >= 18;

    final hint = _candlesOut
        ? l.t('cakeOut')
        : (_micReady ? l.t('cakeBlow') : l.t('micOff'));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.9, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(scale: value, child: child),
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF15171F),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB300).withValues(alpha: 0.14),
                blurRadius: 50,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.t(adult ? 'hbAdult' : 'hb'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l.t(adult ? 'hbSubAdult' : 'hbSub'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.t('bNth', {'n': '${age + 1}'}),
                style: const TextStyle(
                  color: Color(0x66FFFFFF),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 210,
                width: double.infinity,
                child: AnimatedOpacity(
                  opacity: _candlesOut ? 0.42 : 1,
                  duration: const Duration(milliseconds: 700),
                  child: Image.asset(
                    kBirthdayCake,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.cake_rounded,
                      size: 120,
                      color: Color(0xFFFFC107),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: Text(
                  hint,
                  key: ValueKey('$_candlesOut-$_micReady'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _candlesOut
                        ? const Color(0xFFFFD54F)
                        : Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: ValueListenableBuilder<double>(
                  valueListenable: _meter,
                  builder: (context, value, _) {
                    return LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFFFFD54F),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(23),
                    ),
                  ),
                  onPressed: _candlesOut ? null : _extinguish,
                  child: Text(
                    _candlesOut ? l.t('cakeOut') : l.t('cakeManual'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 32. 情绪卡片分享
// =============================================================================

Future<void> showMoodCard(BuildContext context, {String? initialText}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MoodCardSheet(initialText: initialText),
  );
}

class MoodCardSheet extends StatefulWidget {
  const MoodCardSheet({super.key, this.initialText});

  final String? initialText;

  @override
  State<MoodCardSheet> createState() => _MoodCardSheetState();
}

class _MoodCardSheetState extends State<MoodCardSheet> {
  final GlobalKey _cardKey = GlobalKey();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText ??
        QuoteBank.homeQuote(AppStore.I.langCode, DateTime.now().day),
  );
  bool _sharing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
      _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('card not ready');

      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('encode failed');

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/not_alone_mood_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      final box = context.findRenderObject() as RenderBox?;
      final origin =
      box == null ? null : box.localToGlobal(Offset.zero) & box.size;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: context.t('shareText'),
        sharePositionOrigin: origin,
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.t('moodSaved'))),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;
    final text = _controller.text.trim().isEmpty
        ? l.t('moodPlaceholder')
        : _controller.text.trim();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.t('moodTitle'),
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.t('moodSub'),
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              RepaintBoundary(
                key: _cardKey,
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: MoodCard(text: text, lang: l.lang),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 3,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: cs.onSurface, fontSize: 13),
                decoration: InputDecoration(
                  hintText: l.t('moodPlaceholder'),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                      : const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(l.t('moodShare')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MoodCard extends StatelessWidget {
  const MoodCard({
    super.key,
    required this.text,
    required this.lang,
  });

  final String text;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B2440),
            Color(0xFF2B1B3D),
            Color(0xFF0E1220),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6E8BFF).withValues(alpha: 0.32),
                    const Color(0xFF6E8BFF).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -70,
            left: -60,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFB4C1).withValues(alpha: 0.2),
                    const Color(0xFFFFB4C1).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AppLogo(size: 30),
                  const SizedBox(width: 10),
                  const Text(
                    'Not alone',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                '“',
                style: TextStyle(
                  color: Color(0x4DFFFFFF),
                  fontSize: 54,
                  height: 0.7,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  height: 1.65,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${ymd(now)} · ${wdShort(now.weekday, lang)}',
                    style: const TextStyle(
                      color: Color(0x80FFFFFF),
                      fontSize: 10,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.favorite_rounded,
                    size: 12,
                    color: Color(0xFFFFB4C1),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
