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

const String kAmapKey = 'ef14bbc0e73e99e67fe94e0e5f5ed1d7';
const String kCityCode = '360300';
const double kLat = 24.5130;
const double kLon = 117.6470;

/* ====================== 本地 Ollama 对话配置 ====================== */

/// 🚨 真机联调必改：
/// 127.0.0.1 在手机上指向手机自己，连不到你电脑。
/// 打包 APK 到真机测试时，必须改成电脑的局域网 IP，例如：
///   const String kOllamaBaseUrl = 'http://192.168.1.23:11434';
/// 查 IP：Windows 命令行执行 ipconfig，看「IPv4 地址」。
///
/// 另外电脑端还要做两件事，否则同样连不上：
///   1) setx OLLAMA_HOST 0.0.0.0，然后彻底退出 Ollama 再启动
///   2) 放行防火墙 11434 端口
const String kOllamaBaseUrl = 'http://192.168.1.4:11434';

/// 必须和 `ollama list` 里的 tag 完全一致
const String kOllamaModel = 'qwen3.5:4b';

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
    'December',
  ];
  return zh ? '${d.year}年${d.month}月' : '${en[d.month - 1]} ${d.year}';
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

/* ================================ i18n ================================= */

const Map<String, List<String>> _dict = {
  'app': ['Not alone', 'Not alone'],
  'navHome': ['首页', 'Home'],
  'navWeather': ['天气', 'Weather'],
  'navCalendar': ['日历', 'Calendar'],
  'navTree': ['树洞', 'Hollow'],
  'navSettings': ['设置', 'Settings'],
  'greetNight': ['夜深了，早点睡，世界明天再应付', 'Late night. Rest now.'],
  'greetMorning': ['早上好，今天也会有人偷偷想你', 'Good morning. Someone is thinking of you.'],
  'greetNoon': ['下午好，记得喝口水', 'Good afternoon. Drink some water.'],
  'greetEvening': ['晚上好，今天辛苦了', 'Good evening. You made it through.'],
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
  'wNetwork': ['网络异常，请检查连接后重试', 'Network error. Please retry.'],
  'wRetry': ['重试', 'Retry'],
  'wDetail': ['天气详情', 'Weather details'],
  'wCurrent': ['实时天气', 'Right now'],
  'wHourly': ['未来 12 小时', 'Next 12 hours'],
  'wDaily': ['未来几天', 'Next days'],
  'wExtras': ['逐小时与紫外线来自 Open-Meteo', 'Hourly & UV from Open-Meteo'],
  'wSource': ['数据来源：高德开放平台', 'Source: Amap Open Platform'],
  'calendarTitle': ['日历', 'Calendar'],
  'holidaysMonth': ['本月节日', 'Holidays this month'],
  'noHolidays': ['本月没有节日', 'No holidays this month'],
  'cn': ['中国', 'China'],
  'de': ['德国', 'Germany'],
  'us': ['美国', 'USA'],
  'today': ['今天', 'Today'],
  'treeTitle': ['树洞', 'Hollow'],
  'treeSub': ['匿名 · 双向授权 · 数据只在这台手机', 'Anonymous · mutual consent · on device'],
  'modeAi': ['树洞 AI', 'Hollow AI'],
  'modeMatch': ['同频匹配', 'Match'],
  'aiEmpty': ['这里只有你和树洞。\n想说什么都可以，我在听。', 'Just you and the hollow.\nSay anything. I am listening.'],
  'aiInputHint': ['说点什么吧，我在听……', 'Say something. I am listening…'],
  'aiTimeout': ['我这边有点慢……再等我一下好吗？', 'A little slow… give me a moment?'],
  'aiError': ['信号好像走丢了', 'Connection lost'],
  'aiErrorHint': ['看看电脑上的 Ollama 还在不在？', 'Is Ollama still running on the computer?'],
  'aiFallback': ['嗯……我在听，你继续说。', 'Mm… I am here. Go on.'],
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
  'themeSystem': ['跟随系统', 'System'],
  'changed': ['已切换', 'Updated'],
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
  'cakeOut': ['愿望会实现的', 'Your wish will come true'],
  'cakeManual': ['吹不动了？点这里吹灭', 'Tap to put them out'],
  'micOff': ['麦克风不可用，点击手动吹灭', 'Microphone unavailable, tap to put them out'],
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
      args.forEach((k, v) {
        s = s.replaceAll('{$k}', v);
      });
    }
    return s;
  }

  static L10n of(BuildContext context) =>
      Localizations.of<L10n>(context, L10n) ?? const L10n(Locale('zh'));

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  static const List<Locale> supportedLocales = [Locale('zh'), Locale('en')];
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'zh' || locale.languageCode == 'en';

  @override
  Future<L10n> load(Locale locale) => SynchronousFuture<L10n>(L10n(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<L10n> old) => false;
}

