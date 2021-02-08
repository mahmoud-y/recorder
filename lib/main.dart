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
  FlutterSoundPlayer _soundPlayer = FlutterSoundPlayer();
  StreamSubscription _soundPlayerSubscription;
  bool _isAudioSessionOpened = false;
  File _playingRecord;
  String _playingRecordPositionText = '00:00';
  double _playingRecordPosition = 0.0;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _soundPlayer = null;
    _soundPlayerSubscription = null;
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

  Future<void> _startSoundPlayer(File record) async {
    if (!_isAudioSessionOpened) {
      await _soundPlayer.openAudioSession();
      await _soundPlayer.setSubscriptionDuration(Duration(milliseconds: 10));
      setState(() {
        _isAudioSessionOpened = true;
      });
    }
    await _soundPlayer.startPlayer(
        fromURI: record.path,
        codec: Codec.aacADTS,
        whenFinished: () {
          _stopSoundPlayer();
        });
    _soundPlayerSubscription = _soundPlayer.onProgress.listen((e) {
      if (e != null) {
        setState(() {
          _playingRecordPosition = e.position.inMilliseconds.toDouble();
          _playingRecordPositionText = DateFormat('mm:ss').format(
              DateTime.fromMillisecondsSinceEpoch(e.position.inMilliseconds));
        });
      }
    });
    setState(() {
      _playingRecord = record;
    });
  }

  Future<void> _seekSoundPlayer(double value) async {
    if (_soundPlayer.isPlaying) {
      await _soundPlayer.seekToPlayer(Duration(milliseconds: value.toInt()));
    }
  }

  Future<void> _stopSoundPlayer() async {
    if (_soundPlayer != null) {
      await _soundPlayer.stopPlayer();
      await _soundPlayer.closeAudioSession();
      await _soundPlayerSubscription.cancel();
      _soundPlayerSubscription = null;
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

  Future<ListTile> _buildListTile(int index) async {
    FlutterSoundHelper soundHelper = FlutterSoundHelper();
    File record = _records.elementAt(index);

    Widget leading;
    if (_selectedRecords.isNotEmpty) {
      leading = _selectedRecords.contains(record)
          ? Icon(Icons.check_circle)
          : Icon(Icons.circle);
    }

    String titleText = record.path.split('/').last.split('.').first;
    Widget title = Text(titleText);

    Duration recordDuration = await soundHelper.duration(record.path);
    String recordDurationText;
    double sliderValue = 0.0;
    double sliderMax = recordDuration.inMilliseconds.toDouble();
    ValueChanged<double> sliderChangeHandler;
    if (record == _playingRecord) {
      sliderValue = _playingRecordPosition;
      recordDurationText = _playingRecordPositionText;
      sliderChangeHandler = _seekSoundPlayer;
    } else {
      recordDurationText = DateFormat('mm:ss').format(
          DateTime.fromMillisecondsSinceEpoch(recordDuration.inMilliseconds));
    }
    Widget subtitle;
    subtitle = Row(
      children: [
        Slider(
          value: sliderValue,
          min: 0.0,
          max: sliderMax,
          onChanged: sliderChangeHandler,
          divisions: sliderMax == 0.0 ? 1 : sliderMax.toInt(),
        ),
        Text(recordDurationText),
      ],
    );

    Widget trailing;
    if (_playingRecord == null || _playingRecord != record) {
      trailing = IconButton(
        icon: Icon(Icons.play_arrow),
        onPressed: () {
          _startSoundPlayer(record);
        },
      );
    } else {
      trailing = IconButton(
        icon: Icon(Icons.stop),
        onPressed: () {
          _stopSoundPlayer();
        },
      );
    }

    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
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
        return FutureBuilder(
          future: _buildListTile(index),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return snapshot.data;
            }
            return ListTile();
          },
        );
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
  FlutterSoundRecorder _soundRecorder = FlutterSoundRecorder();
  StreamSubscription _soundRecorderSubscription;
  String _recordPath;
  String _recordDuration = '00:00';
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _startSoundRecorder();
  }

  @override
  void dispose() async {
    _soundRecorder = null;
    _soundRecorderSubscription = null;
    super.dispose();
  }

  Future<void> _startSoundRecorder() async {
    String name = DateFormat.jm().add_MMMd().format(DateTime.now());
    setState(() {
      _recordPath = '${widget.recordsDirectory.path}/$name.aac';
    });
    await _soundRecorder.openAudioSession();
    await _soundRecorder.startRecorder(
      toFile: _recordPath,
      codec: Codec.aacADTS,
    );
    _soundRecorderSubscription = _soundRecorder.onProgress.listen((e) {
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

  Future<void> _pauseSoundRecorder() async {
    await _soundRecorder.pauseRecorder();
    setState(() {
      _isRecording = false;
    });
  }

  Future<void> _resumeSoundRecorder() async {
    await _soundRecorder.resumeRecorder();
    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopSoundRecorder(BuildContext context) async {
    await _soundRecorder.stopRecorder();
    await _soundRecorder.closeAudioSession();
    await _soundRecorderSubscription.cancel();
    setState(() {
      _isRecording = false;
    });
    Navigator.pop(context);
  }

  Future<void> _deleteRecord(BuildContext context) async {
    await _soundRecorder.stopRecorder();
    await _soundRecorder.closeAudioSession();
    await _soundRecorderSubscription.cancel();
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
                      ? _pauseSoundRecorder
                      : _resumeSoundRecorder),
                  child: (_isRecording
                      ? Icon(Icons.pause)
                      : Icon(Icons.play_arrow))),
              ElevatedButton(
                  onPressed: () => _stopSoundRecorder(context),
                  child: Icon(Icons.save)),
            ],
          ),
        ],
      ),
    );
  }
}
