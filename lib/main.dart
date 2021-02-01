import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isAudioSessionOpened = false;
  File _playingRecord;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _stopPlayer();
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

  void _startPlayer(File record) async {
    if (!_isAudioSessionOpened) {
      await _player.openAudioSession();
      setState(() {
        _isAudioSessionOpened = true;
      });
    }
    await _player.startPlayer(
        fromURI: record.path,
        codec: Codec.aacADTS,
        whenFinished: () {
          _stopPlayer();
        });
    setState(() {
      _playingRecord = record;
    });
  }

  Future<void> _stopPlayer() async {
    if (_player != null) {
      await _player.stopPlayer();
      await _player.closeAudioSession();
      setState(() {
        _playingRecord = null;
        _isAudioSessionOpened = false;
      });
    }
  }

  void _handleRecordSelection(int index) {
    if (_selectedRecords.contains(_records.elementAt(index))) {
      setState(() {
        _selectedRecords.remove(_records.elementAt(index));
      });
    } else {
      setState(() {
        _selectedRecords.add(_records.elementAt(index));
      });
    }
  }

  ListTile _buildListTile(int index) {
    Widget leading;
    Widget trailing;

    if (_selectedRecords.isNotEmpty) {
      leading =_selectedRecords.contains(_records.elementAt(index)) ? Icon(Icons.check_circle) : Icon(Icons.circle);
    }

    if (_playingRecord == null || _playingRecord != _records.elementAt(index)) {
      trailing = IconButton(
        icon: Icon(Icons.play_arrow),
        onPressed: () {
          _startPlayer(_records.elementAt(index));
        },
      );
    } else {
      trailing = IconButton(
        icon: Icon(Icons.stop),
        onPressed: () {
          _stopPlayer();
        },
      );
    }

    return ListTile(
      leading: leading,
      title: Text(basenameWithoutExtension(_records.elementAt(index).path)),
      trailing: trailing,
      selected: _selectedRecords.contains(_records.elementAt(index)),
      onTap: () {
        if (_selectedRecords.isNotEmpty) {
          _handleRecordSelection(index);
        }
      },
      onLongPress: () {
        if (_selectedRecords.isEmpty) {
          _handleRecordSelection(index);
        }
      },
    );
  }

  ListView _buildListView() {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _records.length,
      itemBuilder: (BuildContext context, int index) {
        if (index >= _records.length) return null;
        return _buildListTile(index);
      },
      separatorBuilder: (context, index) => Divider(),
    );
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
      body: _buildListView(),
      floatingActionButton: NewRecordButton(
          recordsDirectory: _recordsDirectory, loadRecords: _loadRecords),
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
  StreamSubscription _recorderSubscription;
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
    _recorderSubscription = null;
    super.dispose();
  }

  Future<void> _startRecorder() async {
    final prefs = await SharedPreferences.getInstance();
    int index = prefs.getInt('index') ?? 0;
    index++;
    prefs.setInt('index', index);
    setState(() {
      _recordPath = '${widget.recordsDirectory.path}/Record $index.aac';
    });
    await _recorder.openAudioSession();
    await _recorder.startRecorder(
      toFile: _recordPath,
      codec: Codec.aacADTS,
    );
    _recorderSubscription = _recorder.onProgress.listen((e) {
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
    await _recorderSubscription.cancel();
    setState(() {
      _isRecording = false;
    });
    Navigator.pop(context);
  }

  Future<void> _deleteRecord(BuildContext context) async {
    await _recorder.stopRecorder();
    await _recorder.closeAudioSession();
    await _recorderSubscription.cancel();
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
                  onPressed: () => _deleteRecord(context), child: Icon(Icons.delete)),
              ElevatedButton(
                  onPressed: (_isRecording ? _pauseRecorder : _resumeRecorder),
                  child: (_isRecording
                      ? Icon(Icons.pause)
                      : Icon(Icons.play_arrow))),
              ElevatedButton(
                  onPressed: () => _stopRecorder(context), child: Icon(Icons.save)),
            ],
          ),
        ],
      ),
    );
  }
}
