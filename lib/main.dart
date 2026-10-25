// 依赖: audioplayers ^6.1.0 / http / shared_preferences / table_calendar / file_picker
// path_provider / record ^5.1.2 / flutter_localizations  (Flutter >= 3.27, minSdk 23)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter/foundation.dart';

const String kKey = 'ef14bbc0e73e99e67fe94e0e5f5ed1d7';
const String kCity = '360300';
const double kLat = 24.5130;
const double kLon = 117.6470;
final Random rnd = Random();

String two(int v) => v.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// 宽松解析：1998-6-1 / 1998-06-01 / 1998/6/1 / 1998.6.1 / 1998年6月1日 全部支持
DateTime? parseYmd(String input) {
  final raw = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (raw.isEmpty) return null;
  final m = RegExp(r'^(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?$').firstMatch(raw);
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

String wdFull(int w, bool zh) {
  const zhList = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  const enList = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return zh ? zhList[w - 1] : enList[w - 1];
}

String wdShort(int w, bool zh) {
  const zhList = ['一', '二', '三', '四', '五', '六', '日'];
  const enList = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return zh ? zhList[w - 1] : enList[w - 1];
}

String monthLabel(DateTime d, bool zh) {
  const en = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return zh ? '${d.year}年${d.month}月' : '${en[d.month - 1]} ${d.year}';
}

String bytesLabel(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
}

String descEn(String d) => const {
  '晴': 'Clear', '多云': 'Cloudy', '阴': 'Overcast', '阵雨': 'Showers',
  '雷阵雨': 'Thunderstorm', '小雨': 'Light rain', '中雨': 'Rain',
  '大雨': 'Heavy rain', '暴雨': 'Storm', '雨夹雪': 'Sleet',
  '小雪': 'Light snow', '中雪': 'Snow', '大雪': 'Heavy snow',
  '雾': 'Fog', '霾': 'Haze', '浮尘': 'Dust', '扬沙': 'Sand',
}[d] ?? d;

/* ---------------------------------- i18n ---------------------------------- */

const Map<String, List<String>> _dict = {
  'app': ['Not alone', 'Not alone'],
  'navHome': ['首页', 'Home'],
  'navWeather': ['天气', 'Weather'],
  'navCalendar': ['日历', 'Calendar'],
  'navTree': ['树洞', 'Hollow'],
  'navSettings': ['设置', 'Settings'],
  'hiMorning': ['早上好，今天也会有人偷偷想你', 'Good morning. Someone is thinking of you.'],
  'hiNoon': ['下午好，记得喝口水', 'Good afternoon. Drink some water.'],
  'hiEvening': ['晚上好，今天辛苦了', 'Good evening. You made it through.'],
  'hiNight': ['夜深了，早点睡，世界明天再应付', 'Late night. Rest now, the world can wait.'],
  'tapCalendar': ['点击查看日历', 'Tap for the calendar'],
  'tapTime': ['再点一下回到时间', 'Tap again for the clock'],
  'weather': ['高德天气', 'Weather'],
  'alarm': ['闹钟', 'Alarm'],
  'alarmRinging': ['闹钟 · 响铃中', 'Alarm · ringing'],
  'dailyAlarm': ['每日提醒', 'Every day'],
  'humidity': ['湿度', 'Humidity'],
  'wind': ['风', 'Wind'],
  'uv': ['紫外线', 'UV index'],
  'feels': ['体感', 'Feels like'],
  'wUnavailable': ['天气暂不可用', 'Weather unavailable'],
  'wNetwork': ['网络异常，请检查连接', 'Network error'],
  'wRetry': ['重试', 'Retry'],
  'wDetail': ['天气详情', 'Weather details'],
  'wCurrent': ['实时天气', 'Right now'],
  'wHourly': ['未来 12 小时', 'Next 12 hours'],
  'wDaily': ['未来几天', 'Next days'],
  'wExtras': ['逐小时与紫外线来自 Open-Meteo', 'Hourly & UV from Open-Meteo'],
  'calendarTitle': ['日历', 'Calendar'],
  'holidaysMonth': ['本月节日', 'Holidays this month'],
  'noHolidays': ['本月没有节日', 'No holidays this month'],
  'cn': ['中国', 'China'],
  'de': ['德国', 'Germany'],
  'us': ['美国', 'USA'],
  'today': ['今天', 'Today'],
  'treeTitle': ['树洞', 'Hollow'],
  'treeSub': ['匿名 · 双向授权 · 数据只在这台手机', 'Anonymous · mutual consent · on device'],
  'match': ['随机匹配', 'Random match'],
  'matching': ['正在寻找同频的人…', 'Looking for someone like you…'],
  'rematch': ['换一个人', 'Someone else'],
  'apply': ['申请认识（双向授权）', 'Ask to connect'],
  'applied': ['已发送匿名申请，等待对方同意', 'Request sent. Waiting.'],
  'connectedTap': ['已互相授权 · 去打招呼', 'Connected · say hi'],
  'noReply': ['对方还没有回应，也许 ta 也在犹豫', 'No reply yet. Maybe they hesitate.'],
  'consentTitle': ['对方同意了你的申请', 'They accepted'],
  'consentBody': ['「{name}」接受了你的双向授权，你们可以匿名互相倾诉了。', '“{name}” accepted. Talk anonymously now.'],
  'sayHi': ['说点什么', 'Say something'],
  'treeEmpty': ['这个世界很大，总有人和你同频', 'Someone out there matches you.'],
  'anon': ['匿名', 'anon'],
  'settingsTitle': ['设置', 'Settings'],
  'settingsSub': ['所有数据保存在本机，卸载即删除', 'Everything stays on this device'],
  'language': ['语言', 'Language'],
  'followSystem': ['跟随系统', 'System'],
  'theme': ['主题', 'Theme'],
  'themeDark': ['深色', 'Dark'],
  'themeLight': ['浅色', 'Light'],
  'birthday': ['生日', 'Birthday'],
  'notSet': ['未设置', 'Not set'],
  'bLocked': ['今年已修改过，明年才能再改', 'Changed this year. Try next year.'],
  'edit': ['修改', 'Edit'],
  'wallpaper': ['壁纸', 'Wallpaper'],
  'wallpaperDefault': ['默认日落壁纸', 'Default sunset'],
  'wallpaperLocal': ['来自本地相册', 'From your device'],
  'ringtone': ['闹钟铃声', 'Ringtone'],
  'ringtoneDefault': ['默认 Ring10.wav', 'Default Ring10.wav'],
  'ringtoneLocal': ['来自本地文件', 'From your device'],
  'changeWallpaper': ['更换壁纸', 'Change wallpaper'],
  'changeRingtone': ['更换铃声', 'Change ringtone'],
  'resetDefault': ['恢复默认', 'Reset'],
  'clearCache': ['清除缓存', 'Clear cache'],
  'cacheCleared': ['缓存已清除', 'Cache cleared'],
  'cacheSize': ['当前占用', 'In use'],
  'privacy': ['隐私', 'Privacy'],
  'privacyBody': ['完全匿名 · 无账号 · 无服务器 · 无上传', 'Anonymous · no account · no upload'],
  'careBody': [
    '如果你现实中真的很孤独，我想给你一点温暖。本应用完全匿名，请放心倾诉。',
    'If you are truly lonely out there, I want to give you a little warmth. This app is fully anonymous.',
  ],
  'agree': ['我同意并进入', 'I agree and enter'],
  'bAsk': ['告诉我们你的生日', 'Tell us your birthday'],
  'bAskSub': ['只在生日当天，我们会送你一块电子蛋糕。', 'On your birthday we bake you a digital cake.'],
  'bNote': ['生日每年只能修改一次，请填写真实日期。', 'Can be changed once a year.'],
  'bFormat': ['请输入有效日期，如 1998-6-1 或 1998-06-01', 'Enter a valid date, e.g. 1998-6-1'],
  'bFuture': ['生日不能在未来', 'Birthday cannot be in the future'],
  'bSave': ['保存生日', 'Save birthday'],
  'bPick': ['选择日期', 'Pick a date'],
  'save': ['保存', 'Save'],
  'cancel': ['取消', 'Cancel'],
  'hb': ['生日快乐', 'Happy birthday'],
  'hbAdult': ['恭喜成年', 'Happy adulthood'],
  'hbSub': ['愿新的一岁，你被世界温柔以待。', 'May the world be gentle with you.'],
  'hbSubAdult': ['从今天起，请为自己而活，也请偶尔为自己软弱。', 'Live for yourself now. Be soft sometimes.'],
  'bNth': ['今天是你的第 {n} 个生日', 'Birthday #{n}'],
  'cakeBlow': ['对着屏幕轻轻吹气，吹灭蜡烛', 'Blow gently at the screen'],
  'micDenied': ['麦克风不可用，点击手动吹灭', 'No microphone, tap to blow out'],
  'blowManual': ['吹不动了？点这里吹灭', 'Tap to put them out'],
  'candlesOut': ['愿望会实现的', 'Your wish will come true'],
  'ringTitle': ['该起床啦', 'Time to wake up'],
  'wokeUp': ['我醒了', "I'm up"],
  'alarmSaved': ['闹钟已设置为 {t}', 'Alarm set for {t}'],
  'q1': ['闹钟响了，你一定很累吧，但生活推着你向前。', 'You must be tired. But life keeps pushing.'],
  'q2': ['慢慢来，你没有迟到，你只是在自己的时区里。', 'Take your time. You are in your own timezone.'],
  'q3': ['今天也请好好吃饭，好好喝水，你不是一个人在撑。', 'Eat well. Drink water. You are not alone.'],
  'q4': ['不用成为更好的人，先成为更舒服的人。', 'You do not have to be better. Just be comfortable.'],
  'q5': ['如果没有人对你说早安，那我来。早安。', 'If nobody said good morning, I will.'],
  'q6': ['你不必万事都赢，你只要还在，就很好。', 'You do not have to win everything.'],
};

class L10n {
  const L10n(this.locale);

  final Locale locale;

  bool get isZh => locale.languageCode == 'zh';

  String t(String key, [Map<String, String>? args]) {
    final pair = _dict[key];
    var s = pair == null ? key : pair[isZh ? 0 : 1];
    if (args != null) {
      args.forEach((k, v) => s = s.replaceAll('{$k}', v));
    }
    return s;
  }

  static L10n of(BuildContext c) =>
      Localizations.of<L10n>(c, L10n) ?? const L10n(Locale('zh'));

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();
  static const List<Locale> supported = [Locale('zh'), Locale('en')];
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  bool isSupported(Locale l) => l.languageCode == 'zh' || l.languageCode == 'en';

  @override
  Future<L10n> load(Locale l) => SynchronousFuture<L10n>(L10n(l));

  @override
  bool shouldReload(covariant LocalizationsDelegate<L10n> old) => false;
}

extension AppCtx on BuildContext {
  L10n get l => L10n.of(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
  String t(String k, [Map<String, String>? a]) => L10n.of(this).t(k, a);
}

/* -------------------------------- app store -------------------------------- */

class AppStore extends ChangeNotifier {
  AppStore._(this._p);

  static late AppStore I;

  static Future<void> load() async => I = AppStore._(await SharedPreferences.getInstance());

  final SharedPreferences _p;

  String get localeCode => _p.getString('locale') ?? 'system';

  Locale? get locale => switch (localeCode) {
    'zh' => const Locale('zh'),
    'en' => const Locale('en'),
    _ => null,
  };

  Future<void> setLocale(String v) async {
    await _p.setString('locale', v);
    notifyListeners();
  }

  String get themeCode => _p.getString('theme') ?? 'dark';

  ThemeMode get themeMode => switch (themeCode) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };

  Future<void> setTheme(String v) async {
    await _p.setString('theme', v);
    notifyListeners();
  }

  bool get careAccepted => _p.getBool('careAccepted') ?? false;

  Future<void> acceptCare() async {
    await _p.setBool('careAccepted', true);
    notifyListeners();
  }

  int get alarmHour => _p.getInt('alarmHour') ?? 7;
  int get alarmMinute => _p.getInt('alarmMinute') ?? 0;

  Future<void> setAlarm(int h, int m) async {
    await _p.setInt('alarmHour', h);
    await _p.setInt('alarmMinute', m);
    notifyListeners();
  }

  String? get birthday => _p.getString('birthday');
  int get birthdayEditYear => _p.getInt('birthdayEditYear') ?? 0;
  bool get canEditBirthday => birthday == null || birthdayEditYear < DateTime.now().year;

  Future<void> setBirthday(String v) async {
    await _p.setString('birthday', v);
    await _p.setInt('birthdayEditYear', DateTime.now().year);
    notifyListeners();
  }

  String? get cakeShownOn => _p.getString('cakeShownOn');

  Future<void> markCakeShown() async => _p.setString('cakeShownOn', ymd(DateTime.now()));

  String? get wallpaper => _p.getString('wallpaper');
  String? get ringtone => _p.getString('ringtone');

  Future<void> setWallpaper(String? v) async {
    if (v == null) {
      await _p.remove('wallpaper');
    } else {
      await _p.setString('wallpaper', v);
    }
    notifyListeners();
  }

  Future<void> setRingtone(String? v) async {
    if (v == null) {
      await _p.remove('ringtone');
    } else {
      await _p.setString('ringtone', v);
    }
    notifyListeners();
  }
}

/* --------------------------------- weather -------------------------------- */

class WNow {
  const WNow({
    required this.city,
    required this.desc,
    required this.temp,
    required this.humidity,
    required this.windDir,
    required this.windPower,
    required this.time,
  });

  final String city, desc, windDir, windPower, time;
  final int temp, humidity;
}

class WDay {
  const WDay({
    required this.date,
    required this.dayDesc,
    required this.high,
    required this.low,
  });

  final DateTime date;
  final String dayDesc;
  final int high, low;
}

class WHour {
  const WHour({required this.time, required this.temp, required this.rain});
  final DateTime time;
  final double temp;
  final int rain;
}

class WSnap {
  const WSnap({required this.now, this.days = const [], this.hours = const [], this.uv, this.feels});
  final WNow now;
  final List<WDay> days;
  final List<WHour> hours;
  final double? uv, feels;
}

class _WErr implements Exception {
  const _WErr(this.code);
  final String code;
}

String _s(Object? v) => v is String ? v : (v is num ? '$v' : '');
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

class WeatherController extends ChangeNotifier {
  final http.Client _client = http.Client();

  WSnap? data;
  String? error;
  bool loading = false;
  DateTime? _last;

  Future<void> refresh({bool force = false}) async {
    if (loading) return;
    if (!force && _last != null && DateTime.now().difference(_last!) < const Duration(minutes: 10)) {
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final now = await _now();
      var days = const <WDay>[];
      try {
        days = await _days();
      } catch (_) {}
      _Open? open;
      try {
        open = await _open();
      } catch (_) {}
      data = WSnap(
        now: now,
        days: days,
        hours: open?.hours ?? const [],
        uv: open?.uv,
        feels: open?.feels,
      );
      _last = DateTime.now();
      error = null;
    } on _WErr catch (e) {
      error = e.code;
    } catch (_) {
      error = 'network';
    }
    loading = false;
    notifyListeners();
  }

  Future<WNow> _now() async {
    final m = await _get(Uri.https('restapi.amap.com', '/v3/weather/weatherInfo', {
      'key': kKey,
      'city': kCity,
      'extensions': 'base',
    }));
    final lives = m['lives'];
    if (lives is! List || lives.isEmpty) throw const _WErr('api');
    final x = Map<String, dynamic>.from(lives.first as Map);
    return WNow(
      city: _s(x['city']),
      desc: _s(x['weather']),
      temp: _i(x['temperature']),
      humidity: _i(x['humidity']),
      windDir: _s(x['winddirection']),
      windPower: _s(x['windpower']),
      time: _s(x['reporttime']),
    );
  }

  Future<List<WDay>> _days() async {
    final m = await _get(Uri.https('restapi.amap.com', '/v3/weather/weatherInfo', {
      'key': kKey,
      'city': kCity,
      'extensions': 'all',
    }));
    final fc = m['forecasts'];
    if (fc is! List || fc.isEmpty) return const [];
    final casts = (fc.first as Map)['casts'];
    if (casts is! List) return const [];
    return casts.whereType<Map>().map((raw) {
      final x = Map<String, dynamic>.from(raw);
      return WDay(
        date: DateTime.tryParse(_s(x['date'])) ?? DateTime.now(),
        dayDesc: _s(x['dayweather']),
        high: _i(x['daytemp']),
        low: _i(x['nighttemp']),
      );
    }).toList();
  }

  Future<_Open?> _open() async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$kLat',
      'longitude': '$kLon',
      'current': 'apparent_temperature,uv_index',
      'hourly': 'temperature_2m,precipitation_probability',
      'timezone': 'Asia/Shanghai',
      'forecast_days': '2',
    });
    final r = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final m = jsonDecode(utf8.decode(r.bodyBytes));
    if (m is! Map<String, dynamic>) return null;

    final hours = <WHour>[];
    final hourly = m['hourly'];
    if (hourly is Map<String, dynamic>) {
      final times = hourly['time'] as List? ?? const [];
      final temps = hourly['temperature_2m'] as List? ?? const [];
      final rains = hourly['precipitation_probability'] as List? ?? const [];
      final n = DateTime.now();
      final floor = DateTime(n.year, n.month, n.day, n.hour);
      for (var i = 0; i < times.length; i++) {
        final t = DateTime.tryParse('${times[i]}');
        if (t == null || t.isBefore(floor)) continue;
        hours.add(WHour(
          time: t,
          temp: _d(i < temps.length ? temps[i] : null),
          rain: _i(i < rains.length ? rains[i] : null),
        ));
        if (hours.length >= 12) break;
      }
    }

    final cur = m['current'];
    final c = cur is Map<String, dynamic> ? cur : const <String, dynamic>{};
    return _Open(
      hours: hours,
      uv: cur == null ? null : _d(c['uv_index']),
      feels: cur == null ? null : _d(c['apparent_temperature']),
    );
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    http.Response r;
    try {
      r = await _client.get(uri).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const _WErr('network');
    }
    if (r.statusCode != 200) throw const _WErr('network');
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) return d;
      throw const _WErr('api');
    } on _WErr {
      rethrow;
    } catch (_) {
      throw const _WErr('api');
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

class _Open {
  const _Open({required this.hours, this.uv, this.feels});
  final List<WHour> hours;
  final double? uv, feels;
}

/* -------------------------------- holidays -------------------------------- */

enum HScope { cn, de, us }

class Holiday {
  const Holiday(this.scope, this.zh, this.en);
  final HScope scope;
  final String zh, en;
  String name(bool zhMode) => zhMode ? zh : en;
}

class _Fixed {
  const _Fixed(this.m, this.d, this.scope, this.zh, this.en);
  final int m, d;
  final HScope scope;
  final String zh, en;
}

class _Offset {
  const _Offset(this.o, this.scope, this.zh, this.en);
  final int o;
  final HScope scope;
  final String zh, en;
}

class _Nth {
  const _Nth(this.m, this.w, this.n, this.scope, this.zh, this.en);
  final int m, w, n;
  final HScope scope;
  final String zh, en;
}

const List<_Fixed> _fixedHolidays = [
  _Fixed(1, 1, HScope.cn, '元旦', "New Year's Day"),
  _Fixed(4, 4, HScope.cn, '清明节', 'Qingming Festival'),
  _Fixed(5, 1, HScope.cn, '劳动节', 'Labour Day'),
  _Fixed(10, 1, HScope.cn, '国庆节', 'National Day'),
  _Fixed(1, 1, HScope.de, '元旦', 'Neujahr'),
  _Fixed(1, 6, HScope.de, '主显节', 'Heilige Drei Könige'),
  _Fixed(5, 1, HScope.de, '劳动节', 'Tag der Arbeit'),
  _Fixed(10, 3, HScope.de, '德国统一日', 'Tag der Deutschen Einheit'),
  _Fixed(10, 31, HScope.de, '宗教改革日', 'Reformationstag'),
  _Fixed(11, 1, HScope.de, '万圣节', 'Allerheiligen'),
  _Fixed(12, 25, HScope.de, '圣诞第一节', '1. Weihnachtstag'),
  _Fixed(12, 26, HScope.de, '圣诞第二节', '2. Weihnachtstag'),
  _Fixed(1, 1, HScope.us, '新年', "New Year's Day"),
  _Fixed(2, 14, HScope.us, '情人节', "Valentine's Day"),
  _Fixed(7, 4, HScope.us, '独立日', 'Independence Day'),
  _Fixed(10, 31, HScope.us, '万圣夜', 'Halloween'),
  _Fixed(12, 25, HScope.us, '圣诞节', 'Christmas Day'),
];

const List<_Offset> _easterHolidays = [
  _Offset(-2, HScope.de, '耶稣受难日', 'Karfreitag'),
  _Offset(1, HScope.de, '复活节星期一', 'Ostermontag'),
  _Offset(39, HScope.de, '耶稣升天节', 'Christi Himmelfahrt'),
  _Offset(50, HScope.de, '圣灵降临节星期一', 'Pfingstmontag'),
];

const List<_Nth> _nthHolidays = [
  _Nth(5, 7, 2, HScope.us, '母亲节', "Mother's Day"),
  _Nth(6, 7, 3, HScope.us, '父亲节', "Father's Day"),
  _Nth(11, 4, 4, HScope.us, '感恩节', 'Thanksgiving'),
];

const Map<int, Map<String, List<int>>> _lunar = {
  2024: {'spring': [2, 10], 'lantern': [2, 24], 'dragon': [6, 10], 'mid': [9, 17], 'double': [10, 11]},
  2025: {'spring': [1, 29], 'lantern': [2, 12], 'dragon': [5, 31], 'mid': [10, 6], 'double': [10, 29]},
  2026: {'spring': [2, 17], 'lantern': [3, 3], 'dragon': [6, 19], 'mid': [9, 25], 'double': [10, 18]},
  2027: {'spring': [2, 6], 'lantern': [2, 20], 'dragon': [6, 9], 'mid': [9, 15], 'double': [10, 8]},
};

const Map<String, List<String>> _lunarNames = {
  'spring': ['春节', 'Spring Festival'],
  'lantern': ['元宵节', 'Lantern Festival'],
  'dragon': ['端午节', 'Dragon Boat Festival'],
  'mid': ['中秋节', 'Mid-Autumn Festival'],
  'double': ['重阳节', 'Double Ninth Festival'],
};

final _Holidays holidays = _Holidays();

class _Holidays {
  List<Holiday> forDate(DateTime d) {
    final out = <Holiday>[];
    for (final h in _fixedHolidays) {
      if (h.m == d.month && h.d == d.day) out.add(Holiday(h.scope, h.zh, h.en));
    }
    final e = easter(d.year);
    for (final o in _easterHolidays) {
      final x = e.add(Duration(days: o.o));
      if (x.month == d.month && x.day == d.day) out.add(Holiday(o.scope, o.zh, o.en));
    }
    for (final n in _nthHolidays) {
      if (n.m != d.month) continue;
      if (_nthWeekday(d.year, n.m, n.w, n.n) == d.day) {
        out.add(Holiday(n.scope, n.zh, n.en));
      }
    }
    _lunar[d.year]?.forEach((k, md) {
      if (md[0] == d.month && md[1] == d.day) {
        final nm = _lunarNames[k];
        if (nm != null) out.add(Holiday(HScope.cn, nm[0], nm[1]));
      }
    });
    return out;
  }

  Map<int, List<Holiday>> forMonth(int y, int m, Set<HScope> scopes) {
    final out = <int, List<Holiday>>{};
    final total = DateTime(y, m + 1, 0).day;
    for (var d = 1; d <= total; d++) {
      final list = forDate(DateTime(y, m, d)).where((h) => scopes.contains(h.scope)).toList();
      if (list.isNotEmpty) out[d] = list;
    }
    return out;
  }

  DateTime easter(int y) {
    final a = y % 19, b = y ~/ 100, c = y % 100, d = b ~/ 4, e = b % 4;
    final f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4, k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    return DateTime(y, (h + l - 7 * m + 114) ~/ 31, (h + l - 7 * m + 114) % 31 + 1);
  }

  int _nthWeekday(int y, int m, int weekday, int n) {
    final first = DateTime(y, m, 1);
    return 1 + (weekday - first.weekday) % 7 + (n - 1) * 7;
  }

  String label(HScope s, bool zh) => switch (s) {
    HScope.cn => zh ? '中国' : 'CN',
    HScope.de => zh ? '德国' : 'DE',
    HScope.us => zh ? '美国' : 'US',
  };
}

/* --------------------------------- 树洞数据 -------------------------------- */

class Anon {
  const Anon(this.alias, this.metaZh, this.metaEn, this.textZh, this.textEn);
  final String alias, metaZh, metaEn, textZh, textEn;
  String meta(bool zh) => zh ? metaZh : metaEn;
  String text(bool zh) => zh ? textZh : textEn;
}

const List<Anon> _anonPool = [
  Anon('匿名小猫', '22 岁 · 广州', '22 · Guangzhou', '哪怕今天很糟糕，我也挺过来了', 'Today was awful. But I made it.'),
  Anon('走神的星星', '25 岁 · 成都', '25 · Chengdu', '凌晨两点睡不着，但没有告诉任何人', 'Awake at 2am. Told nobody.'),
  Anon('抱膝的人', '19 岁 · 哈尔滨', '19 · Harbin', '今天对喜欢的人说了早安，他没有回', 'Said good morning to my crush. No reply.'),
  Anon('路过的风', '28 岁 · 杭州', '28 · Hangzhou', '加班到十点，楼下的关东煮是唯一的温暖', 'Worked till ten. Oden was the only warmth.'),
  Anon('橘子汽水', '21 岁 · 长沙', '21 · Changsha', '一个人搬家，一个人庆祝，也一个人长大', 'Moved alone, grew up alone.'),
  Anon('安静的树', '30 岁 · 西安', '30 · Xi’an', '我在人群中，但我不在人群里', 'Among people, but not in them.'),
];

/* ----------------------------------- app ---------------------------------- */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStore.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
    useMaterial3: true,
    brightness: b,
    colorSchemeSeed: const Color(0xFF8EC5FF),
    scaffoldBackgroundColor:
    b == Brightness.dark ? const Color(0xFF07080E) : const Color(0xFFF4F5F9),
    splashFactory: InkSparkle.splashFactory,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.I,
      builder: (context, _) => MaterialApp(
        title: 'Not alone',
        debugShowCheckedModeBanner: false,
        locale: AppStore.I.locale,
        supportedLocales: L10n.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          L10n.delegate,
        ],
        themeMode: AppStore.I.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const RootPage(),
      ),
    );
  }
}

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _gates());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _weather.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _weather.refresh();
  }

  Future<void> _gates() async {
    final store = AppStore.I;
    if (!store.careAccepted) {
      await showCare(context);
      await store.acceptCare();
    }
    if (!mounted) return;
    if (store.birthday == null) {
      final v = await showBirthday(context);
      if (v != null) await store.setBirthday(v);
    }
    if (!mounted) return;
    final b = store.birthday;
    if (b != null && isBirthdayToday(b) && store.cakeShownOn != ymd(DateTime.now())) {
      await showCake(context, b);
      await store.markCakeShown();
    }
  }

  Future<void> _openAlarm() async {
    final r = await showAlarmSheet(context, AppStore.I.alarmHour, AppStore.I.alarmMinute);
    if (r == null) return;
    await AppStore.I.setAlarm(r.$1, r.$2);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(context.t('alarmSaved', {'t': '${two(r.$1)}:${two(r.$2)}'})),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return ListenableBuilder(
      listenable: AppStore.I,
      builder: (context, _) {
        final s = AppStore.I;
        final cs = context.cs;
        return Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: _tab,
            children: [
              HomePage(
                weather: _weather,
                hour: s.alarmHour,
                minute: s.alarmMinute,
                wallpaper: s.wallpaper,
                ringtone: s.ringtone,
                onAlarm: _openAlarm,
              ),
              WeatherPage(weather: _weather),
              const CalendarPage(),
              const TreeHolePage(),
              SettingsPage(onAlarm: _openAlarm),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: cs.onSurface,
            unselectedItemColor: cs.onSurface.withValues(alpha: 0.45),
            selectedFontSize: 10,
            unselectedFontSize: 10,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.nightlight_outlined),
                activeIcon: const Icon(Icons.nightlight_round),
                label: l.t('navHome'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.cloud_outlined),
                activeIcon: const Icon(Icons.cloud),
                label: l.t('navWeather'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.calendar_month_outlined),
                activeIcon: const Icon(Icons.calendar_month),
                label: l.t('navCalendar'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.forest_outlined),
                activeIcon: const Icon(Icons.forest),
                label: l.t('navTree'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.settings_outlined),
                activeIcon: const Icon(Icons.settings),
                label: l.t('navSettings'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/* -------------------------------- 通用组件 -------------------------------- */

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
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: onImage
                ? Colors.white.withValues(alpha: 0.16)
                : cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: base.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: onImage ? 0.18 : 0.05),
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
                      style: TextStyle(color: base.withValues(alpha: 0.72), fontSize: 11),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 13, color: base.withValues(alpha: 0.45)),
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
                style: TextStyle(color: base.withValues(alpha: 0.45), fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card);
  }
}

Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  final cs = context.cs;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.86),
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
    ),
  );
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
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

