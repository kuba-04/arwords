import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'logger_service.dart';

class ConnectivityService extends ChangeNotifier {
  bool _isOnline = false;
  DateTime _lastCheck = DateTime.now().subtract(const Duration(minutes: 1));
  static const Duration _cacheTimeout = Duration(seconds: 30);

  bool get isOnline => _isOnline;

  ConnectivityService() {
    _checkConnectivity();
  }

  /// Check if we can connect to Supabase (more reliable than network connectivity)
  Future<bool> checkConnectivity() async {
    // Use cached result if recent
    if (DateTime.now().difference(_lastCheck) < _cacheTimeout) {
      return _isOnline;
    }

    try {
      final supabase = Supabase.instance.client;
      // Try a simple query to test Supabase connectivity
      await supabase.from('user_profiles').select('user_id').limit(1);
      _updateConnectionStatus(true);
      return true;
    } catch (e) {
      AppLogger.words('Supabase connectivity check failed: $e', level: 'debug');
      _updateConnectionStatus(false);
      return false;
    }
  }

  Future<void> _checkConnectivity() async {
    await checkConnectivity();
  }

  void _updateConnectionStatus(bool isOnline) {
    _lastCheck = DateTime.now();
    if (_isOnline != isOnline) {
      _isOnline = isOnline;
      AppLogger.words(
        'Connectivity status updated: $_isOnline',
        level: 'debug',
      );
      notifyListeners();
    }
  }
}
