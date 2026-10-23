import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8_studio/core/range_generator.dart';

void main() {
  test('numeric and IP ranges are inclusive', () {
    expect(RangeGenerator.numberRange('310', '312', 'ID'), ['310', '311', '312']);
    expect(RangeGenerator.ipRange('192.168.1.1', '192.168.1.2'),
        ['192.168.1.1', '192.168.1.2']);
  });

  test('produces combinations for the screenshot placeholders', () {
    final channels = RangeGenerator.generate(
      pattern: 'http://{ip}:{port}/cdn{cdn-numer}/{id}.m3u8',
      ids: ['1', '2'], cdns: ['3'], ips: ['192.168.1.1'], ports: ['80'],
    );
    expect(channels, hasLength(2));
    expect(channels.first.url, 'http://192.168.1.1:80/cdn3/1.m3u8');
    expect(channels.last.url, 'http://192.168.1.1:80/cdn3/2.m3u8');
  });

  test('supports cdn-number alias and deduplicated pasted IDs', () {
    expect(RangeGenerator.idList('12, 12\n13'), ['12', '13']);
    final channels = RangeGenerator.generate(
      pattern: 'https://example.com/{cdn-number}/{id}',
      ids: ['12'], cdns: ['3'], ips: ['127.0.0.1'], ports: ['80'],
    );
    expect(channels.single.url, 'https://example.com/3/12');
  });

  test('rejects reversed and excessive ranges', () {
    expect(() => RangeGenerator.numberRange('5', '1', 'ID'), throwsFormatException);
    expect(() => RangeGenerator.numberRange('1', '10000', 'ID'), throwsFormatException);
    expect(() => RangeGenerator.ipRange('192.168.1.20', '192.168.1.1'), throwsFormatException);
  });

  test('caps Cartesian product at five thousand links', () {
    expect(() => RangeGenerator.generate(
      pattern: 'http://example.com/{id}/{cdn-numer}',
      ids: RangeGenerator.numberRange('1', '100', 'ID'),
      cdns: RangeGenerator.numberRange('1', '100', 'CDN'),
      ips: ['127.0.0.1'], ports: ['80'],
    ), throwsFormatException);
  });
}