extension AppCtx on BuildContext {
  L10n get l10n => L10n.of(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
  String t(String key, [Map<String, String>? args]) => L10n.of(this).t(key, args);
}

/* ============================== app store ============================== */

class AppStore extends ChangeNotifier {
  AppStore._(this._prefs);

  static late AppStore I;

  static Future<void> load() async {
    I = AppStore._(await SharedPreferences.getInstance());
  }

  final SharedPreferences _prefs;

  String get localeCode => _prefs.getString('locale') ?? 'system';

  Locale? get locale {
    switch (localeCode) {
      case 'zh':
        return const Locale('zh');
      case 'en':
        return const Locale('en');
      default:
        return null;
    }
  }

  Future<void> setLocale(String code) async {
    await _prefs.setString('locale', code);
    notifyListeners();
  }

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

  bool get careAccepted => _prefs.getBool('careAccepted') ?? false;

  Future<void> acceptCare() async {
    await _prefs.setBool('careAccepted', true);
    notifyListeners();
  }

  int get alarmHour => _prefs.getInt('alarmHour') ?? 7;
  int get alarmMinute => _prefs.getInt('alarmMinute') ?? 0;

  Future<void> setAlarm(int hour, int minute) async {
    await _prefs.setInt('alarmHour', hour);
    await _prefs.setInt('alarmMinute', minute);
    notifyListeners();
  }

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
}

/* =============================== weather =============================== */

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
double _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse(_str(v)) ?? 0;

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
    if (_str(map['status']) != '1') throw const WeatherException(WeatherError.api);
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
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
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

/* =============================== holidays ============================== */

enum HolidayScope { cn, de, us }

class Holiday {
  const Holiday(this.scope, this.zh, this.en);

  final HolidayScope scope;
  final String zh;
  final String en;

  String name(bool zhMode) => zhMode ? zh : en;
}

class _FixedHoliday {
  const _FixedHoliday(this.month, this.day, this.scope, this.zh, this.en);

  final int month;
  final int day;
  final HolidayScope scope;
  final String zh;
  final String en;
}

class _EasterHoliday {
  const _EasterHoliday(this.offset, this.scope, this.zh, this.en);

  final int offset;
  final HolidayScope scope;
  final String zh;
  final String en;
}

class _NthHoliday {
  const _NthHoliday(
      this.month,
      this.weekday,
      this.nth,
      this.scope,
      this.zh,
      this.en,
      );

