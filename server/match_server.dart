// =============================================================================
// Not alone 3.0 — 最小真人匹配服务器（参考实现）
// -----------------------------------------------------------------------------
// 零第三方依赖，只用 dart:io。
//
// 启动：
//   dart run server/match_server.dart
//   PORT=9000 dart run server/match_server.dart
//
// App 连接：
//   flutter run --dart-define=TREE_HOLE_API=http://192.168.1.10:8787
//
// 说明：
//   · 这是内存版，进程重启后队列清空。
//   · 仅用于开发 / 自建小规模服务；生产环境请加 TLS、鉴权、限流和内容审计。
//   · 消息只在中转时经过内存，不落库。
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final Random _random = Random.secure();

const List<String> _aliases = [
  '晚风',
  '月亮',
  '小猫',
  '路灯',
  '橘子',
  '树影',
  '云朵',
  '海盐',
  '夜航船',
  '纸飞机',
  '北极星',
  '小雨',
  '蒲公英',
  '萤火',
  '旧唱片',
  'Wanderer',
  'Moon',
  'Breeze',
  'Pebble',
  'Lantern',
];

class Peer {
  Peer({
    required this.requestId,
    required this.anonId,
    required this.lang,
    required this.country,
    required this.token,
    required this.alias,
  });

  final String requestId;
  final String anonId;
  final String lang;
  final String country;
  final String token;
  final String alias;

  WebSocket? socket;
  Peer? partner;
  bool accepted = false;
}

final List<Peer> _pending = [];
final Map<String, Peer> _byToken = {};
final Map<String, Peer> _byRequest = {};

int get _port => int.tryParse(Platform.environment['PORT'] ?? '') ?? 8787;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
  stdout.writeln('Not alone match server listening on 0.0.0.0:${server.port}');
  stdout.writeln('POST /v1/match   WebSocket /v1/ws');

  await for (final request in server) {
    try {
      if (request.method == 'POST' && request.uri.path == '/v1/match') {
        await _handleMatch(request);
      } else if (request.uri.path == '/v1/ws' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        await _handleSocket(request);
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('not found');
        await request.response.close();
      }
    } catch (error, stack) {
      stderr.writeln('request failed: $error\n$stack');
      try {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('bad request');
        await request.response.close();
      } catch (_) {
        // ignore
      }
    }
  }
}

Future<void> _handleMatch(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  final data = raw.isEmpty
      ? <String, dynamic>{}
      : (jsonDecode(raw) as Map).cast<String, dynamic>();

  final requestId = _id();
  final token = _id();

  final peer = Peer(
    requestId: requestId,
    anonId: (data['anonId'] as String?) ?? 'anon',
    lang: (data['lang'] as String?) ?? 'en',
    country: (data['country'] as String?) ?? 'CN',
    token: token,
    alias: _aliases[_random.nextInt(_aliases.length)],
  );

  _byToken[token] = peer;
  _byRequest[requestId] = peer;
  _pending.add(peer);

  final host = request.headers.value(HttpHeaders.hostHeader) ??
      'localhost:${request.connectionInfo?.localPort ?? _port}';
  final forwarded = request.headers.value('x-forwarded-proto');
  final scheme = forwarded == 'https' ? 'wss' : 'ws';

  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode({
      'requestId': requestId,
      'token': token,
      'ws': '$scheme://$host/v1/ws?token=$token',
    }));
  await request.response.close();

  _tryMatch();
}

Future<void> _handleSocket(HttpRequest request) async {
  final token = request.uri.queryParameters['token'] ?? '';
  final peer = _byToken.remove(token);

  if (peer == null) {
    request.response
      ..statusCode = HttpStatus.forbidden
      ..write('invalid token');
    await request.response.close();
    return;
  }

  final socket = await WebSocketTransformer.upgrade(request);
  peer.socket = socket;

  socket.listen(
    (data) => _onMessage(peer, data),
    onDone: () => _onClose(peer),
    onError: (Object _) => _onClose(peer),
    cancelOnError: true,
  );

  _tryMatch();
}

void _tryMatch() {
  for (var i = 0; i < _pending.length; i++) {
    final a = _pending[i];
    if (a.socket == null) continue;

    for (var j = i + 1; j < _pending.length; j++) {
      final b = _pending[j];
      if (b.socket == null) continue;

      _pending.removeAt(j);
      _pending.removeAt(i);

      a
        ..partner = b
        ..accepted = false;
      b
        ..partner = a
        ..accepted = false;

      _send(a, {
        'type': 'matched',
        'peer': {'alias': b.alias, 'meta': _meta(b)},
      });
      _send(b, {
        'type': 'matched',
        'peer': {'alias': a.alias, 'meta': _meta(a)},
      });

      return;
    }
  }
}

void _onMessage(Peer peer, dynamic raw) {
  Map<String, dynamic> data;
  try {
    data = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
  } catch (_) {
    return;
  }

  final partner = peer.partner;
  if (partner == null) return;

  switch (data['type']) {
    case 'consent_accept':
      peer.accepted = true;
      if (partner.accepted) {
        _send(peer, {'type': 'connected'});
        _send(partner, {'type': 'connected'});
      } else {
        _send(partner, {'type': 'consent_accepted'});
      }
      break;

    case 'message':
      if (!peer.accepted || !partner.accepted) return;
      final text = (data['text'] as String? ?? '').trim();
      if (text.isEmpty || text.length > 2000) return;
      _send(partner, {
        'type': 'message',
        'text': text,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
      break;

    case 'typing':
      _send(partner, {'type': 'typing', 'on': data['on'] == true});
      break;

    case 'leave':
      _send(partner, {'type': 'peer_left'});
      partner.partner = null;
      peer.partner = null;
      break;
  }
}

void _onClose(Peer peer) {
  _pending.remove(peer);
  _byToken.removeWhere((_, value) => identical(value, peer));
  _byRequest.remove(peer.requestId);

  final partner = peer.partner;
  if (partner != null) {
    partner.partner = null;
    _send(partner, {'type': 'peer_left'});
    _tryMatch();
  }
}

void _send(Peer peer, Map<String, Object?> payload) {
  try {
    peer.socket?.add(jsonEncode(payload));
  } catch (_) {
    // socket already closed
  }
}

String _meta(Peer peer) => '${peer.country} · ${peer.lang.toUpperCase()}';

String _id() {
  final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}
