import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class AccessManager {
  static final AccessManager _instance = AccessManager._internal();
  static const String _premiumAccessKey = 'has_offline_dictionary_access';

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
      // First try to get from local storage
      final prefs = await SharedPreferences.getInstance();
      final cachedStatus = prefs.getBool(_premiumAccessKey);

      if (cachedStatus != null) {
        return cachedStatus;
      }

      // If not in local storage, try to get from server
      try {
        final profile = await AuthService.getUserProfile();
        final hasPremiumAccess = profile?[_premiumAccessKey] ?? false;

        // Cache the result for offline use
        await cachePremiumStatus(hasPremiumAccess);

        return hasPremiumAccess;
      } catch (e) {
        // If server check fails and we have no cached value, assume no premium access
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  // TODO: Implement this
  Future<bool> _validateStoredReceipt() async {
    final prefs = await SharedPreferences.getInstance();
    final receipt = prefs.getString('purchaseReceipt');
    return receipt != null && receipt.isNotEmpty;
  }
}