  final int month;
  final int weekday;
  final int nth;
  final HolidayScope scope;
  final String zh;
  final String en;
}

const List<_FixedHoliday> _fixedHolidays = [
  _FixedHoliday(1, 1, HolidayScope.cn, '元旦', "New Year's Day"),
  _FixedHoliday(4, 4, HolidayScope.cn, '清明节', 'Qingming Festival'),
  _FixedHoliday(5, 1, HolidayScope.cn, '劳动节', 'Labour Day'),
  _FixedHoliday(10, 1, HolidayScope.cn, '国庆节', 'National Day'),
  _FixedHoliday(1, 1, HolidayScope.de, '元旦', 'Neujahr'),
  _FixedHoliday(1, 6, HolidayScope.de, '主显节', 'Heilige Drei Könige'),
  _FixedHoliday(5, 1, HolidayScope.de, '劳动节', 'Tag der Arbeit'),
  _FixedHoliday(10, 3, HolidayScope.de, '德国统一日', 'Tag der Deutschen Einheit'),
  _FixedHoliday(10, 31, HolidayScope.de, '宗教改革日', 'Reformationstag'),
  _FixedHoliday(11, 1, HolidayScope.de, '万圣节', 'Allerheiligen'),
  _FixedHoliday(12, 25, HolidayScope.de, '圣诞第一节', '1. Weihnachtstag'),
  _FixedHoliday(12, 26, HolidayScope.de, '圣诞第二节', '2. Weihnachtstag'),
  _FixedHoliday(1, 1, HolidayScope.us, '新年', "New Year's Day"),
  _FixedHoliday(2, 14, HolidayScope.us, '情人节', "Valentine's Day"),
  _FixedHoliday(7, 4, HolidayScope.us, '独立日', 'Independence Day'),
  _FixedHoliday(10, 31, HolidayScope.us, '万圣夜', 'Halloween'),
  _FixedHoliday(12, 25, HolidayScope.us, '圣诞节', 'Christmas Day'),
];

const List<_EasterHoliday> _easterHolidays = [
  _EasterHoliday(-2, HolidayScope.de, '耶稣受难日', 'Karfreitag'),
  _EasterHoliday(1, HolidayScope.de, '复活节星期一', 'Ostermontag'),
  _EasterHoliday(39, HolidayScope.de, '耶稣升天节', 'Christi Himmelfahrt'),
  _EasterHoliday(50, HolidayScope.de, '圣灵降临节星期一', 'Pfingstmontag'),
];

const List<_NthHoliday> _nthHolidays = [
  _NthHoliday(5, 7, 2, HolidayScope.us, '母亲节', "Mother's Day"),
  _NthHoliday(6, 7, 3, HolidayScope.us, '父亲节', "Father's Day"),
  _NthHoliday(11, 4, 4, HolidayScope.us, '感恩节', 'Thanksgiving'),
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

  List<Holiday> forDate(DateTime date) {
    final out = <Holiday>[];

    for (final h in _fixedHolidays) {
      if (h.month == date.month && h.day == date.day) {
        out.add(Holiday(h.scope, h.zh, h.en));
      }
    }

    final easterDate = easter(date.year);
    for (final h in _easterHolidays) {
      final target = easterDate.add(Duration(days: h.offset));
      if (target.month == date.month && target.day == date.day) {
        out.add(Holiday(h.scope, h.zh, h.en));
      }
    }

    for (final h in _nthHolidays) {
      if (h.month != date.month) continue;
      final day = _nthWeekday(date.year, h.month, h.weekday, h.nth);
      if (day == date.day) out.add(Holiday(h.scope, h.zh, h.en));
    }

    final lunar = _lunarDates[date.year];
    if (lunar != null) {
      lunar.forEach((key, md) {
        if (md[0] == date.month && md[1] == date.day) {
          final names = _lunarNames[key];
          if (names != null) {
            out.add(Holiday(HolidayScope.cn, names[0], names[1]));
          }
        }
      });
    }

    return out;
  }

  Map<int, List<Holiday>> forMonth(
      int year,
      int month,
      Set<HolidayScope> scopes,
      ) {
    final result = <int, List<Holiday>>{};
    final total = DateTime(year, month + 1, 0).day;
    for (var day = 1; day <= total; day++) {
      final list = forDate(DateTime(year, month, day))
          .where((h) => scopes.contains(h.scope))
          .toList();
      if (list.isNotEmpty) result[day] = list;
    }
    return result;
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
    final first = DateTime(year, month, 1);
    final delta = (weekday - first.weekday) % 7;
    return 1 + delta + (nth - 1) * 7;
  }

  String scopeLabel(HolidayScope scope, bool zh) {
    switch (scope) {
      case HolidayScope.cn:
        return zh ? '中国' : 'CN';
      case HolidayScope.de:
        return zh ? '德国' : 'DE';
      case HolidayScope.us:
        return zh ? '美国' : 'US';
    }
  }
}

const HolidayEngine holidayEngine = HolidayEngine();

/* ============================== tree hole ============================== */

class AnonPost {
  const AnonPost(
      this.alias,
      this.metaZh,
      this.metaEn,
      this.textZh,
      this.textEn,
      );

