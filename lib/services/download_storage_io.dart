import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'download_file.dart';

const bool downloadsSupported = true;

Future<DownloadFile> createDownloadFile(
  String userId,
  String trackId,
  String name, {
  bool appendToPartial = false,
}) async {
  final temporary = await _temporaryFile(userId, trackId, name);
  if (!appendToPartial && await temporary.exists()) await temporary.delete();
  final finalPath = temporary.path.substring(0, temporary.path.length - 5);
  return _IoDownloadFile(temporary, File(finalPath), append: appendToPartial);
}

Future<File> _temporaryFile(String userId, String trackId, String name) async {
  final root = await getApplicationSupportDirectory();
  final userFolder = _safe(userId);
  final trackKey = _safe(trackId);
  final extension =
      RegExp(r'\.[a-zA-Z0-9]{1,8}$').firstMatch(name)?.group(0) ?? '.audio';
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}downloads${Platform.pathSeparator}$userFolder',
  );
  await directory.create(recursive: true);
  final finalPath =
      '${directory.path}${Platform.pathSeparator}$trackKey$extension';
  return File('$finalPath.part');
}

Future<int> partialDownloadLength(
  String userId,
  String trackId,
  String name,
) async {
  final file = await _temporaryFile(userId, trackId, name);
  return await file.exists() ? file.length() : 0;
}

Future<void> deletePartialDownload(
  String userId,
  String trackId,
  String name,
) async {
  final file = await _temporaryFile(userId, trackId, name);
  if (await file.exists()) await file.delete();
}

String _safe(String value) => value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

Future<bool> downloadFileExists(String path) => File(path).exists();

Future<void> deleteDownloadFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

class _IoDownloadFile implements DownloadFile {
  _IoDownloadFile(this._temporary, this._target, {required bool append})
    : _sink = _temporary.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
  final File _temporary;
  final File _target;
  final IOSink _sink;
  bool _closed = false;

  @override
  String get finalPath => _target.path;

  @override
  Future<void> write(List<int> bytes) async {
    _sink.add(bytes);
  }

  @override
  Future<String> complete() async {
    if (!_closed) {
      await _sink.flush();
      await _sink.close();
      _closed = true;
    }
    if (await _target.exists()) await _target.delete();
    await _temporary.rename(_target.path);
    return _target.path;
  }

  @override
  Future<void> pause() async {
    if (!_closed) {
      await _sink.flush();
      await _sink.close();
      _closed = true;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_closed) {
      await _sink.close();
      _closed = true;
    }
    if (await _temporary.exists()) await _temporary.delete();
  }
}
