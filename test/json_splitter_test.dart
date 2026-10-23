import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8_studio/core/json_splitter_service.dart';

void main() {
  test('inspects arrays and object wrappers', () {
    final simple = JsonSplitterService.inspectText('[1,2,3,4]');
    expect(simple.targets.single.kind, JsonSplitKind.array);
    expect(simple.targets.single.count, 4);
    final wrapped = JsonSplitterService.inspectText(
      '{"version":1,"channels":[{"id":1},{"id":2},{"id":3}]}',
    );
    expect(wrapped.targets.first.wrapperKey, 'channels');
    expect(wrapped.targets.first.count, 3);
    expect(wrapped.targets.last.kind, JsonSplitKind.object);
  });

  test('balanced division and count-based division preserve totals', () {
    expect(JsonSplitterService.partSizes(10, parts: 3).toList(), [4, 3, 3]);
    expect(JsonSplitterService.partSizes(11, itemsPerPart: 5).toList(), [5, 5, 1]);
    expect(JsonSplitterService.partSizes(12001, itemsPerPart: 5000).toList(),
        [5000, 5000, 2001]);
  });

  test('wrapper metadata stays in every split part', () {
    final data = jsonDecode('{"version":2,"channels":[1,2,3,4]}');
    final target = JsonSplitterService.findTargets(data).first;
    final one = JsonSplitterService.makePart(data, target, 0, 2);
    final two = JsonSplitterService.makePart(data, target, 2, 2);
    expect(one['version'], 2);
    expect(two['version'], 2);
    expect(one['channels'], [1, 2]);
    expect(two['channels'], [3, 4]);
  });

  test('object split preserves keys and values', () {
    final original = jsonDecode('{"a":1,"b":2,"c":3,"d":4}');
    final target = JsonSplitterService.findTargets(original).single;
    expect(JsonSplitterService.makePart(original, target, 0, 2), {'a': 1, 'b': 2});
    expect(JsonSplitterService.makePart(original, target, 2, 2), {'c': 3, 'd': 4});
  });

  test('writes split files and creates a valid ZIP', () async {
    final directory = await Directory.systemTemp.createTemp('studio_json_test_');
    try {
      final source = File('${directory.path}${Platform.pathSeparator}input.json');
      await source.writeAsString('{"channels":[1,2,3,4,5],"version":1}');
      final output = '${directory.path}${Platform.pathSeparator}output';
      final files = await JsonSplitterService.splitFile(
        sourcePath: source.path,
        outputDirectory: output,
        targetIndex: 0,
        baseName: 'channels',
        format: 'pretty',
        parts: 2,
      );
      expect(files, hasLength(2));
      expect(files.map((f) => f.itemCount), [3, 2]);
      final first = jsonDecode(await File(files.first.path).readAsString());
      expect(first['channels'], [1, 2, 3]);
      expect(first['version'], 1);
      final zip = '${directory.path}${Platform.pathSeparator}all.zip';
      await JsonSplitterService.exportZip(files, zip);
      expect(await File(zip).length(), greaterThan(30));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