  final String alias;
  final String metaZh;
  final String metaEn;
  final String textZh;
  final String textEn;

  String meta(bool zh) => zh ? metaZh : metaEn;

  String text(bool zh) => zh ? textZh : textEn;
}

const List<AnonPost> anonPool = [
  AnonPost(
    '匿名小猫',
    '22 岁 · 广州',
    '22 · Guangzhou',
    '哪怕今天很糟糕，我也挺过来了',
    'Today was awful. But I made it through.',
  ),
  AnonPost(
    '走神的星星',
    '25 岁 · 成都',
    '25 · Chengdu',
    '凌晨两点睡不着，但没有告诉任何人',
    'Awake at 2am. I told nobody.',
  ),
  AnonPost(
    '抱膝的人',
    '19 岁 · 哈尔滨',
    '19 · Harbin',
    '今天对喜欢的人说了早安，他没有回',
    'I said good morning to my crush. No reply.',
  ),
  AnonPost(
    '路过的风',
    '28 岁 · 杭州',
    '28 · Hangzhou',
    '加班到十点，楼下的关东煮是唯一的温暖',
    'Worked till ten. Oden downstairs was the only warmth.',
  ),
  AnonPost(
    '橘子汽水',
    '21 岁 · 长沙',
    '21 · Changsha',
    '一个人搬家，一个人庆祝，也一个人长大',
    'Moved alone, celebrated alone, grew up alone.',
  ),
  AnonPost(
    '安静的树',
    '30 岁 · 西安',
    '30 · Xi’an',
    '我在人群中，但我不在人群里',
    'I am among people, but not in them.',
  ),
];

/* ================================== app ================================ */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStore.load();
  runApp(const NotAloneApp());
}

class NotAloneApp extends StatelessWidget {
  const NotAloneApp({super.key});

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: const Color(0xFF8EC5FF),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF07080E)
          : const Color(0xFFF4F5F9),
      splashFactory: InkSparkle.splashFactory,
    );
  }

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
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: const RootPage(),
        );
      },
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(context.t('alarmSaved', {'t': label})),
        ),
      );
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
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: cs.onSurface,
            unselectedItemColor: cs.onSurface.withValues(alpha: 0.5),
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

/* ============================= shared widgets ========================== */

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

  /// true：铺在壁纸上的白色玻璃；false：跟随当前主题
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final base = onImage ? Colors.white : cs.onSurface;

    final Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: onImage
                ? Colors.white.withValues(alpha: 0.16)
                : cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: base.withValues(alpha: 0.22)),
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
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
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

/* ============================== mini calendar ========================== */

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
    final l = context.l10n;

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
                icon: const Icon(
                  Icons.chevron_left,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    monthLabel(focusedDay, l.isZh),
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
                icon: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.white,
                ),
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
            eventLoader: holidayEngine.forDate,
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
                    wdShort(day.weekday, l.isZh),
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

