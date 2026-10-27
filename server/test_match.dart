// End-to-end check for server/match_server.dart
// Run from the project root: dart run server/test_match.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int _port = 8791;

class WsClient {
  WsClient(this.socket) {
    socket.listen(
      (raw) => _onData(raw),
      onError: (Object error) => _fail(error),
    );
  }

  final WebSocket socket;
  final List<Map<String, dynamic>> _queue = [];
  final List<Completer<Map<String, dynamic>>> _waiters = [];

  void _onData(dynamic raw) {
    final map = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(map);
    } else {
      _queue.add(map);
    }
  }

  Future<Map<String, dynamic>> next() {
    if (_queue.isNotEmpty) return Future.value(_queue.removeAt(0));
    final completer = Completer<Map<String, dynamic>>();
    _waiters.add(completer);
    return completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException('no websocket event'),
    );
  }

  Future<Map<String, dynamic>> waitFor(String type) async {
    while (true) {
      final event = await next();
      if (event['type'] == type) return event;
    }
  }

  void send(Map<String, Object?> payload) {
    socket.add(jsonEncode(payload));
  }

  void _fail(Object error) {
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
    _waiters.clear();
  }
}

Future<void> main() async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'server/match_server.dart'],
    environment: {'PORT': '$_port'},
  );

  final ready = Completer<void>();
  process.stdout.transform(utf8.decoder).listen((line) {
    stdout.write('[server] $line');
    if (line.contains('listening') && !ready.isCompleted) ready.complete();
  });
  process.stderr.transform(utf8.decoder).listen((line) {
    stderr.write('[server:err] $line');
  });

  try {
    await ready.future.timeout(const Duration(seconds: 10));

    final first = await _requestMatch('alice');
    final second = await _requestMatch('bob');

    final a = WsClient(await WebSocket.connect(first['ws'] as String));
    final b = WsClient(await WebSocket.connect(second['ws'] as String));

    final aMatched = await a.waitFor('matched');
    final bMatched = await b.waitFor('matched');
    _expect(aMatched['type'] == 'matched', 'alice should be matched');
    _expect(bMatched['type'] == 'matched', 'bob should be matched');

    a.send({'type': 'consent_accept'});
    b.send({'type': 'consent_accept'});

    await a.waitFor('connected');
    await b.waitFor('connected');

    a.send({'type': 'message', 'text': '你好，今天过得怎么样？'});
    final delivered = await b.waitFor('message');
    _expect(
      delivered['text'] == '你好，今天过得怎么样？',
      'message text should be relayed intact',
    );

    await a.socket.close();
    await b.waitFor('peer_left');

    stdout.writeln('PASS: match -> mutual consent -> message -> leave');
  } finally {
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}

Future<Map<String, dynamic>> _requestMatch(String anonId) async {
  final client = HttpClient();
  try {
    final request = await client.post('127.0.0.1', _port, '/v1/match');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'anonId': anonId,
      'lang': 'zh',
      'country': 'CN',
    }));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    _expect(response.statusCode == 200, 'match HTTP ${response.statusCode}');
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  } finally {
    client.close(force: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
