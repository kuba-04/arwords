// Temporarily commented out until we fix RevenueCat compatibility
// import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RevenueCatVerifier {
  static const String premiumEntitlementId = 'premium';
  final _supabase = Supabase.instance.client;
  bool _isInitialized = false;

  // Temporarily disabled RevenueCat integration
  Future<void> initialize(String apiKey) async {
    print('RevenueCat verification disabled');
    return;
  }

  Future<void> syncUser() async {
    print('RevenueCat user sync disabled');
    return;
  }

  Future<bool> verifyPurchase(String productId, String verificationData) async {
    print('RevenueCat verification disabled, trusting store purchase');
    return true;
  }

  // Temporarily using simplified profile update
  Future<void> _updateSupabaseProfile(/* CustomerInfo customerInfo */) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser != null) {
        await _supabase
            .from('profiles')
            .update({
              'has_offline_dictionary_access': true,
              'subscription_valid_until': null, // No expiration for now
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', currentUser.id);
      }
    } catch (e) {
      print('Error updating Supabase profile: $e');
    }
  }
}