/* ============================ weather widgets ========================== */

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
      [
        l.t('uv'),
        snapshot.uv == null ? '—' : snapshot.uv!.toStringAsFixed(1),
      ],
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
                  width: 96,
                  child: Text(
                    '${day.date.month}/${day.date.day} '
                        '${wdFull(day.date.weekday, l.isZh)}',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l.isZh ? day.dayDesc : descEn(day.dayDesc),
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
                        '${l.isZh ? data.now.desc : descEn(data.now.desc)} · '
                            '${data.now.city}',
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

/* =============================== home page ============================= */

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
  int _quoteIndex = 1;

  @override
  void initState() {
    super.initState();
    _quoteIndex = rnd.nextInt(6) + 1;
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
    // 1) 先取消音频订阅，避免 dispose 后回调触发 setState
    _playerSub?.cancel();
    _playerSub = null;
    // 2) 取消时钟定时器
    _ticker?.cancel();
    _ticker = null;
    // 3) 最后释放原生播放器
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

    final quote = context.t('q${rnd.nextInt(6) + 1}');
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
                Color(0x94000000),
                Color(0x33000000),
                Color(0xE6000000),
              ]
                  : const [
                Color(0x6B000000),
                Color(0x22000000),
                Color(0xB8000000),
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
                              letterSpacing: 0.6,
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
                      tooltip: l.t('alarm'),
                      onPressed: widget.onOpenAlarm,
                      icon: const Icon(
                        Icons.alarm_add_outlined,
                        color: Colors.white,
                      ),
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
                      onTap: () => setState(() => _showCalendar = !_showCalendar),
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
                _buildQuoteStrip(l),
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
      errorBuilder: (_, __, ___) {
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D), Color(0xFF4A3AFF)],
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
          '${_now.year}-${two(_now.month)}-${two(_now.day)} '
              '${wdFull(_now.weekday, l.isZh)}',
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

  Widget _buildQuoteStrip(L10n l) {
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
              const Icon(
                Icons.favorite,
                size: 13,
                color: Color(0xFFFFB4C1),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.t('q$_quoteIndex'),
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
          value: '${data.now.temp}°C  '
              '${l.isZh ? data.now.desc : descEn(data.now.desc)}',
          subtitle: '${l.t('humidity')} ${data.now.humidity}% · '
              '${data.now.windDir} ${data.now.windPower}',
          onTap: () => showWeatherSheet(context, widget.weather),
        );
      },
    );
  }
}

/* ============================= weather page ============================ */

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
                      value: '${data.now.temp}°C  '
                          '${l.isZh ? data.now.desc : descEn(data.now.desc)}',
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

