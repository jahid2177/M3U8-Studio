import 'dart:math';

import 'channel.dart';
import 'playlist_parser.dart';

class RangeGenerator {
  const RangeGenerator._();

  static List<String> numberRange(String from, String to, String label) {
    final start = int.tryParse(from.trim());
    final end = int.tryParse(to.trim());
    if (start == null || end == null || start < 0 || end < start) {
      throw FormatException('Invalid $label range.');
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
    if (b < a) {
      throw const FormatException('IPv4 range must be ordered.');
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
      .toList();

  static List<String> randomIds(String from, String to, String countRaw) {
    final start = int.tryParse(from.trim());
    final end = int.tryParse(to.trim());
    final count = int.tryParse(countRaw);
    if (start == null || end == null || start < 0 || end < start ||
        count == null || count < 1 || count > end - start + 1) {
      throw const FormatException('Random count must fit within the ID range.');
    }
    final random = Random();
    final selections = <int>{};
    final span = end - start + 1;
    // Floyd's algorithm: exactly `count` draws, even when sampling nearly all IDs.
    for (var j = span - count; j < span; j++) {
      final candidate = random.nextInt(j + 1);
      selections.add(selections.contains(candidate) ? j : candidate);
    }
    return selections.map((id) => '${start + id}').toList();
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
    final active = axes.entries.where((e) => normalized.contains(e.key)).toList();
    for (final entry in active) {
      if (entry.value.isEmpty) throw FormatException('No values for ${entry.key}.');
    }
    final unresolved = RegExp(r'\{[^}]+\}');
    if (unresolved.hasMatch(normalized.replaceAll(RegExp(r'\{(?:id|cdn-numer|ip|port)\}'), ''))) {
      throw const FormatException('Unknown placeholder in pattern.');
    }
    final seen = <String>{};
    final result = <Channel>[];
    void expand(int index, String url) {
      if (index == active.length) {
        if (PlaylistParser.isWebUrl(url) && seen.add(url)) {
          result.add(Channel(name: 'Stream ${seen.length}', url: url, source: 'ID Range Tester'));
        }
        return;
      }
      final entry = active[index];
      for (final value in entry.value) {
        expand(index + 1, url.replaceAll(entry.key, value));
      }
    }
    expand(0, normalized);
    return result;
  }
}
