// Temporarily commented out until we fix RevenueCat compatibility
// import 'package:purchases_flutter/purchases_flutter.dart';
import 'logger_service.dart';

class RevenueCatVerifier {
  static const String premiumEntitlementId = 'premium';

  // Temporarily disabled RevenueCat integration
  Future<void> initialize(String apiKey) async {
    AppLogger.revenueCat('RevenueCat verification disabled', level: 'info');
    return;
  }

  Future<void> syncUser() async {
    AppLogger.revenueCat('RevenueCat user sync disabled', level: 'info');
    return;
  }

  Future<bool> verifyPurchase(String productId, String verificationData) async {
    AppLogger.revenueCat(
      'RevenueCat verification disabled, trusting store purchase',
      level: 'warning',
    );
    return true;
  }
}
