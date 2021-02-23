import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_audio_recorder/flutter_audio_recorder.dart';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recorder',
      home: Records(),
    );
  }
}

class Records extends StatefulWidget {
  @override
  _RecordsState createState() => _RecordsState();
}

class _RecordsState extends State<Records> {
  Directory _recordsDirectory;
  Set<File> _records = Set<File>();
  Set<File> _selectedRecords = Set<File>();
  File _playingRecord;
  Duration _playingRecordDuration = Duration(milliseconds: 0);
  Duration _playingRecordPosition = Duration(milliseconds: 0);
  AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration> _durationSubscription;
  StreamSubscription<Duration> _positionSubscription;
  StreamSubscription<void> _completionSubscription;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<Directory> _getRecordsDirectory() async {
    Directory applicationDocumentsDirectory =
        await getApplicationDocumentsDirectory();
    Directory recordsDirectory =
        Directory('${applicationDocumentsDirectory.path}/records');
    if (!await recordsDirectory.exists()) {
      await recordsDirectory.create();
    }
    return recordsDirectory;
  }

  void _loadRecords() async {
    _recordsDirectory = await _getRecordsDirectory();
    Set<File> records = Set<File>();
    _recordsDirectory
        .list(recursive: false, followLinks: false)
        .listen((FileSystemEntity entity) {
      if (entity is File) {
        setState(() {
          records.add(File(entity.path));
        });
      }
    });
    setState(() {
      _records = records;
    });
  }

  Future<void> _startPlayer(File record) async {
    if (_playingRecord != null) {
      await _stopPlayer();
    }
    await _player.play(record.path, isLocal: true);
    _durationSubscription = _player.onDurationChanged.listen((Duration d) {
      setState(() => _playingRecordDuration = d);
    });
    _positionSubscription = _player.onAudioPositionChanged.listen((Duration p) {
      setState(() => _playingRecordPosition = p);
    });
    _completionSubscription = _player.onPlayerCompletion.listen((event) {
      _stopPlayer();
    });
    setState(() {
      _playingRecord = record;
    });
  }

  Future<void> _seekPlayer(double value) async {
    await _player.seek(Duration(milliseconds: value.toInt()));
  }

  Future<void> _stopPlayer() async {
    await _player.stop();
    await _durationSubscription.cancel();
    await _positionSubscription.cancel();
    await _completionSubscription.cancel();
    setState(() {
      _playingRecord = null;
      _playingRecordDuration = Duration(milliseconds: 0);
      _playingRecordPosition = Duration(milliseconds: 0);
    });
  }

  void _handleRecordSelection(File record) {
    if (_selectedRecords.contains(record)) {
      setState(() {
        _selectedRecords.remove(record);
      });
    } else {
      setState(() {
        _selectedRecords.add(record);
      });
    }
  }

  String getRecordName(File record) {
    String millisecondsSinceEpochString = record.path.split('/').last.split('.').first;
    int millisecondsSinceEpoch = int.parse(millisecondsSinceEpochString);
    DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    return DateFormat.MMMd().add_jms().format(dateTime);
  }

  Future<Duration> getRecordDuration(File record) async {
    AudioPlayer audioPlayer = AudioPlayer();
    await audioPlayer.setUrl(record.path);
    await for (var d in audioPlayer.onDurationChanged) {
      return d;
    }
    return Duration(milliseconds: 0);
  }