/* --------------------------------- 迷你日历 -------------------------------- */

class MiniCalendar extends StatelessWidget {
  const MiniCalendar({
    super.key,
    required this.focused,
    required this.selected,
    required this.onFocused,
    required this.onSelected,
  });

  final DateTime focused;
  final DateTime selected;
  final ValueChanged<DateTime> onFocused;
  final void Function(DateTime, DateTime) onSelected;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
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
                onPressed: () => onFocused(DateTime(focused.year, focused.month - 1, 1)),
                icon: const Icon(Icons.chevron_left, size: 18, color: Colors.white),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    monthLabel(focused, l.isZh),
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
                onPressed: () => onFocused(DateTime(focused.year, focused.month + 1, 1)),
                icon: const Icon(Icons.chevron_right, size: 18, color: Colors.white),
              ),
            ],
          ),
          TableCalendar<Holiday>(
            firstDay: DateTime.utc(1970, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: focused,
            headerVisible: false,
            rowHeight: 30,
            daysOfWeekHeight: 18,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: ''},
            eventLoader: holidays.forDate,
            selectedDayPredicate: (d) => isSameDay(d, selected),
            onDaySelected: onSelected,
            onPageChanged: onFocused,
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              cellMargin: const EdgeInsets.all(2),
              defaultTextStyle: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
              weekendTextStyle: const TextStyle(color: Color(0x80FFFFFF), fontSize: 11),
              todayDecoration: const BoxDecoration(color: Color(0x3DFFFFFF), shape: BoxShape.circle),
              todayTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
              selectedDecoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              selectedTextStyle: const TextStyle(color: Colors.black, fontSize: 11),
            ),
            calendarBuilders: CalendarBuilders<Holiday>(
              dowBuilder: (c, d) => Center(
                child: Text(
                  wdShort(d.weekday, l.isZh),
                  style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 9),
                ),
              ),
              markerBuilder: (c, d, e) => e.isEmpty
                  ? null
                  : Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFD54F),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------------- 天气组件 -------------------------------- */

