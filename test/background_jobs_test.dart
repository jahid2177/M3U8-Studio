import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8_studio/core/background_jobs.dart';

void main() {
  test('JSON inspect, split and ZIP run in background without UI captures', () async {
    final temp = await Directory.systemTemp.createTemp('m3u8_worker_test_');
    try {
      final input = File('${temp.path}${Platform.pathSeparator}source.json');
      await input.writeAsString(jsonEncode({
        'name': 'Sample playlist',
        'channels': [
          {'name': 'A', 'url': 'https://example.com/a.m3u8'},
          {'name': 'B', 'url': 'https://example.com/b.m3u8'},
          {'name': 'C', 'url': 'https://example.com/c.m3u8'},
        ],
      }));
      final inspection = await compute(inspectJsonInBackground, input.path);
      expect(inspection.targets.first.count, 3);

      final parts = await compute(splitJsonInBackground, (
        sourcePath: input.path,
        outputDirectory: '${temp.path}${Platform.pathSeparator}parts',
        targetIndex: 0,
        baseName: 'sample',
        format: 'pretty',
        parts: 2,
        itemsPerPart: null,
      ));
      expect(parts, hasLength(2));
      final first = jsonDecode(await File(parts.first.path).readAsString());
      expect(first['name'], 'Sample playlist');
      expect(first['channels'], hasLength(2));

      final archivePath = '${temp.path}${Platform.pathSeparator}parts.zip';
      final zipPath = await compute(zipJsonInBackground,
          (parts: parts, destination: archivePath));
      expect(await File(zipPath).length(), greaterThan(50));
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('playlist and URL generation jobs are isolate-safe', () async {
    final channels = await compute(parsePlaylistTextInBackground, (
      input: '[{"name":"Example","url":"https://example.com/stream.m3u8"}]',
      source: 'Test',
    ));
    expect(channels.single.name, 'Example');

    final generated = await compute(generateRangeInBackground, (
      idSource: 'Numeric range',
      idFrom: '1',
      idTo: '3',
      randomCount: '2',
      idsText: '',
      pattern: 'https://example.com/{id}.m3u8',
      cdnFrom: '1',
      cdnTo: '1',
      ipFrom: '192.168.0.1',
      ipTo: '192.168.0.1',
      portFrom: '80',
      portTo: '80',
    ));
    expect(generated, hasLength(3));
  });
}
