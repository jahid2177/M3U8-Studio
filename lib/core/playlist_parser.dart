import 'dart:convert';

import 'channel.dart';

class PlaylistParser {
  const PlaylistParser._();

  static final _m3uAttributes = <String, RegExp>{
    'tvg-logo': RegExp(r'tvg-logo="([^"]*)"'),
    'group-title': RegExp(r'group-title="([^"]*)"'),
    'tvg-id': RegExp(r'tvg-id="([^"]*)"'),
  };

  static bool isWebUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static List<Channel> parse(String input, {String source = 'Imported'}) {
    final text = input.replaceFirst('\ufeff', '').trim();
    if (text.isEmpty) return const [];
    if (text.startsWith('[') || text.startsWith('{')) {
      try {
        return _unique(_fromJson(jsonDecode(text), source));
      } on FormatException {
        rethrow;
      } catch (e) {
        throw FormatException('Invalid JSON playlist: $e');
      }
    }
    return _unique(_fromM3u(text, source));
  }

  static List<Channel> _fromJson(dynamic data, String source) {
    if (data is Map) {
      if (data['channels'] is List) return _fromJson(data['channels'], source);
      if (data['items'] is List) return _fromJson(data['items'], source);
      if (data['data'] is List) return _fromJson(data['data'], source);
      data = [data];
    }
    if (data is! List) {
      throw const FormatException('Expected a JSON array or a channels array.');
    }
    final channels = <Channel>[];
    for (final item in data) {
      if (item is String) {
        if (isWebUrl(item)) {
          channels.add(Channel(name: 'Stream ${channels.length + 1}', url: item.trim(), source: source));
        }
        continue;
      }
      if (item is! Map) continue;
      final url = (item['url'] ?? item['stream_url'] ?? item['link'] ?? '').toString().trim();
      if (!isWebUrl(url)) continue;
      final name = (item['name'] ?? item['title'] ?? item['channel'] ?? '').toString().trim();
      channels.add(Channel(
        name: name.isEmpty ? 'Stream ${channels.length + 1}' : name,
        url: url,
        group: (item['group'] ?? item['group_title'] ?? '').toString(),
        logo: (item['logo'] ?? item['tvg_logo'] ?? '').toString(),
        epgId: (item['epg_id'] ?? item['tvg_id'] ?? '').toString(),
        source: source,
      ));
    }
    return channels;
  }

  static List<Channel> _fromM3u(String text, String source) {
    final result = <Channel>[];
    String name = '';
    String logo = '';
    String group = '';
    String epgId = '';
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.startsWith('#EXTINF')) {
        final comma = line.lastIndexOf(',');
        name = comma < 0 ? '' : line.substring(comma + 1).trim();
        logo = _attribute(line, 'tvg-logo');
        group = _attribute(line, 'group-title');
        epgId = _attribute(line, 'tvg-id');
      } else if (line.startsWith('#EXTGRP:')) {
        group = line.substring('#EXTGRP:'.length).trim();
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        final url = _resolve(line, source);
        if (isWebUrl(url)) {
          result.add(Channel(
            name: name.isEmpty ? 'Stream ${result.length + 1}' : name,
            url: url,
            logo: logo,
            group: group,
            epgId: epgId,
            source: source,
          ));
        }
        name = '';
        logo = '';
        group = '';
        epgId = '';
      }
    }
    return result;
  }

  static String _attribute(String line, String key) {
    final match = _m3uAttributes[key]?.firstMatch(line);
    return match?.group(1) ?? '';
  }

  static String _resolve(String raw, String source) {
    if (isWebUrl(raw)) return raw;
    final base = Uri.tryParse(source);
    return base != null && isWebUrl(source) ? base.resolve(raw).toString() : raw;
  }

  static List<Channel> _unique(List<Channel> channels) {
    final seen = <String>{};
    return channels.where((channel) => seen.add(channel.url.trim())).toList();
  }

  static String asM3u(Iterable<Channel> channels) =>
      '#EXTM3U\n${channels.map((channel) => channel.toM3u()).join('\n')}\n';
}