class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.snap});
  final WSnap snap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cs = context.cs;
    final items = <(IconData, String, String)>[
      (Icons.water_drop_outlined, l.t('humidity'), '${snap.now.humidity}%'),
      (Icons.air, l.t('wind'), '${snap.now.windDir} ${snap.now.windPower}'),
      (Icons.wb_sunny_outlined, l.t('uv'), snap.uv == null ? '—' : snap.uv!.toStringAsFixed(1)),
      (Icons.thermostat_outlined, l.t('feels'), snap.feels == null ? '—' : '${snap.feels!.round()}°C'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.5,
      children: [
        for (final it in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(it.$1, size: 15, color: cs.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.$2,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontSize: 10,
                          )),
                      Text(
                        it.$3,
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
  final List<WHour> hours;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (c, i) {
          final h = hours[i];
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
                Text('${two(h.time.hour)}:00',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.5),
                      fontSize: 10,
                    )),
                Icon(
                  h.rain >= 50 ? Icons.umbrella_outlined : Icons.wb_sunny_outlined,
                  size: 15,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
                Text('${h.temp.round()}°',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
                Text('${h.rain}%',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      fontSize: 9,
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class DayList extends StatelessWidget {
  const DayList({super.key, required this.days});
  final List<WDay> days;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cs = context.cs;
    return Column(
      children: [
        for (final d in days)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    '${d.date.month}/${d.date.day} ${wdFull(d.date.weekday, l.isZh)}',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l.isZh ? d.dayDesc : descEn(d.dayDesc),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '${d.low}° / ${d.high}°',
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

Future<void> showWeatherSheet(BuildContext context, WeatherController c) {
  return showAppSheet<void>(context, (ctx) {
    final l = ctx.l;
    final cs = ctx.cs;
    return ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final s = c.data;
        if (s == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: c.loading
                  ? const CircularProgressIndicator()
                  : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.t(c.error == 'api' ? 'wUnavailable' : 'wNetwork'),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => c.refresh(force: true),
                    child: Text(l.t('wRetry')),
                  ),
                ],
              ),
            ),
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
                    '${s.now.temp}°',
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
                        '${l.isZh ? s.now.desc : descEn(s.now.desc)} · ${s.now.city}',
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
                      s.now.time,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.35),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MetricGrid(snap: s),
              if (s.hours.isNotEmpty) ...[
                const SizedBox(height: 18),
                SheetTitle(l.t('wHourly')),
                HourStrip(hours: s.hours),
              ],
              if (s.days.isNotEmpty) ...[
                const SizedBox(height: 18),
                SheetTitle(l.t('wDaily')),
                DayList(days: s.days),
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

/* ---------------------------------- 首页 ---------------------------------- */

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.weather,
    required this.hour,
    required this.minute,
    required this.wallpaper,
    required this.ringtone,
    required this.onAlarm,
  });

  final WeatherController weather;
  final int hour, minute;
  final String? wallpaper, ringtone;
  final VoidCallback onAlarm;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _sub;
  Timer? _ticker;

  DateTime _now = DateTime.now();
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  PlayerState _state = PlayerState.stopped;
  bool _cal = false;
  bool _ringing = false;
  String? _fired;
  int _qi = 1;

  @override
  void initState() {
    super.initState();
    _qi = rnd.nextInt(6) + 1;
    _sub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant HomePage old) {
    super.didUpdateWidget(old);
    if (old.hour != widget.hour || old.minute != widget.minute) _fired = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    _player.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final n = DateTime.now();
    setState(() => _now = n);
    if (n.hour == widget.hour && n.minute == widget.minute) {
      final key = '${ymd(n)} ${n.hour}:${n.minute}';
      if (_fired != key) {
        _fired = key;
        unawaited(_ring());
      }
    }
  }

  Future<void> _ring() async {
    if (_ringing || !mounted) return;
    _ringing = true;
    final quote = context.t('q${rnd.nextInt(6) + 1}');
    await _startAudio();
    if (!mounted) {
      _ringing = false;
      return;
    }
    await showWakeUp(context, quote);
    _ringing = false;
    await _stopAudio();
  }

  Future<void> _startAudio() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1);
      final p = widget.ringtone;
      if (p != null && p.isNotEmpty && File(p).existsSync()) {
        await _player.play(DeviceFileSource(p));
      } else {
        await _player.play(AssetSource('Ring10.wav'));
      }
    } catch (e) {
      debugPrint('alarm audio: $e');
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  String _greet(L10n l) {
    final h = _now.hour;
    if (h < 6) return l.t('hiNight');
    if (h < 12) return l.t('hiMorning');
    if (h < 18) return l.t('hiNoon');
    return l.t('hiEvening');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final night = _now.hour >= 18 || _now.hour < 6;
    return Stack(
      fit: StackFit.expand,
      children: [
        _bg(night),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: night
                  ? const [Color(0x8C000000), Color(0x33000000), Color(0xE0000000)]
                  : const [Color(0x6B000000), Color(0x22000000), Color(0xB8000000)],
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
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _greet(l),
                            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l.t('alarm'),
                      onPressed: widget.onAlarm,
                      icon: const Icon(Icons.alarm_add_outlined, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _cal = !_cal),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.92, end: 1).animate(a),
                            child: child,
                          ),
                        ),
                        child: _cal
                            ? MiniCalendar(
                          key: const ValueKey('cal'),
                          focused: _focused,
                          selected: _selected,
                          onFocused: (d) => setState(() => _focused = d),
                          onSelected: (s, f) => setState(() {
                            _selected = s;
                            _focused = f;
                          }),
                        )
                            : _clock(l),
                      ),
                    ),
                  ),
                ),
                _quoteStrip(l),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _weatherCard(l)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassCard(
                        icon: _state == PlayerState.playing
                            ? Icons.notifications_active
                            : Icons.alarm,
                        title: _state == PlayerState.playing
                            ? l.t('alarmRinging')
                            : l.t('alarm'),
                        value: '${two(widget.hour)}:${two(widget.minute)}',
                        subtitle: l.t('dailyAlarm'),
                        onTap: widget.onAlarm,
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

  Widget _bg(bool night) {
    final p = widget.wallpaper;
    if (p != null && p.isNotEmpty) {
      final f = File(p);
      if (f.existsSync()) {
        return Image.file(
          f,
          key: ValueKey(p),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _bgDefault(night),
        );
      }
    }
    return _bgDefault(night);
  }

  Widget _bgDefault(bool night) {
    if (night) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF05070F), Color(0xFF0B1230), Color(0xFF02030A)],
          ),
        ),
      );
    }
    return Image.asset(
      'assets/sunset.jpg',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8A65), Color(0xFFFFB74D), Color(0xFF4A3AFF)],
          ),
        ),
      ),
    );
  }

  Widget _clock(L10n l) {
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
          '${_now.year}-${two(_now.month)}-${two(_now.day)} ${wdFull(_now.weekday, l.isZh)}',
          style: const TextStyle(
            color: Color(0xB3FFFFFF),
            fontSize: 13,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app_outlined, size: 12, color: Color(0x80FFFFFF)),
            const SizedBox(width: 4),
            Text(
              l.t(_cal ? 'tapTime' : 'tapCalendar'),
              style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quoteStrip(L10n l) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.favorite, size: 13, color: Color(0xFFFFB4C1)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.t('q$_qi'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weatherCard(L10n l) {
    return AnimatedBuilder(
      animation: widget.weather,
      builder: (context, _) {
        final s = widget.weather.data;
        if (s == null) {
          return GlassCard(
            icon: Icons.wb_cloudy_outlined,
            title: l.t('weather'),
            value: l.t(widget.weather.error == 'api' ? 'wUnavailable' : 'wNetwork'),
            subtitle: l.t('wRetry'),
            onTap: () => showWeatherSheet(context, widget.weather),
          );
        }
        return GlassCard(
          icon: Icons.wb_cloudy_outlined,
          title: l.t('weather'),
          value: '${s.now.temp}°C  ${l.isZh ? s.now.desc : descEn(s.now.desc)}',
          subtitle: '${l.t('humidity')} ${s.now.humidity}% · ${s.now.windDir} ${s.now.windPower}',
          onTap: () => showWeatherSheet(context, widget.weather),
        );
      },
    );
  }
}

/* --------------------------------- 天气页 --------------------------------- */

class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key, required this.weather});
  final WeatherController weather;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cs = context.cs;
    return SafeArea(
      child: ListenableBuilder(
        listenable: weather,
        builder: (context, _) {
          final s = weather.data;
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
                            l.t('weather'),
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
                if (s == null && weather.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (s == null)
                  GlassCard(
                    icon: Icons.cloud_off,
                    title: l.t('weather'),
                    value: l.t(weather.error == 'api' ? 'wUnavailable' : 'wNetwork'),
                    subtitle: l.t('wRetry'),
                    onImage: false,
                    onTap: () => weather.refresh(force: true),
                  )
                else ...[
                    GlassCard(
                      icon: Icons.wb_sunny_outlined,
                      title: l.t('wCurrent'),
                      value: '${s.now.temp}°C  ${l.isZh ? s.now.desc : descEn(s.now.desc)}',
                      subtitle: '${s.now.city} · ${s.now.time}',
                      onImage: false,
                    ),
                    const SizedBox(height: 14),
                    MetricGrid(snap: s),
                    if (s.hours.isNotEmpty) ...[
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
                      HourStrip(hours: s.hours),
                    ],
                    if (s.days.isNotEmpty) ...[
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
                      DayList(days: s.days),
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

/* --------------------------------- 日历页 --------------------------------- */

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  Set<HScope> _scopes = HScope.values.toSet();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cs = context.cs;
    final month = holidays.forMonth(_focused.year, _focused.month, _scopes);
    final days = month.keys.toList()..sort();
    final picked = holidays.forDate(_selected).where((h) => _scopes.contains(h.scope)).toList();

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
                      '${ymd(_selected)} ${wdFull(_selected.weekday, l.isZh)}',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _focused = DateTime.now();
                  _selected = DateTime.now();
                }),
                child: Text(l.t('today')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() {
                        _focused = DateTime(_focused.year, _focused.month - 1, 1);
                      }),
                      icon: Icon(Icons.chevron_left, size: 18, color: cs.onSurface),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          monthLabel(_focused, l.isZh),
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _focused = DateTime(_focused.year, _focused.month + 1, 1);
                      }),
                      icon: Icon(Icons.chevron_right, size: 18, color: cs.onSurface),
                    ),
                  ],
                ),
                TableCalendar<Holiday>(
                  firstDay: DateTime.utc(1970, 1, 1),
                  lastDay: DateTime.utc(2100, 12, 31),
                  focusedDay: _focused,
                  headerVisible: false,
                  rowHeight: 40,
                  daysOfWeekHeight: 22,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {CalendarFormat.month: ''},
                  eventLoader: holidays.forDate,
                  selectedDayPredicate: (d) => isSameDay(d, _selected),
                  onDaySelected: (s, f) => setState(() {
                    _selected = s;
                    _focused = f;
                  }),
                  onPageChanged: (f) => setState(() => _focused = f),
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
                    todayTextStyle: TextStyle(color: cs.onSurface, fontSize: 13),
                    selectedDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    selectedTextStyle: TextStyle(color: cs.onPrimary, fontSize: 13),
                  ),
                  calendarBuilders: CalendarBuilders<Holiday>(
                    dowBuilder: (c, d) => Center(
                      child: Text(
                        wdShort(d.weekday, l.isZh),
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.35),
                          fontSize: 10,
                        ),
                      ),
                    ),
                    markerBuilder: (c, d, e) => e.isEmpty
                        ? null
                        : Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFB74D),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final s in HScope.values)
                FilterChip(
                  label: Text(
                    holidays.label(s, l.isZh),
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: _scopes.contains(s),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _scopes.add(s);
                    } else {
                      _scopes.remove(s);
                    }
                  }),
                ),
            ],
          ),
          if (picked.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.celebration_outlined, size: 16, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      picked.map((h) => h.name(l.isZh)).join(' · '),
                      style: TextStyle(color: cs.onSurface, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            l.t('holidaysMonth'),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (days.isEmpty)
            Text(
              l.t('noHolidays'),
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            )
          else
            for (final d in days)
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
                        '$d',
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
                          for (final h in month[d]!)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      h.name(l.isZh),
                                      style: TextStyle(
                                        color: cs.onSurface.withValues(alpha: 0.85),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    holidays.label(h.scope, l.isZh),
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(alpha: 0.35),
                                      fontSize: 10,
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
              ),
        ],
      ),
    );
  }
}

