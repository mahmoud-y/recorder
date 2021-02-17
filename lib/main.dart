import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sound/flutter_sound.dart';

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
  FlutterSoundPlayer _player = FlutterSoundPlayer();
  File _playingRecord;
  Duration _playingRecordDuration;
  Duration _playingRecordPosition;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _player = null;
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
    await _player.openAudioSession();
    await _player.setSubscriptionDuration(Duration(milliseconds: 10));
    await _player.startPlayer(
        fromURI: record.path,
        codec: Codec.aacADTS,
        whenFinished: () {
          _stopPlayer();
        });
    _player.onProgress.listen((e) {
      if (e != null) {
        setState(() {
          _playingRecordDuration = e.duration;
          _playingRecordPosition = e.position;
        });
      }
    });
    setState(() {
      _playingRecord = record;
    });
  }

  Future<void> _seekPlayer(double value) async {
    await _player.seekToPlayer(Duration(milliseconds: value.toInt()));
  }

  Future<void> _stopPlayer() async {
    await _player.stopPlayer();
    await _player.closeAudioSession();
    setState(() {
      _playingRecord = null;
      _playingRecordDuration = null;
      _playingRecordPosition = null;
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
        onPressed: () {
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

  File record;
  FlutterSoundPlayer player;
  File playingRecord;
  Duration playingRecordDuration;
  Duration playingRecordPosition;
  ValueChanged<File> handlePlayingRecord;
  bool isSelectable;
  bool isSelected;
  ValueChanged<File> selectionHandler;
  ValueChanged<File> startPlayer;
  ValueChanged<double> seekPlayer;
  VoidCallback stopPlayer;
  bool isPlaying;

  @override
  _RecordListTileState createState() => _RecordListTileState();
}

class _RecordListTileState extends State<RecordListTile> {
  FlutterSoundHelper soundHelper = FlutterSoundHelper();
  double _duration;
  Duration _position;

  String getRecordName() {
    String millisecondsSinceEpochString = widget.record.path.split('/').last.split('.').first;
    int millisecondsSinceEpoch = int.parse(millisecondsSinceEpochString);
    DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    return DateFormat.MMMd().add_jms().format(dateTime);
  }

  Future<void> _startPlayer(File record) async {
    if (widget.playingRecord != null) {
      await _stopPlayer();
    }
    await widget.player.openAudioSession();
    await widget.player.setSubscriptionDuration(Duration(milliseconds: 10));
    await widget.player.startPlayer(
        fromURI: widget.record.path,
        codec: Codec.aacADTS,
        whenFinished: () {
          _stopPlayer();
        });
    widget.player.onProgress.listen((e) {
      if (e != null) {
        setState(() {
          _duration = e.duration.inMilliseconds.toDouble();
          _position = e.position;
        });
      }
    });
    widget.handlePlayingRecord(record);
  }

  Future<void> _seekPlayer(double value) async {
    if (widget.player.isPlaying) {
      await widget.player.seekToPlayer(Duration(milliseconds: value.toInt()));
    }
  }

  Future<void> _stopPlayer() async {
    await widget.player.stopPlayer();
    await widget.player.closeAudioSession();
    widget.handlePlayingRecord(null);
    setState(() {
      _duration = null;
      _position = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: widget.isSelected,
      leading: (widget.isSelectable
          ? (widget.isSelected ? Icon(Icons.check_circle) : Icon(Icons.circle))
          : null),
      title: Text(getRecordName()),
      subtitle: Row(
        children: [
          Slider(
            value: (widget.isPlaying
                ? widget.playingRecordPosition.inMilliseconds.toDouble()
                : 0.0),
            min: 0.0,
            max: (widget.isPlaying
                ? widget.playingRecordDuration.inMilliseconds.toDouble()
                : 0.0),
            onChanged: (widget.isPlaying ? widget.seekPlayer : null),
            divisions: (widget.isPlaying
                ? widget.playingRecordDuration.inMilliseconds
                : 1),
          ),
          (widget.isPlaying
              ? Text(DateFormat('mm:ss').format(
                  DateTime.fromMillisecondsSinceEpoch(
                      widget.playingRecordPosition.inMilliseconds)))
              : FutureBuilder(
                  future: soundHelper.duration(widget.record.path),
                  builder: (context, snapshot) {
                    String text = '..:..';
                    if (snapshot.hasData) {
                      text = DateFormat('mm:ss').format(
                          DateTime.fromMillisecondsSinceEpoch(
                              snapshot.data.inMilliseconds));
                    }
                    return Text(text);
                  },
                )),
        ],
      ),
      trailing: widget.isPlaying
          ? IconButton(
              icon: Icon(Icons.stop),
              onPressed: () {
                // _stopPlayer();
                widget.stopPlayer();
              },
            )
          : IconButton(
              icon: Icon(Icons.play_arrow),
              onPressed: () {
                // _startPlayer(widget.record);
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
  FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  String _recordPath;
  String _recordDuration = '00:00';
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
    setState(() {
      _recordPath = '${widget.recordsDirectory.path}/$millisecondsSinceEpoch.aac';
    });
    await _recorder.openAudioSession();
    await _recorder.startRecorder(
      toFile: _recordPath,
      codec: Codec.aacADTS,
    );
    _recorder.onProgress.listen((e) {
      if (e != null && e.duration != null) {
        setState(() {
          _recordDuration = DateFormat('mm:ss').format(
              DateTime.fromMillisecondsSinceEpoch(e.duration.inMilliseconds));
        });
      }
    });
    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _pauseRecorder() async {
    await _recorder.pauseRecorder();
    setState(() {
      _isRecording = false;
    });
  }

  Future<void> _resumeRecorder() async {
    await _recorder.resumeRecorder();
    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopRecorder(BuildContext context) async {
    await _recorder.stopRecorder();
    await _recorder.closeAudioSession();
    setState(() {
      _isRecording = false;
    });
    Navigator.pop(context);
  }

  Future<void> _deleteRecord(BuildContext context) async {
    await _recorder.stopRecorder();
    await _recorder.closeAudioSession();
    setState(() {
      _isRecording = false;
    });
    File record = File(_recordPath);
    await record.delete();
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
          Text(_recordDuration),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                  onPressed: () => _deleteRecord(context),
                  child: Icon(Icons.delete)),
              ElevatedButton(
                  onPressed: (_isRecording
                      ? _pauseRecorder
                      : _resumeRecorder),
                  child: (_isRecording
                      ? Icon(Icons.pause)
                      : Icon(Icons.play_arrow))),
              ElevatedButton(
                  onPressed: () => _stopRecorder(context),
                  child: Icon(Icons.save)),
            ],
          ),
        ],
      ),
    );
  }
}
