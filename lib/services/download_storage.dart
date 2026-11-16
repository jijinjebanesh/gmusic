import 'download_storage_stub.dart'
    if (dart.library.io) 'download_storage_io.dart'
    as implementation;
import 'download_file.dart';

export 'download_file.dart';

bool get downloadsSupported => implementation.downloadsSupported;
Future<DownloadFile> createDownloadFile(
  String userId,
  String trackId,
  String name, {
  bool appendToPartial = false,
}) => implementation.createDownloadFile(
  userId,
  trackId,
  name,
  appendToPartial: appendToPartial,
);
Future<int> partialDownloadLength(String userId, String trackId, String name) =>
    implementation.partialDownloadLength(userId, trackId, name);
Future<void> deletePartialDownload(
  String userId,
  String trackId,
  String name,
) => implementation.deletePartialDownload(userId, trackId, name);
Future<bool> downloadFileExists(String path) =>
    implementation.downloadFileExists(path);
Future<void> deleteDownloadFile(String path) =>
    implementation.deleteDownloadFile(path);
