import 'dart:io';

import 'channel.dart';
import 'json_splitter_service.dart';
import 'playlist_parser.dart';
import 'range_generator.dart';

// Each function is top-level so Flutter's compute() only sends the plain
// argument and never accidentally captures a Widget State / BuildContext.
Future<JsonInspection> inspectJsonInBackground(String path) =>
    JsonSplitterService.inspectFile(path);

typedef JsonSplitJob = ({
  String sourcePath,
  String outputDirectory,
  int targetIndex,
  String baseName,
  String format,
  int? parts,
  int? itemsPerPart,
});

Future<List<JsonSplitPart>> splitJsonInBackground(JsonSplitJob job) =>
    JsonSplitterService.splitFile(
      sourcePath: job.sourcePath,
      outputDirectory: job.outputDirectory,
      targetIndex: job.targetIndex,
      baseName: job.baseName,
      format: job.format,
      parts: job.parts,
      itemsPerPart: job.itemsPerPart,
    );

typedef JsonZipJob = ({List<JsonSplitPart> parts, String destination});

Future<String> zipJsonInBackground(JsonZipJob job) =>
    JsonSplitterService.exportZip(job.parts, job.destination);

typedef RangeGenerationJob = ({
  String idSource,
  String idFrom,
  String idTo,
  String randomCount,
  String idsText,
  String pattern,
  String cdnFrom,
  String cdnTo,
  String ipFrom,
  String ipTo,
  String portFrom,
  String portTo,
});

List<Channel> generateRangeInBackground(RangeGenerationJob job) {
  final ids = switch (job.idSource) {
    'Random IDs' => RangeGenerator.randomIds(
        job.idFrom, job.idTo, job.randomCount),
    'Pasted ID list' || 'Uploaded ID list' =>
      RangeGenerator.idList(job.idsText),
    _ => RangeGenerator.numberRange(job.idFrom, job.idTo, 'ID'),
  };
  return RangeGenerator.generate(
    pattern: job.pattern,
    ids: ids,
    cdns: RangeGenerator.numberRange(job.cdnFrom, job.cdnTo, 'CDN'),
    ips: RangeGenerator.ipRange(job.ipFrom, job.ipTo),
    ports: RangeGenerator.numberRange(job.portFrom, job.portTo, 'port'),
  );
}

typedef PlaylistFileJob = ({String path, String source});
typedef PlaylistTextJob = ({String input, String source});

Future<List<Channel>> parsePlaylistFileInBackground(PlaylistFileJob job) async {
  final content = await File(job.path).readAsString();
  return PlaylistParser.parse(content, source: job.source);
}

List<Channel> parsePlaylistTextInBackground(PlaylistTextJob job) =>
    PlaylistParser.parse(job.input, source: job.source);
