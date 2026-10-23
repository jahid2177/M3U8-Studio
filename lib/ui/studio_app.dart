import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/channel.dart';
import '../core/playlist_parser.dart';
import '../core/range_generator.dart';
import '../core/stream_checker.dart';
import 'json_splitter_page.dart';

const _background = Color(0xff242424);
const _side = Color(0xff292929);
const _panel = Color(0xff1d1d1d);
const _fieldBackground = Color(0xff36393b);
const _blue = Color(0xff2379ad);
const _cyan = Color(0xff11d4e8);
const _green = Color(0xff228b43);
const _purple = Color(0xff8740a8);

class StudioApp extends StatelessWidget {
  const StudioApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'M3U8 Studio',
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: _background,
          colorScheme: ColorScheme.fromSeed(seedColor: _blue, brightness: Brightness.dark),
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 13)),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: _fieldBackground,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xff5a6063)),
              borderRadius: BorderRadius.circular(5),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _blue, width: 2),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        home: const StudioHome(),
      );
}

class StudioHome extends StatefulWidget {
  const StudioHome({super.key});

  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  final _pattern = TextEditingController();
  final _idFrom = TextEditingController(text: '310');
  final _idTo = TextEditingController(text: '320');
  final _cdnFrom = TextEditingController(text: '1');
  final _cdnTo = TextEditingController(text: '1');
  final _ipFrom = TextEditingController(text: '192.168.1.1');
  final _ipTo = TextEditingController(text: '192.168.1.1');
  final _portFrom = TextEditingController(text: '80');
  final _portTo = TextEditingController(text: '80');
  final _idsText = TextEditingController();
  final _randomCount = TextEditingController(text: '10');
  final _input = TextEditingController();
  final _filter = TextEditingController();
  final _workers = TextEditingController(text: '12');

