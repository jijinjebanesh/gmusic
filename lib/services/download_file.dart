abstract interface class DownloadFile {
  String get finalPath;
  Future<void> write(List<int> bytes);
  Future<String> complete();
  Future<void> pause();
  Future<void> cancel();
}
