// lib/main.dart
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

const String _amapKey = 'ef14bbc0e73e99e67fe94e0e5f5ed1d7';
const String _cityCode = '360300';
const List<String> _weekNames = ['一', '二', '三', '四', '五', '六', '日'];
final Random _rand = Random();

String _two(int v) => v.toString().padLeft(2, '0');

const List<String> _warmQuotes = [
  '闹钟响了，你一定很累吧，但生活推着你向前。',
  '慢慢来，你没有迟到，你只是在自己的时区里。',
  '今天也请好好吃饭，好好喝水，你不是一个人在撑。',
  '不用成为更好的人，先成为更舒服的人。',
  '如果没有人对你说早安，那我来。早安。',
  '你不必万事都赢，你只要还在，就很好。',
];

class _AnonProfile {
  const _AnonProfile(this.name, this.tag, this.text);
  final String name;
  final String tag;
  final String text;
}

const List<_AnonProfile> _anonPool = [
  _AnonProfile('匿名小猫', '22 岁 · 广州', '哪怕今天很糟糕，我也挺过来了'),
  _AnonProfile('走神的星星', '25 岁 · 成都', '凌晨两点睡不着，但没有告诉任何人'),
  _AnonProfile('抱膝的人', '19 岁 · 哈尔滨', '今天对喜欢的人说了早安，他没有回'),
  _AnonProfile('路过的风', '28 岁 · 杭州', '加班到十点，楼下的关东煮是唯一的温暖'),
  _AnonProfile('橘子汽水', '21 岁 · 长沙', '一个人搬家，一个人庆祝，也一个人长大'),
  _AnonProfile('安静的树', '30 岁 · 西安', '我在人群中，但我不在人群里'),
];

void main() {
  runApp(const NotAloneApp());
}

class NotAloneApp extends StatelessWidget {
  const NotAloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Not alone',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF8EC5FF),
        scaffoldBackgroundColor: const Color(0xFF06070C),
        splashFactory: InkSparkle.splashFactory,
      ),
      home: const RootPage(),
    );
  }
}