  late final Player _player;
  late final VideoController _video;
  StreamSubscription<bool>? _playingSubscription;
  int _page = 0;
  String _idSource = 'Numeric range';
  String _pickedFile = 'No file selected';
  PlatformFile? _playlistFile;
  List<Channel> _loaded = [];
  final List<Channel> _verified = [];
  final Map<String, StreamCheck> _checks = {};
  final List<String> _logs = [];
  Channel? _current;
  String? _selectedValid;
  bool _testing = false;
  bool _cancelTesting = false;
  bool _importing = false;
  String _importStatus = '';
  bool _generating = false;
  bool _playing = false;
  int _tested = 0;
  int _reachable = 0;
  double _volume = 75;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _video = VideoController(_player);
    _player.setVolume(_volume);
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _playing = playing);
      final current = _current;
      if (playing && current != null && !_verified.any((c) => c.url == current.url)) {
        setState(() {
          _verified.add(current);
          _selectedValid = current.url;
        });
        _log('[PLAYBACK] ${current.name} - playback started');
      }
    });
  }

  @override
  void dispose() {
    _cancelTesting = true;
    _playingSubscription?.cancel();
    _player.dispose();
    for (final controller in [
      _pattern, _idFrom, _idTo, _cdnFrom, _cdnTo, _ipFrom, _ipTo,
      _portFrom, _portTo, _idsText, _randomCount, _input, _filter, _workers,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _log(String message, {bool repaint = true}) {
    final time = TimeOfDay.now();
    final stamp = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    _logs.add('[$stamp] $message');
    if (_logs.length > 250) _logs.removeAt(0);
    if (mounted && repaint) setState(() {});
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  void _insertToken(String value) {
    final selection = _pattern.selection;
    final a = selection.isValid ? selection.start : _pattern.text.length;
    final b = selection.isValid ? selection.end : _pattern.text.length;
    final old = _pattern.text;
    _pattern.value = TextEditingValue(
      text: old.replaceRange(a, b, value),
      selection: TextSelection.collapsed(offset: a + value.length),
    );
  }

  Future<void> _pickIds() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose ID list', type: FileType.custom,
        allowedExtensions: ['txt', 'csv'],
      );
      if (file == null) return;
      _idsText.text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      setState(() => _idSource = 'Uploaded ID list');
      _notice('ID list loaded.');
    } catch (e) {
      _notice('Cannot read ID list: $e');
    }
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final idSource = _idSource;
      final idFrom = _idFrom.text;
      final idTo = _idTo.text;
      final randomCount = _randomCount.text;
      final idsText = _idsText.text;
      final pattern = _pattern.text;
      final cdnFrom = _cdnFrom.text;
      final cdnTo = _cdnTo.text;
      final ipFrom = _ipFrom.text;
      final ipTo = _ipTo.text;
      final portFrom = _portFrom.text;
      final portTo = _portTo.text;
      final channels = await Isolate.run(() {
        final ids = switch (idSource) {
          'Random IDs' => RangeGenerator.randomIds(idFrom, idTo, randomCount),
          'Pasted ID list' || 'Uploaded ID list' => RangeGenerator.idList(idsText),
          _ => RangeGenerator.numberRange(idFrom, idTo, 'ID'),
        };
        return RangeGenerator.generate(
          pattern: pattern,
          ids: ids,
          cdns: RangeGenerator.numberRange(cdnFrom, cdnTo, 'CDN'),
          ips: RangeGenerator.ipRange(ipFrom, ipTo),
          ports: RangeGenerator.numberRange(portFrom, portTo, 'port'),
        );
      });
      if (channels.isEmpty) throw const FormatException('No valid HTTP(S) URLs generated.');
      if (!mounted) return;
      _load(channels);
    } catch (e) {
      _notice('$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _pickPlaylist() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Browse M3U or JSON playlist', type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8', 'json', 'txt'],
      );
      if (file == null) return;
      setState(() {
        _pickedFile = file.name;
        _playlistFile = file;
        _input.clear();
      });
      _notice('File ready: $_pickedFile');
    } catch (e) {
      _notice('File read failed: $e');
    }
  }

  Future<File?> _fetchPlaylist(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..autoUncompress = true;
    Directory? temporary;
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final mimeType = response.headers.contentType?.mimeType ?? '';
      if (mimeType.startsWith('video/') ||
          (mimeType.startsWith('audio/') && !mimeType.contains('mpegurl'))) {
        return null;
      }
      final downloadDirectory = await Directory.systemTemp.createTemp('m3u8_playlist_');
      temporary = downloadDirectory;
      final file = File('${downloadDirectory.path}${Platform.pathSeparator}downloaded.txt');
      final outputSink = file.openWrite();
      sink = outputSink;
      var received = 0;
      var lastProgress = DateTime.now();
      var firstChunk = true;
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        if (firstChunk) {
          firstChunk = false;
          final sample = utf8.decode(chunk.take(512).toList(), allowMalformed: true)
              .replaceFirst('\ufeff', '').trimLeft();
          final recognizable = sample.startsWith('{') || sample.startsWith('[') ||
              sample.startsWith('#EXTM3U') || sample.startsWith('#EXTINF') ||
              sample.startsWith('http://') || sample.startsWith('https://');
          if (!recognizable) {
            await outputSink.close();
            sink = null;
            await downloadDirectory.delete(recursive: true);
            temporary = null;
            return null;
          }
        }
        outputSink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastProgress).inMilliseconds >= 400 && mounted) {
          final total = response.contentLength;
          setState(() => _importStatus = total > 0
              ? 'Downloading ${(100 * received / total).toStringAsFixed(1)}% · ${(received / 1048576).toStringAsFixed(1)} MB'
              : 'Downloading ${(received / 1048576).toStringAsFixed(1)} MB');
          lastProgress = now;
        }
      }
      await outputSink.flush();
      await outputSink.close();
      sink = null;
      return file;
    } catch (_) {
      await sink?.close();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Channel>> _parsePlaylistFile(String path, String source) => Isolate.run(() async {
        final content = await File(path).readAsString();
        return PlaylistParser.parse(content, source: source);
      });

  Future<void> _import() async {
    if (_importing) return;
    setState(() { _importing = true; _importStatus = 'Preparing input...'; });
    try {
      final raw = _input.text.trim();
      late final List<Channel> channels;
      if (raw.isEmpty && _playlistFile != null) {
        final picked = _playlistFile!;
        final sourceName = picked.name;
        final filePath = picked.path;
        if (filePath != null) {
          setState(() => _importStatus = 'Parsing $sourceName in background...');
          channels = await _parsePlaylistFile(filePath, sourceName);
        } else {
          final content = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
          setState(() => _importStatus = 'Parsing $sourceName in background...');
          channels = await Isolate.run(() => PlaylistParser.parse(content, source: sourceName));
        }
      } else {
        File? downloaded;
        if (PlaylistParser.isWebUrl(raw) && !raw.contains('\n')) {
          final path = Uri.parse(raw).path.toLowerCase();
          final directStream = ['.m3u8', '.ts', '.mp4', '.mkv', '.avi', '.mpd']
              .any(path.endsWith);
          if (!directStream) {
            downloaded = await _fetchPlaylist(raw);
          }
        }
        try {
          if (downloaded != null) {
            setState(() => _importStatus = 'Parsing downloaded playlist in background...');
            channels = await _parsePlaylistFile(downloaded.path, raw);
          } else {
            setState(() => _importStatus = 'Parsing input in background...');
            channels = await Isolate.run(() => PlaylistParser.parse(raw, source: 'Pasted input'));
          }
        } finally {
          if (downloaded != null) {
            final tempDir = downloaded.parent;
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
          }
        }
      }
      if (channels.isEmpty) throw const FormatException('No valid HTTP(S) entries found.');
      if (!mounted) return;
      _load(channels);
    } catch (e) {
      _notice('Import failed: $e');
    } finally {
      if (mounted) setState(() { _importing = false; _importStatus = ''; });
    }
  }

  void _load(List<Channel> channels) {
    _cancelTesting = true;
    _player.stop();
    setState(() {
      _loaded = channels;
      _verified.clear();
      _checks.clear();
      _current = null;
      _selectedValid = null;
      _tested = 0;
      _reachable = 0;
      _page = 3;
    });
    _log('[LOAD] ${channels.length} unique streams loaded');
  }

  Future<void> _check({required bool quick}) async {
    if (_testing || _loaded.isEmpty) return;
    final targets = List<Channel>.from(_loaded);
    final workerCount = int.tryParse(_workers.text.trim());
    if (workerCount == null || workerCount < 1) {
      _notice('Concurrent requests must be a positive number.');
      return;
    }
    setState(() {
      _testing = true;
      _cancelTesting = false;
      _tested = 0;
      _reachable = 0;
      _checks.clear();
    });
    _log('[TEST] ${quick ? 'Fast HEAD' : 'HEAD/GET'} checking ${targets.length} streams ($workerCount concurrent)');
    var index = 0;
    final refresh = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    Future<void> worker() async {
      final checker = StreamChecker();
      try {
        while (!_cancelTesting && index < targets.length && mounted) {
          final channel = targets[index++];
          final result = await checker.check(channel.url, quick: quick);
          if (!mounted || _cancelTesting) break;
          _checks[channel.url] = result;
          _tested++;
          if (result.reachable) {
            _reachable++;
            _log('[HTTP OK] ${channel.name} (${result.detail})', repaint: false);
          }
        }
      } finally {
        checker.close();
      }
    }
    try {
      await Future.wait(List.generate(
        workerCount < targets.length ? workerCount : targets.length, (_) => worker()));
    } finally {
      refresh.cancel();
    }
    if (!mounted) return;
    final wasStopped = _cancelTesting;
    setState(() => _testing = false);
    _log('[DONE] Checked $_tested/${targets.length}; HTTP OK: '
        '$_reachable'
        '${wasStopped ? ' (stopped)' : ''}');
  }

  Future<void> _play(Channel channel) async {
    setState(() {
      _current = channel;
      _playing = false;
    });
    _log('[PLAY] Opening ${channel.name}');
    try {
      await _player.open(Media(channel.url));
    } catch (e) {
      _notice('Player could not open stream: $e');
      _log('[ERROR] Could not open ${channel.name}');
    }
  }

  Future<void> _saveM3u() async {
    if (_verified.isEmpty) {
      _notice('Play a stream successfully before exporting the verified list.');
      return;
    }
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export playback-tested streams',
        fileName: 'M3U8-Studio-Verified.m3u',
        bytes: Uint8List.fromList(utf8.encode(PlaylistParser.asM3u(_verified))),
        mimeType: 'audio/x-mpegurl',
        type: FileType.custom,
        allowedExtensions: ['m3u'],
      );
      if (path == null) return;
      _notice('Saved ${_verified.length} entries to $path');
      _log('[EXPORT] Saved ${_verified.length} channels');
    } catch (e) {
      _notice('Export failed: $e');
    }
  }

  Future<void> _editVerified() async {
    final index = _verified.indexWhere((e) => e.url == _selectedValid);
    if (index < 0) return;
    final controller = TextEditingController(text: _verified[index].name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit channel name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    setState(() => _verified[index] = _verified[index].copyWith(name: name));
  }

  void _moveVerified(int amount) {
    final index = _verified.indexWhere((e) => e.url == _selectedValid);
    final next = index + amount;
    if (index < 0 || next < 0 || next >= _verified.length) return;
    setState(() {
      final entry = _verified.removeAt(index);
      _verified.insert(next, entry);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Row(
          children: [
            _sidebar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 20, 16),
                child: Stack(children: [
                  Positioned.fill(child: Offstage(
                    offstage: _page == 4,
                    child: switch (_page) {
                      0 => _dashboard(),
                      1 => _rangePage(),
                      2 => _filePage(),
                      3 => _studioPage(),
                      _ => const SizedBox.shrink(),
                    },
                  )),
                  // Keep split results alive when moving between sidebar tabs.
                  Positioned.fill(child: Offstage(
                    offstage: _page != 4,
                    child: const JsonSplitterPage(),
                  )),
                ]),
              ),
            ),
          ],
        ),
      );

  Widget _sidebar() => Container(
        width: 210,
        color: _side,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 26, 10, 25),
              child: Row(children: [
                Icon(Icons.bolt, color: Colors.white, size: 24),
                SizedBox(width: 8),
                Expanded(child: Text('M3U8 STUDIO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19))),
              ]),
            ),
            _navigation(0, Icons.dashboard_outlined, 'Dashboard'),
            _navigation(1, Icons.pin_outlined, 'ID Range Tester'),
            _navigation(2, Icons.folder_open_outlined, 'File / URL Tester'),
            _navigation(3, Icons.live_tv_outlined, 'Playlist & Player Studio'),
            _navigation(4, Icons.splitscreen_outlined, 'Json Spliter'),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('Developed by Md Jahidul Islam\n© 2026 M3U8 Studio',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Color(0xff9aa4ae))),
            ),
          ],
        ),
      );

  Widget _navigation(int index, IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
        child: Material(
          color: index == _page ? _blue : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: () => setState(() => _page = index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Row(children: [
                Icon(icon, size: 14),
                const SizedBox(width: 5),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
              ]),
            ),
          ),
        ),
      );

  Widget _heading(IconData icon, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(children: [
          Icon(icon, size: 23),
          const SizedBox(width: 9),
          Flexible(child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))),
        ]),
      );

  Widget _dashboard() => SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Welcome to  M3U8 Studio',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Optimized IPTV Stream Tester & Manager for Windows PCs.',
              style: TextStyle(color: Color(0xff9ba6b1))),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.rocket_launch_outlined, size: 19),
                SizedBox(width: 8),
                Text('Quick Instructions:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              SizedBox(height: 16),
              Text('Local Edition  |  No license server  |  No account required',
                  style: TextStyle(color: _cyan, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('1. Load links from ID ranges, ID lists, an M3U/JSON file, or a URL.\n'
                  '2. Use a pattern token to generate URL combinations.\n'
                  '3. Quick Check tests HTTP availability; select a channel to try playback.\n'
                  '4. Streams that start playing appear in the exportable list.\n'
                  '5. Use Json Spliter to divide large JSON files into parts.'),
              SizedBox(height: 12),
              Text('Only test playlists and streams you own or have permission to access.',
                  style: TextStyle(color: Color(0xffaab1b8), fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _metric('Loaded', '${_loaded.length}', Icons.playlist_play),
            _metric('HTTP OK', '$_reachable', Icons.check_circle_outline),
            _metric('Playback started', '${_verified.length}', Icons.live_tv),
          ]),
        ]),
      );

  Widget _metric(String title, String value, IconData icon) => Container(
        width: 180,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, size: 22, color: _cyan),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ]),
      );

  Widget _rangePage() => SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _heading(Icons.pin_outlined, 'ID Range Pattern Tester'),
          const Text('Pattern placeholders: {id}, {cdn-numer}, {ip}, {port}'),
          const SizedBox(height: 7),
          TextField(controller: _pattern, decoration: const InputDecoration(hintText: 'https://{ip}:{port}/live/{id}/index.m3u8')),
          const SizedBox(height: 16),
          Wrap(spacing: 5, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Insert at cursor:  '),
            for (final token in ['{id}', '{cdn-numer}', '{ip}', '{port}'])
              _action(token, _blue, () => _insertToken(token), width: 95),
          ]),
          const SizedBox(height: 15),
          Row(children: [
            const Text('ID source:  '),
            SizedBox(width: 208, child: DropdownButtonFormField<String>(
              initialValue: _idSource,
              isDense: true,
              items: ['Numeric range', 'Random IDs', 'Pasted ID list', 'Uploaded ID list']
                  .map((source) => DropdownMenuItem(value: source, child: Text(source, style: const TextStyle(fontSize: 12))))
                  .toList(),
              onChanged: (v) => setState(() => _idSource = v ?? 'Numeric range'),
            )),
          ]),
          const SizedBox(height: 10),
          if (_idSource == 'Numeric range' || _idSource == 'Random IDs') ...[
            _inputRow('Start ID:', _idFrom, 'End ID:', _idTo, firstWidth: 90, secondWidth: 90),
            if (_idSource == 'Random IDs')
              _inputRow('Count:', _randomCount, '', null, firstWidth: 90),
          ] else ...[
            TextField(controller: _idsText, maxLines: 3,
                decoration: const InputDecoration(hintText: 'Paste one ID per line or separate with commas')),
            const SizedBox(height: 6),
            if (_idSource == 'Uploaded ID list')
              Align(alignment: Alignment.centerLeft,
                  child: _action('Browse ID File', _blue, _pickIds, width: 160)),
          ],
          const SizedBox(height: 9),
          _inputRow('Start CDN:', _cdnFrom, 'End CDN:', _cdnTo, firstWidth: 90, secondWidth: 90),
          _inputRow('Start IP:', _ipFrom, 'End IP:', _ipTo, firstWidth: 135, secondWidth: 135),
          _inputRow('Start Port:', _portFrom, 'End Port:', _portTo, firstWidth: 90, secondWidth: 90),
          const SizedBox(height: 32),
          _action(_generating ? 'Generating links...' : 'Load Links & Go to Testing Studio',
              _blue, _generating ? null : _generate, height: 42),
        ]),
      );

  Widget _inputRow(String firstLabel, TextEditingController first,
      String secondLabel, TextEditingController? second,
      {double firstWidth = 100, double secondWidth = 100}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 145 + firstWidth,
              child: Row(children: [
                SizedBox(width: 70, child: Text(firstLabel, style: const TextStyle(fontSize: 12))),
                SizedBox(width: firstWidth, child: TextField(controller: first)),
              ])),
          if (second != null) Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 70, child: Text(secondLabel, style: const TextStyle(fontSize: 12))),
            SizedBox(width: secondWidth, child: TextField(controller: second)),
          ]),
        ]),
      );

  Widget _filePage() => SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _heading(Icons.folder_open_outlined, 'Load File or Smart Auto-Detect Input'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(9)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_pickedFile, style: const TextStyle(color: _cyan, fontSize: 12)),
              const SizedBox(height: 10),
              _action('Browse Playlist File', const Color(0xff3c3d40), _pickPlaylist, width: 180),
              if (_playlistFile != null) const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Selected file is read directly when you click Load; it is not copied into the text box.',
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          const Text('Or Paste M3U Playlist / JSON / Single Link (Auto-Detect):'),
          const SizedBox(height: 10),
          Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TextField(
              controller: _input,
              maxLines: 7,
              decoration: const InputDecoration(hintText: '#EXTM3U\n#EXTINF:-1,Example\nhttps://example.com/live.m3u8'),
            ),
          )),
          const SizedBox(height: 20),
          _action(_importing ? 'Loading...' : 'Load & Proceed to Testing Studio',
              _green, _importing ? null : _import, height: 42),
          if (_importing) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 7),
            Text(_importStatus, style: const TextStyle(color: _cyan, fontSize: 12)),
          ],
        ]),
      );

  Widget _studioPage() => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final left = _studioLeft();
          final right = _studioRight();
          if (compact) {
            return SingleChildScrollView(child: Column(children: [
              left, const SizedBox(height: 18), right,
            ]));
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 51, child: left),
            const SizedBox(width: 20),
            Expanded(flex: 49, child: right),
          ]);
        },
      );

  Widget _studioLeft() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('⚡  Studio Control & Valid List',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _action(_testing ? 'Stop Testing' : 'Start Testing',
              _green, _testing ? () => setState(() => _cancelTesting = true) : () => _check(quick: false))),
          const SizedBox(width: 9),
          Expanded(child: _action('Quick HEAD Check', _blue, _testing ? null : () => _check(quick: true))),
          const SizedBox(width: 9),
          Expanded(child: _action('Save M3U', _purple, _saveM3u)),
        ]),
        const SizedBox(height: 17),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Concurrent checks:', style: TextStyle(fontSize: 11)),
          SizedBox(width: 62, height: 34, child: TextField(
            controller: _workers,
            keyboardType: TextInputType.number,
          )),
          const Text('More workers may be faster but use more network resources.',
              style: TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
        const SizedBox(height: 7),
        Text('${_testing ? 'Testing...' : 'Ready.'}  Loaded: ${_loaded.length}  '
            '| Tested: $_tested | HTTP OK: $_reachable',
            style: const TextStyle(color: _cyan, fontSize: 11)),
        const SizedBox(height: 18),
        Row(children: [
          const Expanded(child: Text('Loaded List (awaiting validation)',
              style: TextStyle(fontWeight: FontWeight.bold))),
          Text('Loaded Channels: ${_loaded.length}',
              style: const TextStyle(color: Color(0xff58d7ff), fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 9),
        TextField(
          controller: _filter,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Filter by name, URL or group...',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
        ),
        const SizedBox(height: 7),
        _channelList(),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('Valid List (playback started)',
              style: TextStyle(fontWeight: FontWeight.bold))),
          Text('Player Started: ${_verified.length}',
              style: const TextStyle(color: Color(0xff5bdf82), fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 5, runSpacing: 6, children: [
          _action('Edit', const Color(0xffdf650b), _editVerified, width: 73),
          _action('▲ Up', const Color(0xff414247), () => _moveVerified(-1), width: 66),
          _action('▼ Down', const Color(0xff414247), () => _moveVerified(1), width: 78),
          _action('Clear Loaded', const Color(0xff9d171e), () {
            _cancelTesting = true;
            _player.stop();
            setState(() { _loaded.clear(); _checks.clear(); _tested = 0; _reachable = 0; _current = null; });
            _log('[CLEAR] Loaded list cleared');
          }, width: 112),
          _action('Delete', const Color(0xffb72d30), () {
            setState(() {
              _verified.removeWhere((e) => e.url == _selectedValid);
              _selectedValid = null;
            });
          }, width: 76),
        ]),
        const SizedBox(height: 7),
        Container(
          height: 156,
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(6)),
          child: _verified.isEmpty
              ? const Center(child: Text('Play a channel to add it here.', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  itemCount: _verified.length,
                  itemBuilder: (context, i) {
                    final entry = _verified[i];
                    final selected = _selectedValid == entry.url;
                    return InkWell(
                      onTap: () { setState(() => _selectedValid = entry.url); _play(entry); },
                      child: Container(
                        color: selected ? _blue : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                        child: Text('◉  ${entry.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    );
                  }),
        ),
      ]);

  Widget _channelList() {
    final query = _filter.text.trim().toLowerCase();
    final channels = query.isEmpty ? _loaded : _loaded.where((e) =>
        e.name.toLowerCase().contains(query) || e.url.toLowerCase().contains(query) ||
        e.group.toLowerCase().contains(query)).toList();
    return Container(
      height: 199,
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(6)),
      child: channels.isEmpty
          ? Center(child: Text(_loaded.isEmpty ? 'No streams loaded yet.' : 'No matches.',
              style: const TextStyle(color: Colors.white54)))
          : ListView.builder(
              itemCount: channels.length,
              itemBuilder: (context, i) {
                final entry = channels[i];
                final check = _checks[entry.url];
                final selected = _current?.url == entry.url;
                return Tooltip(
                  message: entry.url,
                  child: InkWell(
                    onTap: () => _play(entry),
                    child: Container(
                      color: selected ? _blue : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      child: Row(children: [
                        if (check != null)
                          Icon(check.reachable ? Icons.check_circle : Icons.cancel,
                              color: check.reachable ? Colors.greenAccent : Colors.redAccent,
                              size: 12),
                        Expanded(child: Text('• ${entry.name} — ${entry.url}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11))),
                      ]),
                    ),
                  ),
                );
              }),
    );
  }

  Widget _studioRight() => Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        decoration: BoxDecoration(color: const Color(0xff161616), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: Text('▣  Live Player Monitor',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                color: Colors.black,
                child: _current == null
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.live_tv_outlined, size: 48, color: Colors.white38),
                        SizedBox(height: 9),
                        Text('Select a loaded channel to play', style: TextStyle(color: Colors.white54)),
                      ]))
                    : Video(controller: _video, controls: NoVideoControls),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Text(_current == null ? 'Not playing' : '${_playing ? 'Playing' : 'Selected'}: ${_current!.name}',
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _cyan, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Wrap(spacing: 5, runSpacing: 5, children: [
            _action('▶ Play', _green, _current == null ? null : _player.play, width: 75),
            _action('Ⅱ Pause', const Color(0xffee7b0a), _current == null ? null : _player.pause, width: 75),
            _action('◼ Stop', const Color(0xffc33438), _current == null ? null : _player.stop, width: 75),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Text('Volume:', style: TextStyle(fontSize: 11)),
            Expanded(child: Slider(
              value: _volume, min: 0, max: 100,
              onChanged: (value) { setState(() => _volume = value); _player.setVolume(value); },
            )),
            Text('${_volume.round()}%', style: const TextStyle(fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('Activity Logs:', style: TextStyle(fontWeight: FontWeight.bold))),
            _action('Clear Logs', const Color(0xff414247), () => setState(_logs.clear), width: 87),
          ]),
          const SizedBox(height: 5),
          Container(
            height: 148,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(5)),
            child: _logs.isEmpty
                ? const Center(child: Text('No activity yet.', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    reverse: true,
                    itemCount: _logs.length,
                    itemBuilder: (context, i) => Text(_logs[_logs.length - 1 - i],
                        style: const TextStyle(fontSize: 10, height: 1.3)),
                  ),
          ),
        ]),
      );

  Widget _action(String title, Color color, VoidCallback? onPressed,
      {double? width, double height = 35}) => SizedBox(
        width: width,
        height: height,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: color.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(title, textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      );
}
