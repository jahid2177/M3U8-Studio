import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8_studio/core/channel.dart';

void main() {
  test('channel rename preserves stream URL and metadata', () {
    const original = Channel(
      name: 'Original',
      url: 'https://example.com/live.m3u8',
      group: 'Documentary',
    );
    final renamed = original.copyWith(name: 'Renamed');
    expect(renamed.name, 'Renamed');
    expect(renamed.url, original.url);
    expect(renamed.group, 'Documentary');
  });
}
