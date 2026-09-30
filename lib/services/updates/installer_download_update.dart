/// Bytes received versus the file size, when the server sent a length.
double? downloadFraction(int received, int? total) {
  if (total == null || total <= 0) return null;
  final value = received / total;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

class InstallerDownloadUpdate {
  const InstallerDownloadUpdate({
    required this.received,
    this.total,
    this.filePath,
    this.error,
  });

  final int received;
  final int? total;
  final String? filePath;
  final String? error;

  double? get fraction => downloadFraction(received, total);
  bool get isComplete => filePath != null && error == null;
}
