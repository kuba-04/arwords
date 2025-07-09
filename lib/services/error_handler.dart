class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
}

class StorageException implements Exception {
  final String message;
  StorageException(this.message);
}
