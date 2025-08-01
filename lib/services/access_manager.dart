import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'offline_storage_service.dart';

class AccessManager {
  static final AccessManager _instance = AccessManager._internal();
  static const String _premiumAccessKey = 'has_offline_dictionary_access';
  OfflineStorageService? _offlineStorage;

  factory AccessManager() {
    return _instance;
  }

  AccessManager._internal();

  Future<void> cachePremiumStatus(bool hasPremiumAccess) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumAccessKey, hasPremiumAccess);
  }

  Future<bool> verifyPremiumAccess() async {
    try {
      // Check if user is logged in first
      final user = AuthService.supabase.auth.currentUser;
      if (user == null) {
        return false;
      }

      // First check SQLite database (most authoritative local source)
      _offlineStorage ??= OfflineStorageService();
      final sqliteProfile = await _offlineStorage!.getUserProfile(user.id);
      if (sqliteProfile != null) {
        final sqliteStatus =
            sqliteProfile['has_offline_dictionary_access'] ?? false;
        // Update SharedPreferences to match SQLite
        await cachePremiumStatus(sqliteStatus);
        return sqliteStatus;
      }

      // If no SQLite data, check SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final cachedStatus = prefs.getBool(_premiumAccessKey);
      if (cachedStatus != null) {
        return cachedStatus;
      }

      // If not in local storage, try to get from server
      try {
        final profile = await AuthService.getUserProfile();
        final hasPremiumAccess = profile?[_premiumAccessKey] ?? false;

        // Cache the result for offline use in both places
        await cachePremiumStatus(hasPremiumAccess);
        if (profile != null) {
          _offlineStorage ??= OfflineStorageService();
          await _offlineStorage!.saveUserProfile(profile);
        }

        return hasPremiumAccess;
      } catch (e) {
        // If server check fails and we have no cached value, assume no premium access
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<void> clearPremiumAccessCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_premiumAccessKey);
  }

  // TODO: Implement this
  Future<bool> _validateStoredReceipt() async {
    final prefs = await SharedPreferences.getInstance();
    final receipt = prefs.getString('purchaseReceipt');
    return receipt != null && receipt.isNotEmpty;
  }
}
