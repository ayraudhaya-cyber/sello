/// Non-web platforms: no browser download.
void downloadBrowserFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError(
    'File download is only available in the web app.',
  );
}