/* ------------------------------- 根页面 ------------------------------- */

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  late SharedPreferences _prefs;
  bool _ready = false;
  int _index = 0;
  bool _agreed = false;
  int _alarmHour = 7;
  int _alarmMinute = 0;
  String? _birthday;
  String? _wallpaper;
  String? _ringtone;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    _prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _agreed = _prefs.getBool('agreed') ?? false;
      _alarmHour = _prefs.getInt('alarmHour') ?? 7;
      _alarmMinute = _prefs.getInt('alarmMinute') ?? 0;
      _birthday = _prefs.getString('birthday');
      _wallpaper = _prefs.getString('wallpaper');
      _ringtone = _prefs.getString('ringtone');
      _ready = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _gate());
  }

  Future<void> _gate() async {
    if (!mounted) return;
    if (!_agreed) {
      await showCareDialog(context);
      await _prefs.setBool('agreed', true);
      if (mounted) setState(() => _agreed = true);
    }
    if (!mounted) return;
    if (_birthday == null || _birthday!.isEmpty) {
      final value = await showBirthdayDialog(context);
      if (value != null) {
        await _prefs.setString('birthday', value);
        if (mounted) setState(() => _birthday = value);
      }
    }
    if (!mounted) return;
    final bd = _birthday;
    if (bd != null && _isTodayBirthday(bd)) {
      await showCakeDialog(context, bd);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF23262F),
      ));
  }

  Future<void> _openAlarmSheet() async {
    final res = await showModalBottomSheet<List<int>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AlarmSheet(hour: _alarmHour, minute: _alarmMinute),
    );
    if (res == null || res.length < 2) return;
    await _prefs.setInt('alarmHour', res[0]);
    await _prefs.setInt('alarmMinute', res[1]);
    if (!mounted) return;
    setState(() {
      _alarmHour = res[0];
      _alarmMinute = res[1];
    });
    _toast('闹钟已设置为 ${_two(res[0])}:${_two(res[1])}');
  }

  Future<String> _persist(String src, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')) : '';
    final dest = File('${dir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(src).copy(dest.path);
    return dest.path;
  }

  Future<void> _pickWallpaper() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = res?.files.single.path;
      if (path == null) return;
      final saved = await _persist(path, 'wallpaper');
      await _prefs.setString('wallpaper', saved);
      if (!mounted) return;
      setState(() => _wallpaper = saved);
      _toast('壁纸已更换');
    } catch (e) {
      _toast('更换壁纸失败：$e');
    }
  }

  Future<void> _pickRingtone() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.audio);
      final path = res?.files.single.path;
      if (path == null) return;
      final saved = await _persist(path, 'ringtone');
      await _prefs.setString('ringtone', saved);
      if (!mounted) return;
      setState(() => _ringtone = saved);
      _toast('铃声已更换');
    } catch (e) {
      _toast('更换铃声失败：$e');
    }
  }

  Future<void> _resetWallpaper() async {
    await _prefs.remove('wallpaper');
    if (!mounted) return;
    setState(() => _wallpaper = null);
    _toast('已恢复默认壁纸');
  }

  Future<void> _resetRingtone() async {
    await _prefs.remove('ringtone');
    if (!mounted) return;
    setState(() => _ringtone = null);
    _toast('已恢复默认铃声');
  }

  Future<void> _editBirthday() async {
    final value = await showBirthdayDialog(context, initial: _birthday);
    if (value == null) return;
    await _prefs.setString('birthday', value);
    if (!mounted) return;
    setState(() => _birthday = value);
    _toast('生日已保存');
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF06070C),
        body: Center(child: CircularProgressIndicator(color: Colors.white24)),
      );
    }
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF07080E), Color(0xFF11131C), Color(0xFF05060A)],
              ),
            ),
          ),
          IndexedStack(
            index: _index,
            children: [
              HomePage(
                alarmHour: _alarmHour,
                alarmMinute: _alarmMinute,
                wallpaper: _wallpaper,
                ringtone: _ringtone,
                onOpenAlarmSheet: _openAlarmSheet,
              ),
              const TreeHolePage(),
              SettingsPage(
                alarmHour: _alarmHour,
                alarmMinute: _alarmMinute,
                birthday: _birthday,
                wallpaper: _wallpaper,
                ringtone: _ringtone,
                onOpenAlarmSheet: _openAlarmSheet,
                onPickWallpaper: _pickWallpaper,
                onPickRingtone: _pickRingtone,
                onResetWallpaper: _resetWallpaper,
                onResetRingtone: _resetRingtone,
                onEditBirthday: _editBirthday,
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.white,
        unselectedItemColor: const Color(0x8AFFFFFF),
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.nightlight_outlined),
            activeIcon: Icon(Icons.nightlight_round),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.forest_outlined),
            activeIcon: Icon(Icons.forest),
            label: '树洞',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/* -------------------------------- 首页 -------------------------------- */

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.alarmHour,
    required this.alarmMinute,
    required this.wallpaper,
    required this.ringtone,
    required this.onOpenAlarmSheet,
  });

  final int alarmHour;
  final int alarmMinute;
  final String? wallpaper;
  final String? ringtone;
  final VoidCallback onOpenAlarmSheet;

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
  String _weather = '正在获取…';
  String _weatherSub = '高德天气 · 漳州';

  @override
  void initState() {
    super.initState();
    _playerSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadWeather();
  }

  @override
  void dispose() {
    // 1) 先取消音频订阅，避免 dispose 后回调触发 setState
    _playerSub?.cancel();
    _playerSub = null;
    // 2) 取消时钟定时器
    _ticker?.cancel();
    _ticker = null;
    // 3) 最后释放播放器原生资源
    _player.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() => _now = now);
    _maybeRing(now);
  }

  void _maybeRing(DateTime now) {
    if (now.hour != widget.alarmHour || now.minute != widget.alarmMinute) return;
    final key = '${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute}';
    if (_firedKey == key) return;
    _firedKey = key;
    unawaited(_ring());
  }

  Future<void> _ring() async {
    if (_ringing || !mounted) return;
    _ringing = true;
    final quote = _warmQuotes[_rand.nextInt(_warmQuotes.length)];
    await _startAudio();
    if (!mounted) {
      _ringing = false;
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '闹钟',
      barrierColor: Colors.white,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (ctx, _, __) => _WakeUpOverlay(
        quote: quote,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
      transitionBuilder: (ctx, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );
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
      debugPrint('播放铃声失败: $e');
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('停止铃声失败: $e');
    }
  }

  Future<void> _loadWeather() async {
    final uri = Uri.parse(
      'https://restapi.amap.com/v3/weather/weatherInfo?key=$_amapKey&city=$_cityCode&extensions=base',
    );
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      final map = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final lives = map['lives'];
      if (lives is List && lives.isNotEmpty) {
        final live = lives.first as Map;
        if (!mounted) return;
        setState(() {
          _weather = '${live['weather']} ${live['temperature']}°C';
          _weatherSub = '${live['city']} · 湿度 ${live['humidity']}% · ${live['winddirection']}风';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _weather = '天气暂不可用';
        _weatherSub = '高德天气 · 漳州';
      });
    } catch (e) {
      debugPrint('天气请求失败: $e');
      if (!mounted) return;
      setState(() {
        _weather = '天气暂不可用';
        _weatherSub = '高德天气 · 漳州';
      });
    }
  }

  String _greeting() {
    final h = _now.hour;
    if (h < 6) return '夜深了，早点睡，世界明天再应付';
    if (h < 12) return '早上好，今天也会有人偷偷想你';
    if (h < 18) return '下午好，记得喝口水';
    return '晚上好，今天辛苦了';
  }

  @override
  Widget build(BuildContext context) {
    final night = _now.hour >= 18 || _now.hour < 6;
    return Stack(
      fit: StackFit.expand,
      children: [
        _background(night),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: night
                  ? const [Color(0x66000000), Color(0x1F000000), Color(0xCC000000)]
                  : const [Color(0x59000000), Color(0x14000000), Color(0x99000000)],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 100),
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
                          const Text(
                            'Not alone',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _greeting(),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '设置闹钟',
                      onPressed: widget.onOpenAlarmSheet,
                      icon: const Icon(Icons.alarm_add_outlined, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0x22FFFFFF),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _showCalendar = !_showCalendar),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.94, end: 1).animate(anim),
                            child: child,
                          ),
                        ),
                        child: _showCalendar ? _calendar() : _clock(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _glass(
                        icon: Icons.wb_cloudy_outlined,
                        title: '高德天气',
                        value: _weather,
                        subtitle: _weatherSub,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _glass(
                        icon: _playerState == PlayerState.playing
                            ? Icons.notifications_active
                            : Icons.alarm,
                        title: _playerState == PlayerState.playing ? '闹钟 · 响铃中' : '闹钟',
                        value: '${_two(widget.alarmHour)}:${_two(widget.alarmMinute)}',
                        subtitle: '每日提醒',
                        onTap: widget.onOpenAlarmSheet,
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

  Widget _background(bool night) {
    final p = widget.wallpaper;
    if (p != null && p.isNotEmpty && File(p).existsSync()) {
      return Image.file(
        File(p),
        key: ValueKey(p),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultBackground(night),
      );
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
            colors: [Color(0xFF05070F), Color(0xFF0A1128), Color(0xFF02030A)],
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

  Widget _clock() {
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
                '${_two(_now.hour)}:${_two(_now.minute)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 74,
                  height: 1,
                  letterSpacing: -2,
                  fontWeight: FontWeight.w200,
                ),
              ),
              Text(
                ':${_two(_now.second)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${_now.year}年${_now.month}月${_now.day}日 星期${_weekNames[_now.weekday - 1]}',
          style: const TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 0.8),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app_outlined, size: 12, color: Colors.white38),
            const SizedBox(width: 4),
            Text(
              _showCalendar ? '再点一下回到时间' : '点击查看日历',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _calendar() {
    return Container(
      key: const ValueKey('calendar'),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                }),
                icon: const Icon(Icons.chevron_left, color: Colors.white70, size: 18),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_focusedDay.year}年${_focusedDay.month}月',
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
                onPressed: () => setState(() {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                }),
                icon: const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
              ),
            ],
          ),
          TableCalendar(
            firstDay: DateTime.utc(1970, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            headerVisible: false,
            rowHeight: 32,
            daysOfWeekHeight: 20,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: '月'},
            selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
            onDaySelected: (selected, focused) => setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            }),
            onPageChanged: (focused) => setState(() => _focusedDay = focused),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              cellMargin: const EdgeInsets.all(2),
              defaultTextStyle: const TextStyle(color: Colors.white70, fontSize: 11),
              weekendTextStyle: const TextStyle(color: Colors.white54, fontSize: 11),
              todayDecoration: const BoxDecoration(
                color: Color(0x3DFFFFFF),
                shape: BoxShape.circle,
              ),
              todayTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
              selectedDecoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(color: Colors.black, fontSize: 11),
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: Colors.white38, fontSize: 10),
              weekendStyle: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glass({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x26FFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x3DFFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: Colors.white70),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/* ----------------------------- 唤醒全屏遮罩 ----------------------------- */

class _WakeUpOverlay extends StatelessWidget {
  const _WakeUpOverlay({required this.quote, required this.onDismiss});

  final String quote;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF7E8), Color(0xFFFFFFFF), Color(0xFFFFE9C7)],
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
                const Text(
                  '该起床啦',
                  style: TextStyle(
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
                    onPressed: onDismiss,
                    child: const Text(
                      '我醒了',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* -------------------------------- 树洞 -------------------------------- */

class TreeHolePage extends StatefulWidget {
  const TreeHolePage({super.key});

  @override
  State<TreeHolePage> createState() => _TreeHolePageState();
}

class _TreeHolePageState extends State<TreeHolePage> {
  bool _loading = false;
  bool _applied = false;
  bool _connected = false;
  _AnonProfile? _current;
  Timer? _consentTimer;

  @override
  void dispose() {
    _consentTimer?.cancel();
    _consentTimer = null;
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF23262F),
      ));
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
      _current = _anonPool[_rand.nextInt(_anonPool.length)];
    });
  }

  void _apply() {
    final p = _current;
    if (p == null || _applied) return;
    setState(() => _applied = true);
    _snack('已发送匿名申请，等待对方同意');
    _consentTimer?.cancel();
    _consentTimer = Timer(const Duration(seconds: 4), _simulateConsent);
  }

  Future<void> _simulateConsent() async {
    if (!mounted) return;
    final agree = _rand.nextInt(100) < 70;
    if (!agree) {
      if (!mounted) return;
      setState(() => _applied = false);
      _snack('对方还没有回应，也许 ta 也在犹豫');
      return;
    }
    if (!mounted) return;
    setState(() => _connected = true);
    final name = _current?.name ?? '匿名用户';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15171F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          '对方同意了你的申请',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '「$name」接受了你的双向授权，你们现在可以匿名互相倾诉了。',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('说点什么'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '树洞',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '匿名 · 双向授权 · 数据只存在这台手机里',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.forest_outlined, color: Colors.white38),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(child: Center(child: _body())),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                onPressed: _loading ? null : _match,
                icon: Icon(_loading ? Icons.hourglass_bottom : Icons.shuffle),
                label: Text(
                  _loading ? '正在寻找同频的人…' : (_current == null ? '随机匹配' : '换一个人'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70),
          ),
          SizedBox(height: 18),
          Text(
            '正在为你匹配一个愿意听你说话的人…',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      );
    }
    final p = _current;
    if (p == null) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.nightlight_round, size: 46, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            '这个世界很大，总有人和你同频',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0x33FFFFFF),
                child: Text(
                  p.name.substring(0, 1),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.tag,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x22FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '匿名',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '「${p.text}」',
            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.8),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0x66FFFFFF)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
              ),
              onPressed: _applied
                  ? (_connected ? () => _snack('你们已互为树洞，去打个招呼吧') : null)
                  : _apply,
              child: Text(
                _connected
                    ? '已互相授权 · 去打招呼'
                    : (_applied ? '已发送申请，等待对方同意' : '申请认识（双向授权）'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------- 设置 -------------------------------- */

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.alarmHour,
    required this.alarmMinute,
    required this.birthday,
    required this.wallpaper,
    required this.ringtone,
    required this.onOpenAlarmSheet,
    required this.onPickWallpaper,
    required this.onPickRingtone,
    required this.onResetWallpaper,
    required this.onResetRingtone,
    required this.onEditBirthday,
  });

  final int alarmHour;
  final int alarmMinute;
  final String? birthday;
  final String? wallpaper;
  final String? ringtone;
  final VoidCallback onOpenAlarmSheet;
  final VoidCallback onPickWallpaper;
  final VoidCallback onPickRingtone;
  final VoidCallback onResetWallpaper;
  final VoidCallback onResetRingtone;
  final VoidCallback onEditBirthday;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          const Text(
            '设置',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '所有数据保存在本机，卸载即删除',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 22),
          _tile(
            icon: Icons.alarm,
            title: '闹钟',
            value: '${_two(alarmHour)}:${_two(alarmMinute)} · 每日循环',
            actionLabel: '修改',
            onTap: onOpenAlarmSheet,
          ),
          _tile(
            icon: Icons.cake_outlined,
            title: '生日',
            value: (birthday == null || birthday!.isEmpty) ? '未设置' : birthday!,
            actionLabel: '修改',
            onTap: onEditBirthday,
          ),
          _tile(
            icon: Icons.wallpaper_outlined,
            title: '壁纸',
            value: (wallpaper == null || wallpaper!.isEmpty) ? '默认夕阳壁纸' : '来自本地相册',
            extra: Row(
              children: [
                Expanded(
                  child: _miniButton(label: '更换壁纸', onTap: onPickWallpaper),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _miniButton(label: '恢复默认', onTap: onResetWallpaper),
                ),
              ],
            ),
          ),
          _tile(
            icon: Icons.music_note_outlined,
            title: '闹钟铃声',
            value: (ringtone == null || ringtone!.isEmpty) ? '默认 Ring10.wav' : '来自本地文件',
            extra: Row(
              children: [
                Expanded(
                  child: _miniButton(label: '更换铃声', onTap: onPickRingtone),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _miniButton(label: '恢复默认', onTap: onResetRingtone),
                ),
              ],
            ),
          ),
          _tile(
            icon: Icons.shield_outlined,
            title: '隐私',
            value: '完全匿名 · 无账号 · 无服务器 · 无上传',
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Not alone 1.0.0',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniButton({required String label, required VoidCallback onTap}) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0x40FFFFFF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String value,
    String? actionLabel,
    VoidCallback? onTap,
    Widget? extra,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: onTap,
                  child: Text(
                    actionLabel,
                    style: const TextStyle(color: Color(0xFF8EC5FF), fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
          ),
          if (extra != null) ...[
            const SizedBox(height: 12),
            extra,
          ],
        ],
      ),
    );
  }
}