/* --------------------------------- 树洞页 --------------------------------- */

class TreeHolePage extends StatefulWidget {
  const TreeHolePage({super.key});

  @override
  State<TreeHolePage> createState() => _TreeHolePageState();
}

class _TreeHolePageState extends State<TreeHolePage> {
  bool _loading = false;
  bool _applied = false;
  bool _connected = false;
  Anon? _cur;
  int _req = 0;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _match() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _applied = false;
      _connected = false;
      _cur = null;
    });
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _cur = _anonPool[rnd.nextInt(_anonPool.length)];
    });
  }

  Future<void> _apply() async {
    final p = _cur;
    if (p == null || _applied) return;
    setState(() => _applied = true);
    _snack(context.t('applied'));
    final id = ++_req;
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted || id != _req) return;
    if (rnd.nextDouble() > 0.7) {
      setState(() => _applied = false);
      _snack(context.t('noReply'));
      return;
    }
    setState(() => _connected = true);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          ctx.t('consentTitle'),
          style: TextStyle(
            color: ctx.cs.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          ctx.t('consentBody', {'name': p.alias}),
          style: TextStyle(
            color: ctx.cs.onSurface.withValues(alpha: 0.7),
            fontSize: 13,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.t('sayHi'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cs = context.cs;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
                      const SizedBox(height: 4),
                      Text(
                        l.t('treeSub'),
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.forest_outlined, color: cs.onSurface.withValues(alpha: 0.35)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(child: Center(child: _body(l, cs))),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.onSurface,
                  foregroundColor: cs.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                onPressed: _loading ? null : _match,
                icon: Icon(_loading ? Icons.hourglass_bottom : Icons.shuffle),
                label: Text(
                  _loading ? l.t('matching') : (_cur == null ? l.t('match') : l.t('rematch')),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(L10n l, ColorScheme cs) {
    if (_loading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 18),
          Text(
            l.t('matching'),
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12),
          ),
        ],
      );
    }
    final p = _cur;
    if (p == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.nightlight_round,
              size: 46, color: cs.onSurface.withValues(alpha: 0.22)),
          const SizedBox(height: 16),
          Text(
            l.t('treeEmpty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                child: Text(p.alias.substring(0, 1),
                    style: TextStyle(color: cs.onSurface, fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.alias,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.meta(l.isZh),
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l.t('anon'),
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55), fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '「${p.text(l.isZh)}」',
            style: TextStyle(color: cs.onSurface, fontSize: 16, height: 1.8),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                side: BorderSide(color: cs.onSurface.withValues(alpha: 0.25)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
              ),
              onPressed: _applied
                  ? (_connected ? () => _snack(l.t('connectedTap')) : null)
                  : _apply,
              child: Text(
                _connected
                    ? l.t('connectedTap')
                    : (_applied ? l.t('applied') : l.t('apply')),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------------- 设置页 --------------------------------- */

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onAlarm});
  final VoidCallback onAlarm;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _cache = 0;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    if (!await dir.exists()) return 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> _measure() async {
    final d = await getTemporaryDirectory();
    final size = await _dirSize(d);
    if (mounted) setState(() => _cache = size);
  }

  Future<String> _persist(String src, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final dot = src.lastIndexOf('.');
    final ext = dot >= 0 ? src.substring(dot) : '';
    final dest = File('${dir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(src).copy(dest.path);
    return dest.path;
  }

  Future<String?> _pick(FileType type) async {
    final r = await FilePicker.platform.pickFiles(type: type);
    if (r == null || r.files.isEmpty) return null;
    return r.files.first.path;
  }

  Future<void> _wallpaper() async {
    try {
      final p = await _pick(FileType.image);
      if (p == null) return;
      await AppStore.I.setWallpaper(await _persist(p, 'wallpaper'));
      _snack(context.t('wallpaperLocal'));
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _ringtone() async {
    try {
      final p = await _pick(FileType.audio);
      if (p == null) return;
      await AppStore.I.setRingtone(await _persist(p, 'ringtone'));
      _snack(context.t('ringtoneLocal'));
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _clearCache() async {
    final keep = {AppStore.I.wallpaper, AppStore.I.ringtone}.whereType<String>().toSet();
    try {
      for (final dir in [
        await getTemporaryDirectory(),
        await getApplicationDocumentsDirectory(),
      ]) {
        if (!await dir.exists()) continue;
        await for (final e in dir.list(followLinks: false)) {
          if (e is! File || keep.contains(e.path)) continue;
          try {
            await e.delete();
          } catch (_) {}
        }
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (mounted) setState(() => _cache = 0);
      _snack(context.t('cacheCleared'));
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _language() async {
    await showAppSheet<void>(context, (ctx) {
      final l = ctx.l;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(l.t('language')),
          for (final e in [
            ('system', l.t('followSystem')),
            ('zh', '中文'),
            ('en', 'English'),
          ])
            ListTile(
              title: Text(e.$2, style: TextStyle(color: ctx.cs.onSurface)),
              trailing: AppStore.I.localeCode == e.$1
                  ? Icon(Icons.check, size: 18, color: ctx.cs.primary)
                  : null,
              onTap: () async {
                await AppStore.I.setLocale(e.$1);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 10),
        ],
      );
    });
  }

  Future<void> _theme() async {
    await showAppSheet<void>(context, (ctx) {
      final l = ctx.l;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(l.t('theme')),
          for (final e in [
            ('dark', l.t('themeDark')),
            ('light', l.t('themeLight')),
            ('system', l.t('followSystem')),
          ])
            ListTile(
              title: Text(e.$2, style: TextStyle(color: ctx.cs.onSurface)),
              trailing: AppStore.I.themeCode == e.$1
                  ? Icon(Icons.check, size: 18, color: ctx.cs.primary)
                  : null,
              onTap: () async {
                await AppStore.I.setTheme(e.$1);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 10),
        ],
      );
    });
  }

  Future<void> _editBirthday() async {
    final store = AppStore.I;
    if (!store.canEditBirthday) {
      _snack(context.t('bLocked'));
      return;
    }
    final v = await showBirthday(context, initial: store.birthday, allowCancel: true);
    if (v == null) return;
    await store.setBirthday(v);
    _snack(v);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cs = context.cs;
    final s = AppStore.I;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          Text(
            l.t('settingsTitle'),
            style: TextStyle(color: cs.onSurface, fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            l.t('settingsSub'),
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12),
          ),
          const SizedBox(height: 20),
          _Tile(
            icon: Icons.translate,
            title: l.t('language'),
            value: switch (s.localeCode) {
              'zh' => '中文',
              'en' => 'English',
              _ => l.t('followSystem'),
            },
            onTap: _language,
          ),
          _Tile(
            icon: Icons.brightness_6_outlined,
            title: l.t('theme'),
            value: switch (s.themeCode) {
              'light' => l.t('themeLight'),
              'system' => l.t('followSystem'),
              _ => l.t('themeDark'),
            },
            onTap: _theme,
          ),
          _Tile(
            icon: Icons.alarm,
            title: l.t('alarm'),
            value: '${two(s.alarmHour)}:${two(s.alarmMinute)} · ${l.t('dailyAlarm')}',
            onTap: widget.onAlarm,
          ),
          _Tile(
            icon: Icons.cake_outlined,
            title: l.t('birthday'),
            value: s.birthday ?? l.t('notSet'),
            footnote: s.canEditBirthday ? null : l.t('bLocked'),
            action: s.canEditBirthday ? l.t('edit') : null,
            onTap: s.canEditBirthday ? _editBirthday : null,
          ),
          _Tile(
            icon: Icons.wallpaper_outlined,
            title: l.t('wallpaper'),
            value: s.wallpaper == null ? l.t('wallpaperDefault') : l.t('wallpaperLocal'),
            buttons: [
              (l.t('changeWallpaper'), _wallpaper),
              (l.t('resetDefault'), () => AppStore.I.setWallpaper(null)),
            ],
          ),
          _Tile(
            icon: Icons.music_note_outlined,
            title: l.t('ringtone'),
            value: s.ringtone == null ? l.t('ringtoneDefault') : l.t('ringtoneLocal'),
            buttons: [
              (l.t('changeRingtone'), _ringtone),
              (l.t('resetDefault'), () => AppStore.I.setRingtone(null)),
            ],
          ),
          _Tile(
            icon: Icons.cleaning_services_outlined,
            title: l.t('clearCache'),
            value: '${l.t('cacheSize')} ${bytesLabel(_cache)}',
            action: l.t('clearCache'),
            onTap: _clearCache,
          ),
          _Tile(
            icon: Icons.shield_outlined,
            title: l.t('privacy'),
            value: l.t('privacyBody'),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Not alone 2.0.0',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.25), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
    this.action,
    this.footnote,
    this.buttons,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final String? action;
  final String? footnote;
  final List<(String, VoidCallback)>? buttons;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
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
              if (action != null)
                TextButton(
                  onPressed: onTap,
                  child: Text(action!, style: TextStyle(color: cs.primary, fontSize: 12)),
                )
              else if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withValues(alpha: 0.35)),
            ],
          ),
          const SizedBox(height: 6),
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
                    style: TextStyle(color: cs.primary.withValues(alpha: 0.8), fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          if (buttons != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final b in buttons!)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.onSurface,
                            side: BorderSide(color: cs.onSurface.withValues(alpha: 0.22)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: b.$2,
                          child: Text(b.$1, style: const TextStyle(fontSize: 12)),
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

/* ---------------------------------- 弹窗 ---------------------------------- */

Future<void> showCare(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: ctx.cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.favorite_rounded, color: Color(0xFFFF8A9B), size: 26),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  ctx.t('agree'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> showBirthday(
    BuildContext context, {
      String? initial,
      bool allowCancel = false,
    }) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: allowCancel,
        child: _BirthdayDialog(initial: initial, allowCancel: allowCancel),
      ),
    );

class _BirthdayDialog extends StatefulWidget {
  const _BirthdayDialog({this.initial, this.allowCancel = false});
  final String? initial;
  final bool allowCancel;

  @override
  State<_BirthdayDialog> createState() => _BirthdayDialogState();
}

class _BirthdayDialogState extends State<_BirthdayDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial ?? '');
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    final d = parseYmd(v);
    if (d == null) {
      setState(() => _err = context.t('bFormat'));
      return;
    }
    if (d.isAfter(DateTime.now())) {
      setState(() => _err = context.t('bFuture'));
      return;
    }
    Navigator.of(context).pop(ymd(d));
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final parsed = parseYmd(_c.text) ?? DateTime(1998, 6, 1);
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
    _c.text = ymd(picked);
    setState(() => _err = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        context.t('bAsk'),
        style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w600),
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
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: '1998-6-1',
              hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.28)),
              errorText: _err,
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.06),
              suffixIcon: IconButton(
                tooltip: context.t('bPick'),
                onPressed: _pick,
                icon: Icon(Icons.calendar_month_outlined, size: 20, color: cs.primary),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
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

Future<(int, int)?> showAlarmSheet(BuildContext context, int hour, int minute) {
  return showModalBottomSheet<(int, int)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AlarmSheet(hour: hour, minute: minute),
  );
}

class _AlarmSheet extends StatefulWidget {
  const _AlarmSheet({required this.hour, required this.minute});
  final int hour, minute;

  @override
  State<_AlarmSheet> createState() => _AlarmSheetState();
}

class _AlarmSheetState extends State<_AlarmSheet> {
  late int _h = widget.hour.clamp(0, 23);
  late int _m = widget.minute.clamp(0, 59);
  late final FixedExtentScrollController _hc = FixedExtentScrollController(initialItem: _h);
  late final FixedExtentScrollController _mc = FixedExtentScrollController(initialItem: _m);

  @override
  void dispose() {
    _hc.dispose();
    _mc.dispose();
    super.dispose();
  }

  Widget _wheel(int count, FixedExtentScrollController c, ValueChanged<int> onChanged) {
    final color = context.cs.onSurface;
    return SizedBox(
      width: 84,
      height: 172,
      child: ListWheelScrollView.useDelegate(
        controller: c,
        itemExtent: 46,
        diameterRatio: 1.6,
        perspective: 0.003,
        useMagnifier: true,
        magnification: 1.2,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (c, i) => Center(
            child: Text(
              two(i),
              style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w500),
            ),
          ),
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
                _wheel(24, _hc, (v) => setState(() => _h = v)),
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
                _wheel(60, _mc, (v) => setState(() => _m = v)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${two(_h)}:${two(_m)}',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55), fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.onSurface,
                  foregroundColor: cs.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                onPressed: () => Navigator.of(context).pop((_h, _m)),
                child: Text(
                  context.t('save'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showWakeUp(BuildContext context, String quote) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'alarm',
    barrierColor: Colors.white,
    transitionDuration: const Duration(milliseconds: 420),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, __) => Material(
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
                      BoxShadow(color: Color(0x44FFB300), blurRadius: 40, spreadRadius: 12),
                    ],
                  ),
                  child: const Icon(Icons.wb_sunny_rounded, size: 52, color: Color(0xFFFFB300)),
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
                  style: const TextStyle(fontSize: 15, height: 1.8, color: Color(0xFF6B5B49)),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2118),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      ctx.t('wokeUp'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/* ------------------------------ 吹蜡烛蛋糕 ------------------------------ */

Future<void> showCake(BuildContext context, String birthday) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(canPop: false, child: _CakeDialog(birthday: birthday)),
  );
}

class _CakeDialog extends StatefulWidget {
  const _CakeDialog({required this.birthday});
  final String birthday;

  @override
  State<_CakeDialog> createState() => _CakeDialogState();
}

class _CakeDialogState extends State<_CakeDialog> with TickerProviderStateMixin {
  static const int _tick = 80;
  static const double _thr = -22;
  static const int _need = 480;

  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late final AnimationController _blow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  final AudioRecorder _rec = AudioRecorder();
  final ValueNotifier<double> _meter = ValueNotifier<double>(0);

  StreamSubscription<Amplitude>? _amp;
  String? _tmp;
  bool _micOk = false;
  bool _out = false;
  int _loud = 0;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _amp?.cancel();
    _amp = null;
    unawaited(_shutdown());
    _flicker.dispose();
    _blow.dispose();
    _meter.dispose();
    super.dispose();
  }

  Future<void> _shutdown() async {
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
    try {
      await _rec.dispose();
    } catch (_) {}
    final p = _tmp;
    if (p != null) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _listen() async {
    try {
      if (!await _rec.hasPermission()) {
        if (mounted) setState(() => _micOk = false);
        return;
      }
      final dir = await getTemporaryDirectory();
      _tmp = '${dir.path}/blow_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, numChannels: 1),
        path: _tmp!,
      );
      _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: _tick)).listen(_onAmp);
      if (mounted) setState(() => _micOk = true);
    } catch (e) {
      debugPrint('mic: $e');
      if (mounted) setState(() => _micOk = false);
    }
  }

  void _onAmp(Amplitude a) {
    if (_out || !mounted) return;
    _meter.value = ((a.current + 60) / 60).clamp(0.0, 1.0);
    if (a.current >= _thr) {
      _loud += _tick;
    } else {
      _loud = max(0, _loud - _tick ~/ 2);
    }
    if (_loud >= _need) _extinguish();
  }

  Future<void> _extinguish() async {
    if (_out) return;
    setState(() => _out = true);
    _amp?.cancel();
    _amp = null;
    _meter.value = 0;
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
    await _blow.forward();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || _popped) return;
    _popped = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final birth = parseYmd(widget.birthday);
    final age = birth == null ? 0 : ageOn(birth, DateTime.now());
    final adult = age >= 18;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.9, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (c, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: v, child: child),
        ),
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
                style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 11),
              ),
              SizedBox(
                width: double.infinity,
                height: 190,
                child: CustomPaint(
                  painter: _CakePainter(flicker: _flicker, blow: _blow),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: Text(
                  _out
                      ? l.t('candlesOut')
                      : (_micOk ? l.t('cakeBlow') : l.t('micDenied')),
                  key: ValueKey('$_out-$_micOk'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _out
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
                  builder: (c, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD54F)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                  ),
                  onPressed: _out ? null : _extinguish,
                  child: Text(l.t('blowManual'), style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CakePainter extends CustomPainter {
  _CakePainter({required this.flicker, required this.blow})
      : super(repaint: Listenable.merge([flicker, blow]));

  final Animation<double> flicker;
  final Animation<double> blow;

  Path _flame(Offset b, double h, double w, double tilt) => Path()
    ..moveTo(b.dx, b.dy - h)
    ..quadraticBezierTo(b.dx + w, b.dy - h * 0.5, b.dx + tilt, b.dy)
    ..quadraticBezierTo(b.dx - w, b.dy - h * 0.5, b.dx, b.dy - h)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final lit = (1 - blow.value).clamp(0.0, 1.0);
    final smoke = blow.value;
    final t = flicker.value * 2 * pi;

    final plateRect = Rect.fromCenter(
      center: Offset(cx, h * 0.9),
      width: w * 0.82,
      height: h * 0.13,
    );
    canvas.drawOval(plateRect, Paint()..color = const Color(0x1FFFFFFF));
    canvas.drawOval(plateRect.deflate(6), Paint()..color = const Color(0x0DFFFFFF));

    final bodyW = w * 0.56;
    final bodyH = h * 0.34;
    final body = Rect.fromLTWH(cx - bodyW / 2, h * 0.87 - bodyH, bodyW, bodyH);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        body,
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: const Radius.circular(10),
        bottomRight: const Radius.circular(10),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFC7B2), Color(0xFFE2705A)],
        ).createShader(body),
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        body,
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: const Radius.circular(10),
        bottomRight: const Radius.circular(10),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x33000000)],
        ).createShader(body),
    );

    final cream = Rect.fromLTWH(body.left - 2, body.top - 6, bodyW + 4, 20);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cream, const Radius.circular(10)),
      Paint()..color = const Color(0xFFFFF3E6),
    );

    final dripPaint = Paint()..color = const Color(0xFFFFF3E6);
    for (var i = 0; i < 5; i++) {
      final x = cream.left + cream.width * (0.1 + i * 0.2);
      final r = 4.0 + (i.isEven ? 4.0 : 0.0);
      canvas.drawCircle(Offset(x, cream.bottom + r * 0.35), r, dripPaint);
    }

    final r2 = Random(11);
    for (var i = 0; i < 16; i++) {
      final x = body.left + 10 + r2.nextDouble() * (bodyW - 20);
      final y = cream.bottom + 12 + r2.nextDouble() * (bodyH - 34);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(r2.nextDouble() * pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 6, height: 2.4),
          const Radius.circular(2),
        ),
        Paint()
          ..color = const [
            Color(0xFFFFF176),
            Color(0xFFB3E5FC),
            Color(0xFFC5E1A5),
          ][i % 3],
      );
      canvas.restore();
    }

    final candleBottom = body.top + 4;
    const candleH = 42.0;

    for (var i = -1; i <= 1; i++) {
      final x = cx + i * bodyW * 0.26;
      final top = candleBottom - candleH;
      final candleRect = Rect.fromLTWH(x - 4.5, top, 9, candleH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(candleRect, const Radius.circular(3)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: i == 0
                ? const [Color(0xFFFFE082), Color(0xFFFFB300)]
                : const [Color(0xFFB3E5FC), Color(0xFF4FC3F7)],
          ).createShader(candleRect),
      );
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top - 6),
        Paint()
          ..color = const Color(0xFF5D4037)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );

      if (lit > 0.03) {
        final fl = 0.86 + 0.22 * sin(t + i * 1.5);
        final fh = 21 * lit * fl;
        final fw = 7.5 * lit * fl;
        final tilt = sin(t * 0.9 + i) * 1.4 + smoke * 7;
        final base = Offset(x, top - 7);

        final glowRect = Rect.fromCircle(
          center: Offset(x, base.dy - fh * 0.5),
          radius: 26 * lit,
        );
        canvas.drawCircle(
          glowRect.center,
          glowRect.width / 2,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0x59FFC107), Color(0x00FFC107)],
            ).createShader(glowRect),
        );

        final outerRect = Rect.fromLTWH(x - 14, base.dy - fh - 6, 28, fh + 10);
        canvas.drawPath(
          _flame(base, fh, fw, tilt),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF59D), Color(0xFFFFA000)],
            ).createShader(outerRect),
        );
        canvas.drawPath(
          _flame(
            Offset(base.dx, base.dy - 1),
            fh * 0.52,
            fw * 0.46,
            tilt * 0.45,
          ),
          Paint()..color = const Color(0xFFFFFDE7),
        );
      }

      if (smoke > 0.02) {
        for (var k = 0; k < 3; k++) {
          final p = (smoke * 1.6 - k * 0.28).clamp(0.0, 1.0);
          if (p <= 0.01) continue;
          final yy = top - 10 - p * 54;
          final xx = x + sin(p * 4 + k * 1.3) * 8;
          canvas.drawCircle(
            Offset(xx, yy),
            2.5 + p * 8,
            Paint()..color = Colors.white.withValues(alpha: 0.14 * (1 - p)),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CakePainter old) => false;
