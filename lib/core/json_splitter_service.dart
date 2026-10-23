import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

enum JsonSplitKind { array, object }

class JsonSplitTarget {
  const JsonSplitTarget({
    required this.label,
    required this.kind,
    required this.count,
    this.wrapperKey,
  });

  final String label;
  final JsonSplitKind kind;
  final int count;
  final String? wrapperKey;
}

class JsonInspection {
  const JsonInspection({
    required this.targets,
    required this.sourceBytes,
    required this.originalIndent,
  });

  final List<JsonSplitTarget> targets;
  final int sourceBytes;
  final String? originalIndent;
}

class JsonSplitPart {
  const JsonSplitPart({
    required this.name,
    required this.path,
    required this.itemCount,
    required this.bytes,
  });

  final String name;
  final String path;
  final int itemCount;
  final int bytes;
}

class JsonSplitterService {
  const JsonSplitterService._();

  static Future<JsonInspection> inspectFile(String sourcePath) async {
    final text = await File(sourcePath).readAsString();
    return inspectText(text);
  }

  static JsonInspection inspectText(String text) {
    final data = jsonDecode(text.replaceFirst('\ufeff', ''));
    final targets = findTargets(data);
    final indentation = RegExp(r'\n([ \t]+)\S').firstMatch(text)?.group(1);
    return JsonInspection(
      targets: targets,
      sourceBytes: utf8.encode(text).length,
      originalIndent: indentation,
    );
  }

  static List<JsonSplitTarget> findTargets(dynamic data) {
    if (data is List) {
      return data.length >= 2
          ? [JsonSplitTarget(label: 'Root array', kind: JsonSplitKind.array, count: data.length)]
          : [];
    }
    if (data is! Map) {
      return [];
    }
    final keys = data.keys.toList();
    final arrayKeys = keys.where((k) => data[k] is List && (data[k] as List).length >= 2).toList();
    final looksLikeWrapper = arrayKeys.isNotEmpty &&
        arrayKeys.length <= 3 && keys.length - arrayKeys.length <= 6;
    return [
      if (looksLikeWrapper)
        for (final key in arrayKeys)
          JsonSplitTarget(
            label: '"$key" array',
            kind: JsonSplitKind.array,
            count: (data[key] as List).length,
            wrapperKey: '$key',
          ),
      if (keys.length >= 2)
        JsonSplitTarget(label: 'Root object (by keys)', kind: JsonSplitKind.object,
            count: keys.length),
    ];
  }

  static Iterable<int> partSizes(int total, {int? parts, int? itemsPerPart}) sync* {
    if (total < 2) throw const FormatException('JSON must have at least 2 items.');
    if ((parts == null) == (itemsPerPart == null)) {
      throw const FormatException('Choose either number of parts or items per part.');
    }
    if (parts != null) {
      if (parts < 2 || parts > total) {
        throw FormatException('Part count must be between 2 and $total.');
      }
      final normal = total ~/ parts;
      final extra = total % parts;
      for (var i = 0; i < parts; i++) {
        yield normal + (i < extra ? 1 : 0);
      }
    } else {
      final size = itemsPerPart!;
      if (size < 1 || size >= total) {
        throw FormatException('Items per part must be between 1 and ${total - 1}.');
      }
      for (var remaining = total; remaining > 0; remaining -= size) {
        yield remaining < size ? remaining : size;
      }
    }
  }

  static String safeBaseName(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    return sanitized.isEmpty ? 'data' : sanitized;
  }

  static dynamic makePart(dynamic data, JsonSplitTarget target, int start, int count,
      {List<dynamic>? objectKeys}) {
    final source = target.wrapperKey == null ? data : (data as Map)[target.wrapperKey];
    late final dynamic piece;
    if (target.kind == JsonSplitKind.array) {
      piece = (source as List).sublist(start, start + count);
    } else {
      final map = source as Map;
      final keys = objectKeys ?? map.keys.toList();
      piece = {for (var i = start; i < start + count; i++) keys[i]: map[keys[i]]};
    }
    if (target.wrapperKey == null) {
      return piece;
    }
    return {for (final key in (data as Map).keys) key: key == target.wrapperKey ? piece : data[key]};
  }

  static Future<List<JsonSplitPart>> splitFile({
    required String sourcePath,
    required String outputDirectory,
    required int targetIndex,
    required String baseName,
    required String format,
    int? parts,
    int? itemsPerPart,
  }) async {
    final text = await File(sourcePath).readAsString();
    final data = jsonDecode(text.replaceFirst('\ufeff', ''));
    final targets = findTargets(data);
    if (targetIndex < 0 || targetIndex >= targets.length) {
      throw const FormatException('Select a valid JSON target.');
    }
    final target = targets[targetIndex];
    final sizes = partSizes(target.count, parts: parts, itemsPerPart: itemsPerPart).toList();
    final objectKeys = target.kind == JsonSplitKind.object ? (data as Map).keys.toList() : null;
    final indent = switch (format) {
      'pretty' => '  ',
      'min' => null,
      _ => RegExp(r'\n([ \t]+)\S').firstMatch(text)?.group(1),
    };
    final encoder = indent == null ? const JsonEncoder() : JsonEncoder.withIndent(indent);
    final width = sizes.length.toString().length;
    final base = safeBaseName(baseName);
    final output = Directory(outputDirectory);
    await output.create(recursive: true);
    var offset = 0;
    final result = <JsonSplitPart>[];
    for (var i = 0; i < sizes.length; i++) {
      final size = sizes[i];
      final piece = makePart(data, target, offset, size, objectKeys: objectKeys);
      offset += size;
      final name = '$base-part${(i + 1).toString().padLeft(width, '0')}.json';
      final file = File('${output.path}${Platform.pathSeparator}$name');
      await file.writeAsString(encoder.convert(piece));
      result.add(JsonSplitPart(
        name: name,
        path: file.path,
        itemCount: size,
        bytes: await file.length(),
      ));
    }
    return result;
  }

  static Future<String> exportZip(List<JsonSplitPart> parts, String destination) async {
    final zip = ZipFileEncoder();
    zip.create(destination);
    try {
      for (final part in parts) {
        await zip.addFile(File(part.path), part.name);
      }
    } finally {
      await zip.close();
    }
    return destination;
  }

  static Future<String> availablePath(String folder, String filename) async {
    final clean = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String candidate = '$folder${Platform.pathSeparator}$clean';
    var counter = 1;
    while (await File(candidate).exists()) {
      final dot = clean.lastIndexOf('.');
      final prefix = dot < 0 ? clean : clean.substring(0, dot);
      final suffix = dot < 0 ? '' : clean.substring(dot);
      candidate = '$folder${Platform.pathSeparator}$prefix ($counter)$suffix';
      counter++;
    }
    return candidate;
  }
}
