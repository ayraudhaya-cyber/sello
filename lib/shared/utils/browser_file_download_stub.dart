/// Fallback for targets without a browser or a local filesystem.
Future<bool> downloadBrowserFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('File download is not available on this device.');
}