  @override
  Widget build(BuildContext context) {
    Widget appBarLeading;
    List<Widget> appBarActions = List<Widget>();

    if (_selectedRecords.isNotEmpty) {
      appBarLeading = IconButton(
          icon: Icon(Icons.clear),
          onPressed: () {
            setState(() {
              _selectedRecords.clear();
            });
          });
      if (!_selectedRecords.containsAll(_records)) {
        appBarActions.add(IconButton(
          icon: const Icon(Icons.check_circle),
          tooltip: 'Select all',
          onPressed: () {
            setState(() {
              _selectedRecords.addAll(_records);
            });
          },
        ));
      }
      appBarActions.add(IconButton(
        icon: const Icon(Icons.delete),
        tooltip: 'Delete',
        onPressed: () {
          _selectedRecords.forEach((record) async {
            await record.delete();
          });
          setState(() {
            _selectedRecords.clear();
          });
          _loadRecords();
        },
      ));
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarLeading,
        title: Text('Recorder'),
        actions: appBarActions,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _records.length,
        itemBuilder: (BuildContext context, int index) {
          if (index >= _records.length) return null;

          File record = _records.elementAt(index);
          List<Widget> subtitleRowChildren = List<Widget>();
          if (record == _playingRecord) {
            subtitleRowChildren.addAll([
              Slider(
                value: _playingRecordPosition.inMilliseconds.toDouble(),
                min: 0.0,
                max: _playingRecordDuration.inMilliseconds.toDouble(),
                onChanged: _seekPlayer,
                divisions: (_playingRecordDuration.inMilliseconds > 0 ? _playingRecordDuration.inMilliseconds : 1),
              ),
              Text(DateFormat('mm:ss').format(
                  DateTime.fromMillisecondsSinceEpoch(
                      _playingRecordPosition.inMilliseconds))),
            ]);
          } else {
            subtitleRowChildren.add(FutureBuilder(
              future: getRecordDuration(record),
              builder: (context, snapshot) {
                String text = '..:..';
                if (snapshot.hasData) {
                  text = DateFormat('mm:ss').format(
                      DateTime.fromMillisecondsSinceEpoch(
                          snapshot.data.inMilliseconds));
                }
                return Text(text);
              },
            ));
          }
          return ListTile(
            selected: _selectedRecords.contains(record),
            leading: (_selectedRecords.isNotEmpty
                ? (_selectedRecords.contains(record) ? Icon(Icons.check_circle) : Icon(Icons.circle))
                : null),
            title: Text(getRecordName(record)),
            subtitle: Row(
              children: subtitleRowChildren,
            ),
            trailing: (record == _playingRecord)
                ? IconButton(
              icon: Icon(Icons.pause),
              onPressed: () {
                _stopPlayer();
              },
            )
                : IconButton(
              icon: Icon(Icons.play_arrow),
              onPressed: () {
                _startPlayer(record);
              },
            ),
            onLongPress: () {
              if (_selectedRecords.isEmpty) {
                _handleRecordSelection(record);
              }
            },
            onTap: () {
              if (_selectedRecords.isNotEmpty) {
                _handleRecordSelection(record);
              }
            },
          );
        },
        separatorBuilder: (context, index) => Divider(),
      ),
      floatingActionButton: Builder(
        builder: (context) {
          return FloatingActionButton(
            tooltip: 'Record',
            child: Icon(Icons.mic),
            onPressed: () async {
              if (await Permission.microphone.request().isGranted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          Recorder(recordsDirectory: _recordsDirectory)),
                );
                _loadRecords();
              } else {
                Scaffold.of(context).showSnackBar(
                    SnackBar(content: Text('microphone permission denied')));
              }
            },
          );
        },
      ),
    );
  }
}

class Recorder extends StatefulWidget {
  Recorder({Key key, this.recordsDirectory}) : super(key: key);

  final Directory recordsDirectory;

  @override
  _RecorderState createState() => _RecorderState();
}

class _RecorderState extends State<Recorder> {
  FlutterAudioRecorder _recorder;
  Timer _timer;
  Duration _recordDuration = Duration(milliseconds: 0);
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _startRecorder();
  }

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  Future<void> _startRecorder() async {
    int millisecondsSinceEpoch = DateTime.now().millisecondsSinceEpoch;
    _recorder = FlutterAudioRecorder(
        '${widget.recordsDirectory.path}/$millisecondsSinceEpoch',
        audioFormat: AudioFormat.AAC);
    await _recorder.initialized;
    await _recorder.start();
    _timer = Timer.periodic(Duration(milliseconds: 50), (Timer t) async {
      var current = await _recorder.current(channel: 0);
      setState(() {
        _recordDuration = current.duration;
      });
    });
    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _pauseRecorder() async {
    await _recorder.pause();
    setState(() {
      _isRecording = false;
    });
  }

  Future<void> _resumeRecorder() async {
    await _recorder.resume();
    setState(() {
      _isRecording = true;
    });
  }

  Future<dynamic> _stopRecorder() async {
    var result = await _recorder.stop();
    _timer.cancel();
    setState(() {
      _isRecording = false;
    });
    return result;
  }

  Future<void> _saveRecord(BuildContext context) async {
    await _stopRecorder();
    Navigator.pop(context);
  }

  Future<void> _deleteRecord(BuildContext context) async {
    var result = await _stopRecorder();
    await File(result.path).delete();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recorder'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(DateFormat('mm:ss').format(DateTime.fromMillisecondsSinceEpoch(
              _recordDuration.inMilliseconds))),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                  onPressed: () => _deleteRecord(context),
                  child: Icon(Icons.delete)),
              ElevatedButton(
                  onPressed: (_isRecording ? _pauseRecorder : _resumeRecorder),
                  child: (_isRecording
                      ? Icon(Icons.pause)
                      : Icon(Icons.play_arrow))),
              ElevatedButton(
                  onPressed: () => _saveRecord(context),
                  child: Icon(Icons.save)),
            ],
          ),
        ],
      ),
    );
  }
}
