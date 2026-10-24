import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/background_jobs.dart';
import '../core/json_splitter_service.dart';

const _surface = Color(0xff1c1c1c);
const _primary = Color(0xff2379ad);
const _success = Color(0xff228b43);
const _accent = Color(0xff11d4e8);

class JsonSplitterPage extends StatefulWidget {
  const JsonSplitterPage({super.key});

  @override
  State<JsonSplitterPage> createState() => _JsonSplitterPageState();
}

class _JsonSplitterPageState extends State<JsonSplitterPage> {
  final _partsController = TextEditingController(text: '2');
  final _itemsController = TextEditingController(text: '500');
  final _baseController = TextEditingController(text: 'data');
  JsonInspection? _inspection;
  String? _sourcePath;
  String _sourceName = '';
  String _mode = 'parts';
  String _format = 'same';
  String _status = 'Select a JSON file to begin.';
  int _targetIndex = 0;
  bool _busy = false;
  final List<JsonSplitPart> _generated = [];
  final List<Directory> _temporaryDirectories = [];

  @override
  void dispose() {
    _partsController.dispose();
    _itemsController.dispose();
    _baseController.dispose();
    // Only delete workspaces created by this widget, never exported user files.
    for (final temp in _temporaryDirectories) {
      unawaited(temp.delete(recursive: true).then<void>((_) {},
          onError: (Object _, StackTrace __) {}));
    }
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    // Flutter exceptions can contain entire UI object graphs in their text.
    // Show a useful single-line explanation without filling the whole page.
    final summary = text.split('\n').first;
    setState(() => _status = summary.length > 260
        ? '${summary.substring(0, 260)}…'
        : summary);
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select JSON file to split',
      );
      if (file == null) return;
      setState(() {
        _busy = true;
        _status = 'Inspecting ${file.name}...';
        _inspection = null;
        _generated.clear();
      });
      var path = file.path;
      if (path == null) {
        final temp = await Directory.systemTemp.createTemp('m3u8_json_source_');
        _temporaryDirectories.add(temp);
        path = '${temp.path}${Platform.pathSeparator}${JsonSplitterService.safeBaseName(file.name)}';
        await File(path).writeAsBytes(await file.readAsBytes());
      }
      final sourcePath = path;
      final inspection = await compute(inspectJsonInBackground, sourcePath);
      if (!mounted) return;
      setState(() {
        _inspection = inspection;
        _sourcePath = sourcePath;
        _sourceName = file.name;
        _targetIndex = 0;
        _baseController.text = file.name.replaceFirst(RegExp(r'\.json$', caseSensitive: false), '');
        _status = inspection.targets.isEmpty
            ? 'At least 2 array items or object keys are needed.'
            : 'Loaded ${file.name} (${_size(inspection.sourceBytes)}).';
      });
    } catch (e) {
      _message('Cannot inspect JSON: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _split() async {
    final preview = _inspection;
    final source = _sourcePath;
    if (_busy || preview == null || preview.targets.isEmpty || source == null) return;
    final value = int.tryParse(_mode == 'parts' ? _partsController.text : _itemsController.text);
    if (value == null || value <= 0) {
      _message('Enter a positive whole number.');
      return;
    }
    final target = preview.targets[_targetIndex];
    try {
      // Validate before creating disk output. No fixed item or file-size cap.
      final iterator = JsonSplitterService.partSizes(target.count,
          parts: _mode == 'parts' ? value : null,
          itemsPerPart: _mode == 'items' ? value : null).iterator;
      if (!iterator.moveNext()) {
        throw const FormatException('No output parts generated.');
      }
      setState(() {
        _busy = true;
        _status = 'Splitting JSON in the background...';
      });
      final temp = await Directory.systemTemp.createTemp('m3u8_json_parts_');
      _temporaryDirectories.add(temp);
      final tempPath = temp.path;
      final targetIndex = _targetIndex;
      final base = _baseController.text;
      final format = _format;
      final mode = _mode;
      final produced = await compute(splitJsonInBackground, (
        sourcePath: source,
        outputDirectory: tempPath,
        targetIndex: targetIndex,
        baseName: base,
        format: format,
        parts: mode == 'parts' ? value : null,
        itemsPerPart: mode == 'items' ? value : null,
      ));
      if (!mounted) return;
      setState(() {
        _generated
          ..clear()
          ..addAll(produced);
        _status = '✓ ${produced.length} files created · ${produced.fold<int>(0, (n, p) => n + p.itemCount)} items preserved.';
      });
    } catch (e) {
      _message('Split failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportOne(JsonSplitPart part) async {
    final directory = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder to save ${part.name}');
    if (directory == null) return;
    setState(() => _busy = true);
    try {
      final destination = await JsonSplitterService.availablePath(directory, part.name);
      await File(part.path).copy(destination);
      _message('Saved ${part.name} to $directory.');
    } catch (e) {
      _message('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAll() async {
    if (_generated.isEmpty || _busy) return;
    final directory = await FilePicker.getDirectoryPath(dialogTitle: 'Choose output folder for all JSON parts');
    if (directory == null) return;
    setState(() => _busy = true);
    try {
      for (final part in _generated) {
        final destination = await JsonSplitterService.availablePath(directory, part.name);
        await File(part.path).copy(destination);
      }
      _message('Saved all ${_generated.length} JSON parts to $directory.');
    } catch (e) {
      _message('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportZip() async {
    if (_generated.isEmpty || _busy) return;
    final directory = await FilePicker.getDirectoryPath(dialogTitle: 'Choose folder for ZIP archive');
    if (directory == null) return;
    setState(() {
      _busy = true;
      _status = 'Creating ZIP in the background...';
    });
    try {
      final name = '${JsonSplitterService.safeBaseName(_baseController.text)}-parts.zip';
      final destination = await JsonSplitterService.availablePath(directory, name);
      final parts = List<JsonSplitPart>.from(_generated);
      await compute(zipJsonInBackground, (parts: parts, destination: destination));
      _message('ZIP saved: $destination');
    } catch (e) {
      _message('ZIP export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Widget _card(Widget content) => Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10)),
        child: content,
      );

  Widget _button(String label, VoidCallback? action, {Color color = _primary}) =>
      FilledButton(
        onPressed: _busy ? null : action,
        style: FilledButton.styleFrom(backgroundColor: color),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final inspection = _inspection;
    final active = inspection != null && inspection.targets.isNotEmpty;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.splitscreen_outlined, size: 24),
          SizedBox(width: 10),
          Text('Json Spliter', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        const Text('Split a JSON array or object into valid, structure-preserving JSON files.',
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 18),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Select JSON file', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(children: [
            _button('Browse JSON File', _pickFile),
            const SizedBox(width: 12),
            Expanded(child: Text(_sourceName.isEmpty ? 'No file selected' : _sourceName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _accent))),
          ]),
          const SizedBox(height: 10),
          Text(_status, style: const TextStyle(color: Colors.white70)),
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        ])),
        if (active) _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Split options', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('$_sourcePath-$_targetIndex'),
            initialValue: _targetIndex,
            decoration: const InputDecoration(labelText: 'Which section to split'),
            items: [
              for (var i = 0; i < inspection.targets.length; i++)
                DropdownMenuItem(value: i, child: Text(
                    '${inspection.targets[i].label} — ${inspection.targets[i].count} items')),
            ],
            onChanged: _busy ? null : (index) {
              setState(() { _targetIndex = index ?? 0; _generated.clear(); });
            },
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'parts', label: Text('Number of parts')),
              ButtonSegment(value: 'items', label: Text('Items per part')),
            ],
            selected: {_mode},
            onSelectionChanged: _busy ? null : (value) {
              setState(() { _mode = value.first; _generated.clear(); });
            },
          ),
          const SizedBox(height: 12),
          SizedBox(width: 210, child: TextField(
            controller: _mode == 'parts' ? _partsController : _itemsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _mode == 'parts' ? 'How many parts' : 'Items per part'),
          )),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _format,
            decoration: const InputDecoration(labelText: 'Output format'),
            items: const [
              DropdownMenuItem(value: 'same', child: Text('Original formatting (auto)')),
              DropdownMenuItem(value: 'pretty', child: Text('Pretty (2-space indent)')),
              DropdownMenuItem(value: 'min', child: Text('Minified (smaller files)')),
            ],
            onChanged: _busy ? null : (value) => setState(() => _format = value ?? 'same'),
          ),
          const SizedBox(height: 14),
          TextField(controller: _baseController,
              decoration: const InputDecoration(labelText: 'Output base file name')),
          const SizedBox(height: 14),
          _button('Split JSON', _split, color: _success),
        ])),
        if (_generated.isNotEmpty) _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Results — ${_generated.length} parts',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(height: 250, child: ListView.builder(
            itemCount: _generated.length,
            itemBuilder: (context, index) {
              final part = _generated[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(part.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${part.itemCount} items · ${_size(part.bytes)}'),
                trailing: IconButton(
                  onPressed: _busy ? null : () => _exportOne(part),
                  tooltip: 'Save this part',
                  icon: const Icon(Icons.download_outlined),
                ),
              );
            },
          )),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _button('Save all JSON files', _exportAll, color: _success),
            _button('Save all as ZIP', _exportZip),
          ]),
        ])),
        const Text('Processing stays on your PC. Large files depend on available disk space and memory.',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
      ]),
    );
  }
}
