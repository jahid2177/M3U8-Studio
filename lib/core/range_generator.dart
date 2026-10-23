import 'dart:math';

import 'channel.dart';
import 'playlist_parser.dart';

class RangeGenerator {
  const RangeGenerator._();

  static const maxLinks = 5000;

  static List<String> numberRange(String from, String to, String label) {
    final start = int.tryParse(from.trim());
    final end = int.tryParse(to.trim());
    if (start == null || end == null || start < 0 || end < start) {
      throw FormatException('Invalid $label range.');
    }
    if (end - start + 1 > maxLinks) {
      throw FormatException('$label range exceeds $maxLinks values.');
    }
    return [for (var i = start; i <= end; i++) '$i'];
  }

  static List<String> ipRange(String from, String to) {
    int parse(String raw) {
      final parts = raw.trim().split('.');
      if (parts.length != 4) throw const FormatException('Enter IPv4 addresses.');
      var value = 0;
      for (final part in parts) {
        final octet = int.tryParse(part);
        if (octet == null || octet < 0 || octet > 255) {
          throw const FormatException('Invalid IPv4 address.');
        }
        value = value * 256 + octet;
      }
      return value;
    }

    final a = parse(from);
    final b = parse(to);
    if (b < a || b - a + 1 > maxLinks) {
      throw const FormatException('IPv4 range must be ordered and contain at most 5000 IPs.');
    }
    return [
      for (var n = a; n <= b; n++)
        '${(n >> 24) & 255}.${(n >> 16) & 255}.${(n >> 8) & 255}.${n & 255}',
    ];
  }

  static List<String> idList(String raw) => raw
      .split(RegExp(r'[\s,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .take(maxLinks + 1)
      .toList();

  static List<String> randomIds(String from, String to, String countRaw) {
    final range = numberRange(from, to, 'ID');
    final count = int.tryParse(countRaw);
    if (count == null || count < 1 || count > maxLinks || count > range.length) {
      throw const FormatException('Random count must fit within the ID range (max 5000).');
    }
    range.shuffle(Random.secure());
    return range.take(count).toList();
  }

  static List<Channel> generate({
    required String pattern,
    required List<String> ids,
    required List<String> cdns,
    required List<String> ips,
    required List<String> ports,
  }) {
    final template = pattern.trim();
    if (template.isEmpty) throw const FormatException('Enter a URL pattern first.');
    final axes = <String, List<String>>{
      '{id}': ids,
      '{cdn-numer}': cdns,
      '{ip}': ips,
      '{port}': ports,
    };
    final normalized = template.replaceAll('{cdn-number}', '{cdn-numer}');
    var urls = [normalized];
    for (final entry in axes.entries) {
      if (!normalized.contains(entry.key)) continue;
      if (entry.value.isEmpty) throw FormatException('No values for ${entry.key}.');
      if (urls.length > maxLinks ~/ entry.value.length) {
        throw const FormatException('Too many combinations. Maximum is 5000 links.');
      }
      urls = [
        for (final url in urls)
          for (final value in entry.value) url.replaceAll(entry.key, value),
      ];
    }
    final unresolved = RegExp(r'\{[^}]+\}');
    if (urls.any((e) => unresolved.hasMatch(e))) {
      throw const FormatException('Unknown placeholder in pattern.');
    }
    final seen = <String>{};
    return [
      for (final url in urls)
        if (PlaylistParser.isWebUrl(url) && seen.add(url))
          Channel(name: 'Stream ${seen.length}', url: url, source: 'ID Range Tester'),
    ];
  }
}
