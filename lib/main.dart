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

  void _handlePlayingRecord(File record) {
    setState(() {
      _playingRecord = record;
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
        onPressed: () async {
          await _stopPlayer();
          _selectedRecords.forEach((record) {
            record.delete();
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
          return RecordListTile(
            record: _records.elementAt(index),
            player: _player,
            playingRecord: _playingRecord,
            playingRecordDuration: _playingRecordDuration,
            playingRecordPosition: _playingRecordPosition,
            handlePlayingRecord: _handlePlayingRecord,
            isSelectable: _selectedRecords.isNotEmpty,
            isSelected: _selectedRecords.contains(_records.elementAt(index)),
            selectionHandler: _handleRecordSelection,
            startPlayer: _startPlayer,
            seekPlayer: _seekPlayer,
            stopPlayer: _stopPlayer,
            isPlaying: _records.elementAt(index) == _playingRecord,
          );
        },
        separatorBuilder: (context, index) => Divider(),
      ),
      floatingActionButton: NewRecordButton(
          recordsDirectory: _recordsDirectory, loadRecords: _loadRecords),
    );
  }
}

class RecordListTile extends StatefulWidget {
  RecordListTile(
      {Key key,
      this.record,
      this.player,
      this.playingRecord,
      this.playingRecordDuration,
      this.playingRecordPosition,
      this.handlePlayingRecord,
      this.isSelectable,
      this.isSelected,
      this.selectionHandler,
      this.startPlayer,
      this.seekPlayer,
      this.stopPlayer,
      this.isPlaying})
      : super(key: key);

  final File record;
  final AudioPlayer player;
  final File playingRecord;
  final Duration playingRecordDuration;
  final Duration playingRecordPosition;
  final ValueChanged<File> handlePlayingRecord;
  final bool isSelectable;
  final bool isSelected;
  final ValueChanged<File> selectionHandler;
  final ValueChanged<File> startPlayer;
  final ValueChanged<double> seekPlayer;
  final VoidCallback stopPlayer;
  final bool isPlaying;

  @override
  _RecordListTileState createState() => _RecordListTileState();
}

class _RecordListTileState extends State<RecordListTile> {
  String getRecordName() {
    String millisecondsSinceEpochString =
        widget.record.path.split('/').last.split('.').first;
    int millisecondsSinceEpoch = int.parse(millisecondsSinceEpochString);
    DateTime dateTime =
        DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    return DateFormat.MMMd().add_jms().format(dateTime);
  }

  Future<Duration> getRecordDuration() async {
    AudioPlayer audioPlayer = AudioPlayer();
    await audioPlayer.setUrl(widget.record.path);
    await for (var d in audioPlayer.onDurationChanged) {
      return d;
    }
    return Duration(milliseconds: 0);
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> subtitleRowChildren = List<Widget>();
    if (widget.isPlaying) {
      subtitleRowChildren.addAll([
        Slider(
          value: widget.playingRecordPosition.inMilliseconds.toDouble(),
          min: 0.0,
          max: widget.playingRecordDuration.inMilliseconds.toDouble(),
          onChanged: widget.seekPlayer,
          divisions: (widget.playingRecordDuration.inMilliseconds > 0 ? widget.playingRecordDuration.inMilliseconds : 1),
        ),
        Text(DateFormat('mm:ss').format(
          DateTime.fromMillisecondsSinceEpoch(
              widget.playingRecordPosition.inMilliseconds))),
      ]);
    } else {
      subtitleRowChildren.add(FutureBuilder(
        future: getRecordDuration(),
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
      selected: widget.isSelected,
      leading: (widget.isSelectable
          ? (widget.isSelected ? Icon(Icons.check_circle) : Icon(Icons.circle))
          : null),
      title: Text(getRecordName()),
      subtitle: Row(
        children: subtitleRowChildren,
      ),
      trailing: widget.isPlaying
          ? IconButton(
              icon: Icon(Icons.pause),
              onPressed: () {
                widget.stopPlayer();
              },
            )
          : IconButton(
              icon: Icon(Icons.play_arrow),
              onPressed: () {
                widget.startPlayer(widget.record);
              },
            ),
      onLongPress: () {
        if (!widget.isSelectable) {
          widget.selectionHandler(widget.record);
        }
      },
      onTap: () {
        if (widget.isSelectable) {
          widget.selectionHandler(widget.record);
        }
      },
    );
  }
}

class NewRecordButton extends StatelessWidget {
  NewRecordButton({Key key, this.recordsDirectory, this.loadRecords})
      : super(key: key);

  final Directory recordsDirectory;
  final VoidCallback loadRecords;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      tooltip: 'Record',
      child: Icon(Icons.mic),
      onPressed: () async {
        if (await Permission.microphone.request().isGranted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    Recorder(recordsDirectory: recordsDirectory)),
          );
          loadRecords();
        } else {
          Scaffold.of(context).showSnackBar(
              SnackBar(content: Text('microphone permission denied')));
        }
      },
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
  void dispose() async {
    _recorder = null;
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
