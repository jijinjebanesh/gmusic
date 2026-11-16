import 'download_file.dart';

const bool downloadsSupported = false;

Future<DownloadFile> createDownloadFile(
  String userId,
  String trackId,
  String name, {
  bool appendToPartial = false,
}) => Future.error(
  UnsupportedError('Offline downloads are not supported on this platform.'),
);

Future<int> partialDownloadLength(
  String userId,
  String trackId,
  String name,
) async => 0;

Future<void> deletePartialDownload(
  String userId,
  String trackId,
  String name,
) async {}

Future<bool> downloadFileExists(String path) async => false;

Future<void> deleteDownloadFile(String path) async {}
