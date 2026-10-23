import 'dart:async';
import 'dart:io';

class StreamCheck {
  const StreamCheck({required this.reachable, required this.code, required this.detail});

  final bool reachable;
  final int? code;
  final String detail;
}

class StreamChecker {
  const StreamChecker();

  Future<StreamCheck> check(String link) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    client.userAgent = 'M3U8Studio/1.0';
    try {
      for (final method in ['HEAD', 'GET']) {
        try {
          final request = await client.openUrl(method, Uri.parse(link))
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
          if (method == 'GET') {
            return StreamCheck(reachable: false, code: code, detail: 'HTTP $code');
          }
        } on TimeoutException {
          if (method == 'GET') {
            return const StreamCheck(reachable: false, code: null, detail: 'Timeout');
          }
        } catch (e) {
          if (method == 'GET') {
            return StreamCheck(reachable: false, code: null, detail: _brief(e));
          }
        }
      }
      return const StreamCheck(reachable: false, code: null, detail: 'No response');
    } finally {
      client.close(force: true);
    }
  }

  String _brief(Object exception) {
    if (exception is SocketException) return 'Connection failed';
    if (exception is HandshakeException) return 'TLS handshake failed';
    return 'Request failed';
  }
}
