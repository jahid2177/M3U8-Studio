import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8_studio/core/channel.dart';
import 'package:m3u8_studio/core/playlist_parser.dart';

void main() {
  test('M3U metadata and duplicates', () {
    const source = '''#EXTM3U
#EXTINF:-1 tvg-id="one" tvg-logo="https://example.com/a.png" group-title="News",Channel One
https://example.com/live/1.m3u8
#EXTINF:-1,Duplicated
https://example.com/live/1.m3u8
#EXTINF:-1,Channel Two
https://example.com/live/2.m3u8
''';
    final result = PlaylistParser.parse(source);
    expect(result, hasLength(2));
    expect(result.first.name, 'Channel One');
    expect(result.first.group, 'News');
    expect(result.first.epgId, 'one');
    expect(result.first.logo, 'https://example.com/a.png');
  });

  test('JSON channel list accepts known name and URL fields', () {
    const source = '''{"channels":[
      {"name":"A","url":"https://example.com/a.m3u8","group":"Test"},
      {"title":"B","stream_url":"http://example.com/b.ts"},
      {"name":"Bad","url":"file:///tmp/not-a-stream"}
    ]}''';
    final result = PlaylistParser.parse(source);
    expect(result, hasLength(2));
    expect(result[0].group, 'Test');
    expect(result[1].name, 'B');
  });

  test('relative playlist entries use remote source as base', () {
    final result = PlaylistParser.parse(
      '#EXTM3U\n#EXTINF:-1,Local\nvideo/stream.m3u8',
      source: 'https://example.com/list/channels.m3u',
    );
    expect(result.single.url, 'https://example.com/list/video/stream.m3u8');
  });

  test('M3U exported entries can be imported', () {
    const channels = [
      Channel(name: 'First', url: 'https://example.com/first.m3u8', group: 'Movies'),
      Channel(name: 'Second', url: 'https://example.com/second.m3u8'),
    ];
    final result = PlaylistParser.parse(PlaylistParser.asM3u(channels));
    expect(result.map((e) => e.name), ['First', 'Second']);
    expect(result.first.group, 'Movies');
  });

  test('only actual http and https URLs are accepted', () {
    expect(PlaylistParser.isWebUrl('https://example.com/test.m3u8'), isTrue);
    expect(PlaylistParser.isWebUrl('file:///etc/passwd'), isFalse);
    expect(PlaylistParser.isWebUrl('javascript:alert(1)'), isFalse);
    expect(PlaylistParser.isWebUrl('not a URL'), isFalse);
  });
}
