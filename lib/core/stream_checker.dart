import 'dart:async';
import 'dart:io';

class StreamCheck {
  const StreamCheck({required this.reachable, required this.code, required this.detail});

  final bool reachable;
  final int? code;
  final String detail;
}

class StreamChecker {
  StreamChecker()
      : _client = HttpClient()..connectionTimeout = const Duration(seconds: 5) {
    _client.userAgent = 'M3U8Studio/1.1';
  }

  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<StreamCheck> check(String link, {bool quick = false}) async {
    for (final method in quick ? ['HEAD'] : ['HEAD', 'GET']) {
      try {
        final request = await _client.openUrl(method, Uri.parse(link))
            .timeout(const Duration(seconds: 7));
        request.followRedirects = true;
        request.maxRedirects = 3;
        if (method == 'GET') request.headers.set('Range', 'bytes=0-1023');
        final response = await request.close().timeout(const Duration(seconds: 8));
        final code = response.statusCode;
        final subscription = response.listen((_) {});
        await subscription.cancel();
        if (code >= 200 && code < 300) {
          return StreamCheck(reachable: true, code: code, detail: 'HTTP $code');
        }
        if (method == 'GET' || quick) {
          return StreamCheck(reachable: false, code: code, detail: 'HTTP $code');
        }
      } on TimeoutException {
        if (method == 'GET' || quick) {
          return const StreamCheck(reachable: false, code: null, detail: 'Timeout');
        }
      } catch (e) {
        if (method == 'GET' || quick) {
          return StreamCheck(reachable: false, code: null, detail: _brief(e));
        }
      }
    }
    return const StreamCheck(reachable: false, code: null, detail: 'No response');
  }

  String _brief(Object exception) {
    if (exception is SocketException) return 'Connection failed';
    if (exception is HandshakeException) return 'TLS handshake failed';
    return 'Request failed';
  }
}