/* ----------------------------- 闹钟滑动弹窗 ----------------------------- */

class _AlarmSheet extends StatefulWidget {
  const _AlarmSheet({required this.hour, required this.minute});

  final int hour;
  final int minute;

  @override
  State<_AlarmSheet> createState() => _AlarmSheetState();
}

class _AlarmSheetState extends State<_AlarmSheet> {
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hCtrl;
  late final FixedExtentScrollController _mCtrl;

  @override
  void initState() {
    super.initState();
    _hour = widget.hour.clamp(0, 23);
    _minute = widget.minute.clamp(0, 59);
    _hCtrl = FixedExtentScrollController(initialItem: _hour);
    _mCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    super.dispose();
  }

  Widget _wheel({
    required int count,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 84,
      height: 180,
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
          builder: (context, index) => Center(
            child: Text(
              _two(index),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF12141C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '设置闹钟',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              '上下滑动选择时间，24 小时制',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _wheel(
                  count: 24,
                  controller: _hCtrl,
                  onChanged: (v) => setState(() => _hour = v),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    ':',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _wheel(
                  count: 60,
                  controller: _mCtrl,
                  onChanged: (v) => setState(() => _minute = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_two(_hour)}:${_two(_minute)} 唤醒你',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                onPressed: () => Navigator.of(context).pop(<int>[_hour, _minute]),
                child: const Text(
                  '保存闹钟',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------- 弹窗工具 ------------------------------- */

DateTime? _parseBirthday(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  final dt = DateTime(y, m, d);
  if (dt.year != y || dt.month != m || dt.day != d) return null;
  return dt;
}

bool _isTodayBirthday(String s) {
  final dt = _parseBirthday(s);
  if (dt == null) return false;
  final now = DateTime.now();
  return dt.month == now.month && dt.day == now.day;
}

int _ageOn(DateTime birth, DateTime now) {
  var age = now.year - birth.year;
  if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) {
    age--;
  }
  return age;
}

Future<void> showCareDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF14161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.favorite_rounded, color: Color(0xFFFF8A9B), size: 26),
            const SizedBox(height: 16),
            const Text(
              '如果你现实中真的很孤独，我想给你一点温暖。本应用完全匿名，请放心倾诉。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.9),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  '我同意并进入',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> showBirthdayDialog(BuildContext context, {String? initial}) {
  final controller = TextEditingController(text: initial ?? '');
  String? error;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: StatefulBuilder(
        builder: (ctx, setInner) {
          void submit() {
            final value = controller.text.trim();
            final dt = _parseBirthday(value);
            if (dt == null) {
              setInner(() => error = '请输入 YYYY-MM-DD 格式的有效日期');
              return;
            }
            if (dt.isAfter(DateTime.now())) {
              setInner(() => error = '生日不能在未来');
              return;
            }
            Navigator.of(ctx).pop(value);
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF14161F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text(
              '告诉我们你的生日',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '只在生日当天，我们会送你一块电子蛋糕。',
                  style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onSubmitted: (_) => submit(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '1998-06-01',
                    hintStyle: const TextStyle(color: Colors.white24),
                    errorText: error,
                    filled: true,
                    fillColor: const Color(0x14FFFFFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: submit,
                child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> showCakeDialog(BuildContext context, String birthday) {
  final birth = _parseBirthday(birthday);
  final age = birth == null ? 0 : _ageOn(birth, DateTime.now());
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: const Color(0xFF171A24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('🎂', textAlign: TextAlign.center, style: TextStyle(fontSize: 64)),
              const SizedBox(height: 12),
              Text(
                age >= 18 ? '恭喜成年' : '生日快乐',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                age >= 18 ? '从今天起，请为自己而活，也请偶尔为自己软弱。' : '愿新的一岁，你被世界温柔以待。',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.7),
              ),
              const SizedBox(height: 8),
              Text(
                '今天是你的第 ${age + 1} 个生日',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('吹灭蜡烛', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}