/* ============================ calendar page ============================ */

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  final Set<HolidayScope> _scopes = HolidayScope.values.toSet();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    final monthHolidays = holidayEngine.forMonth(
      _focusedDay.year,
      _focusedDay.month,
      _scopes,
    );
    final days = monthHolidays.keys.toList()..sort();
    final dayHolidays = holidayEngine
        .forDate(_selectedDay)
        .where((h) => _scopes.contains(h.scope))
        .toList();

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
                      '${ymd(_selectedDay)} '
                          '${wdFull(_selectedDay.weekday, l.isZh)}',
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
                          monthLabel(_focusedDay, l.isZh),
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
                  eventLoader: holidayEngine.forDate,
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
                          wdShort(day.weekday, l.isZh),
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final scope in HolidayScope.values)
                FilterChip(
                  label: Text(
                    holidayEngine.scopeLabel(scope, l.isZh),
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: _scopes.contains(scope),
                  onSelected: (on) {
                    setState(() {
                      if (on) {
                        _scopes.add(scope);
                      } else {
                        _scopes.remove(scope);
                      }
                    });
                  },
                ),
            ],
          ),
          if (dayHolidays.isNotEmpty) ...[
            const SizedBox(height: 12),
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
                      dayHolidays.map((h) => h.name(l.isZh)).join(' · '),
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
                                      holiday.name(l.isZh),
                                      style: TextStyle(
                                        color: cs.onSurface
                                            .withValues(alpha: 0.85),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    holidayEngine.scopeLabel(
                                      holiday.scope,
                                      l.isZh,
                                    ),
                                    style: TextStyle(
                                      color: cs.onSurface
                                          .withValues(alpha: 0.35),
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

/* ============================= tree hole page ========================== */

enum _TreeHoleMode { ai, match }

class TreeHolePage extends StatefulWidget {
  const TreeHolePage({super.key});

  @override
  State<TreeHolePage> createState() => _TreeHolePageState();
}

class _TreeHolePageState extends State<TreeHolePage> {
  _TreeHoleMode _mode = _TreeHoleMode.ai;

  bool _loading = false;
  bool _applied = false;
  bool _connected = false;
  AnonPost? _current;
  int _requestId = 0;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _match() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _applied = false;
      _connected = false;
      _current = null;
    });

    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    setState(() {
      _loading = false;
      _current = anonPool[rnd.nextInt(anonPool.length)];
    });
  }

  Future<void> _apply() async {
    final post = _current;
    if (post == null || _applied) return;

    setState(() => _applied = true);
    _snack(context.t('applied'));

    final id = ++_requestId;
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted || id != _requestId) return;

    if (rnd.nextDouble() > 0.7) {
      setState(() => _applied = false);
      _snack(context.t('noReply'));
      return;
    }

    setState(() => _connected = true);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: ctx.cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            ctx.t('consentTitle'),
            style: TextStyle(
              color: ctx.cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            ctx.t('consentBody', {'name': post.alias}),
            style: TextStyle(
              color: ctx.cs.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.7,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ctx.t('sayHi')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.cs;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Icon(
                    Icons.forest_outlined,
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildModeSwitch(l, cs),
            ),
            const SizedBox(height: 12),
            // IndexedStack：切换模式时保留 AI 对话记录，不会清空
            Expanded(
              child: IndexedStack(
                index: _mode.index,
                sizing: StackFit.expand,
                children: [
                  const AiChatPanel(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Column(
                      children: [
                        Expanded(child: Center(child: _buildBody(l, cs))),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.onSurface,
                              foregroundColor: cs.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            onPressed: _loading ? null : _match,
                            icon: Icon(
                              _loading ? Icons.hourglass_bottom : Icons.shuffle,
                            ),
                            label: Text(
                              _loading
                                  ? l.t('matching')
                                  : (_current == null
                                  ? l.t('match')
                                  : l.t('rematch')),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitch(L10n l, ColorScheme cs) {
    Widget item(_TreeHoleMode mode, String label, IconData icon) {
      final active = _mode == mode;
      final fg = active ? cs.surface : cs.onSurface.withValues(alpha: 0.55);
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _mode = mode),
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
          item(_TreeHoleMode.ai, l.t('modeAi'), Icons.auto_awesome_outlined),
          item(_TreeHoleMode.match, l.t('modeMatch'), Icons.shuffle),
        ],
      ),
    );
  }

  Widget _buildBody(L10n l, ColorScheme cs) {
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
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    final post = _current;
    if (post == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.nightlight_round,
            size: 46,
            color: cs.onSurface.withValues(alpha: 0.22),
          ),
          const SizedBox(height: 16),
          Text(
            l.t('treeEmpty'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 13,
            ),
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
                child: Text(
                  post.alias.substring(0, 1),
                  style: TextStyle(color: cs.onSurface, fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.alias,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      post.meta(l.isZh),
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l.t('anon'),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '「${post.text(l.isZh)}」',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                side: BorderSide(
                  color: cs.onSurface.withValues(alpha: 0.25),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(23),
                ),
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

/* ============================== ai chat panel ========================== */

class AiChatPanel extends StatefulWidget {
  const AiChatPanel({super.key});

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatMessage {
  const _AiChatMessage(this.text, {required this.isUser});

  final String text;
  final bool isUser;
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_AiChatMessage> _messages = [];
  bool _sending = false;

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

  Future<void> _handleSend() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    _inputCtrl.clear();
    setState(() {
      _messages.add(_AiChatMessage(text, isUser: true));
      _sending = true;
    });
    _scrollToBottom();

    try {
      final reply = await _askOllama();
      if (!mounted) return;
      setState(() => _messages.add(_AiChatMessage(reply, isUser: false)));
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _messages.add(
        _AiChatMessage(context.t('aiTimeout'), isUser: false),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_AiChatMessage(
        '${context.t('aiError')}（$e）\n${context.t('aiErrorHint')}',
        isUser: false,
      )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<String> _askOllama() async {
    // /api/generate 是无状态的：把最近 10 条对话拼进 prompt，模型才记得上文
    final recent = _messages.length > 10
        ? _messages.sublist(_messages.length - 10)
        : _messages;
    final buffer = StringBuffer();
    for (final m in recent) {
      buffer.writeln('${m.isUser ? '用户' : '你'}：${m.text}');
    }
    buffer.writeln('你：');

    final response = await http
        .post(
      Uri.parse('$kOllamaBaseUrl/api/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': kOllamaModel,
        // 关键：system 提示词注入在这里
        'system': kTreeHoleSystemPrompt,
        'prompt': buffer.toString(),
        'stream': false,
        // 关闭 qwen3 的思考链，避免回复又慢又长；
        // 对话期间保持模型常驻内存，减少冷启动等待
        'keep_alive': '30m',
        'options': {
          'temperature': 0.85,
          'top_p': 0.9,
          'num_predict': 120,
        },
      }),
    )
    // 4b 模型冷启动可能很慢，给足 120 秒
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    // 用 bodyBytes + utf8 解码，避免中文乱码
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final reply = (data['response'] as String? ?? '').trim();

    return reply.isEmpty ? context.t('aiFallback') : reply;
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
                return _TypingBubble(cs: cs);
              }
              return _MessageBubble(
                message: _messages[index],
                cs: cs,
              );
            },
          ),
        ),
        _buildInputBar(cs),
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

  Widget _buildInputBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              style: TextStyle(color: cs.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: context.t('aiInputHint'),
                hintStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _handleSend,
            icon: _sending
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.cs});

  final _AiChatMessage message;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: isUser ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

/* ============================== settings page ========================== */

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
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
            value: store.localeCode == 'zh'
                ? '中文'
                : store.localeCode == 'en'
                ? 'English'
                : l.t('followSystem'),
            onTap: _pickLanguage,
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
            icon: Icons.alarm,
            title: l.t('alarm'),
            value: '${two(store.alarmHour)}:${two(store.alarmMinute)} · '
                '${l.t('dailyAlarm')}',
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
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Not alone 2.1.0',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.25),
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
                              color: cs.onSurface.withValues(alpha: 0.22),
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

/* ================================ dialogs ============================== */

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
              hintStyle: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.28),
              ),
              errorText: _error,
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.06),
              suffixIcon: IconButton(
                tooltip: context.t('bPick'),
                onPressed: _pickDate,
                icon: Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: cs.primary,
                ),
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

class _CakeDialogState extends State<CakeDialog>
    with TickerProviderStateMixin {
  static const int _tickMs = 80;
  static const double _thresholdDb = -22;
  static const int _needMs = 480;

  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late final AnimationController _blow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

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
    _flicker.dispose();
    _blow.dispose();
    _meter.dispose();
    super.dispose();
  }

  Future<void> _shutdownRecorder() async {
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {
      // 设备不支持时忽略
    }
    try {
      await _recorder.dispose();
    } catch (_) {
      // 忽略
    }
    final path = _tempPath;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 忽略
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
      // 忽略
    }
    await _blow.forward();
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
              SizedBox(
                width: double.infinity,
                height: 190,
                child: CustomPaint(
                  painter: CakePainter(flicker: _flicker, blow: _blow),
                ),
              ),
              const SizedBox(height: 4),
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

class CakePainter extends CustomPainter {
  CakePainter({required this.flicker, required this.blow})
      : super(repaint: Listenable.merge([flicker, blow]));

  final Animation<double> flicker;
  final Animation<double> blow;

  Path _flamePath(Offset base, double height, double width, double tilt) {
    return Path()
      ..moveTo(base.dx, base.dy - height)
      ..quadraticBezierTo(
        base.dx + width,
        base.dy - height * 0.5,
        base.dx + tilt,
        base.dy,
      )
      ..quadraticBezierTo(
        base.dx - width,
        base.dy - height * 0.5,
        base.dx,
        base.dy - height,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final centerX = width / 2;
    final lit = (1 - blow.value).clamp(0.0, 1.0);
    final smoke = blow.value;
    final phase = flicker.value * 2 * pi;

    final plateRect = Rect.fromCenter(
      center: Offset(centerX, height * 0.9),
      width: width * 0.82,
      height: height * 0.13,
    );
    canvas.drawOval(plateRect, Paint()..color = const Color(0x1FFFFFFF));
    canvas.drawOval(
      plateRect.deflate(6),
      Paint()..color = const Color(0x0DFFFFFF),
    );

    final bodyWidth = width * 0.56;
    final bodyHeight = height * 0.34;
    final bodyRect = Rect.fromLTWH(
      centerX - bodyWidth / 2,
      height * 0.87 - bodyHeight,
      bodyWidth,
      bodyHeight,
    );

    final bodyRRect = RRect.fromRectAndCorners(
      bodyRect,
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );

    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFC7B2), Color(0xFFE2705A)],
        ).createShader(bodyRect),
    );

    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x33000000)],
        ).createShader(bodyRect),
    );

    final creamRect = Rect.fromLTWH(
      bodyRect.left - 2,
      bodyRect.top - 6,
      bodyWidth + 4,
      20,
    );
    final creamPaint = Paint()..color = const Color(0xFFFFF3E6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(creamRect, const Radius.circular(10)),
      creamPaint,
    );

    for (var i = 0; i < 5; i++) {
      final x = creamRect.left + creamRect.width * (0.1 + i * 0.2);
      final radius = 4.0 + (i.isEven ? 4.0 : 0.0);
      canvas.drawCircle(
        Offset(x, creamRect.bottom + radius * 0.35),
        radius,
        creamPaint,
      );
    }

    final sprinkleRandom = Random(11);
    for (var i = 0; i < 16; i++) {
      final x = bodyRect.left + 10 + sprinkleRandom.nextDouble() * (bodyWidth - 20);
      final y = creamRect.bottom +
          12 +
          sprinkleRandom.nextDouble() * (bodyHeight - 34);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(sprinkleRandom.nextDouble() * pi);
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

    final candleBottom = bodyRect.top + 4;
    const candleHeight = 42.0;

    for (var i = -1; i <= 1; i++) {
      final x = centerX + i * bodyWidth * 0.26;
      final candleTop = candleBottom - candleHeight;
      final candleRect = Rect.fromLTWH(x - 4.5, candleTop, 9, candleHeight);

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
        Offset(x, candleTop),
        Offset(x, candleTop - 6),
        Paint()
          ..color = const Color(0xFF5D4037)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );

      if (lit > 0.03) {
        final flick = 0.86 + 0.22 * sin(phase + i * 1.5);
        final flameHeight = 21 * lit * flick;
        final flameWidth = 7.5 * lit * flick;
        final tilt = sin(phase * 0.9 + i) * 1.4 + smoke * 7;
        final base = Offset(x, candleTop - 7);

        final glowRect = Rect.fromCircle(
          center: Offset(x, base.dy - flameHeight * 0.5),
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

        final flameRect = Rect.fromLTWH(
          x - 14,
          base.dy - flameHeight - 6,
          28,
          flameHeight + 10,
        );
        canvas.drawPath(
          _flamePath(base, flameHeight, flameWidth, tilt),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF59D), Color(0xFFFFA000)],
            ).createShader(flameRect),
        );
        canvas.drawPath(
          _flamePath(
            Offset(base.dx, base.dy - 1),
            flameHeight * 0.52,
            flameWidth * 0.46,
            tilt * 0.45,
          ),
          Paint()..color = const Color(0xFFFFFDE7),
        );
      }

      if (smoke > 0.02) {
        for (var k = 0; k < 3; k++) {
          final progress = (smoke * 1.6 - k * 0.28).clamp(0.0, 1.0);
          if (progress <= 0.01) continue;
          final smokeY = candleTop - 10 - progress * 54;
          final smokeX = x + sin(progress * 4 + k * 1.3) * 8;
          canvas.drawCircle(
            Offset(smokeX, smokeY),
            2.5 + progress * 8,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.14 * (1 - progress)),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(CakePainter oldDelegate) => false;
}
