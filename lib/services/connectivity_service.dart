import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'logger_service.dart';

class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  bool _isOnline = false;

  bool get isOnline => _isOnline;

  ConnectivityService() {
    _initConnectivity();
    _setupConnectivityListener();
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
    } catch (e) {
      AppLogger.words('Error checking connectivity: $e', level: 'error');
      _isOnline = false;
    }
  }

  void _setupConnectivityListener() {
    _connectivity.onConnectivityChanged.listen((result) {
      _updateConnectionStatus(result);
    });
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    // Consider the device online if it has any type of connection except 'none'
    _isOnline = result != ConnectivityResult.none;
    AppLogger.words(
      'Connectivity status updated: $_isOnline ($result)',
      level: 'debug',
    );
    notifyListeners();
  }
}
