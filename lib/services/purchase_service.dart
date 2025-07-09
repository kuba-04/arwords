import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'download_service.dart';

// class BackendService {
//   final _supabase = Supabase.instance.client;

//   Future<PurchaseVerificationResponse> verifyPurchase(
//     String verificationData,
//   ) async {
//     final response = await _supabase
//         .from('purchase_verifications')
//         .insert({'verification_data': verificationData})
//         .select()
//         .single();
//     return PurchaseVerificationResponse(isValid: response['is_valid'] ?? false);
//   }
// }

class PurchaseVerificationResponse {
  final bool isValid;
  PurchaseVerificationResponse({required this.isValid});
}

class PurchaseService {
  final _iap = InAppPurchase.instance;
  final _downloadService = ContentDownloadService();
  // final _backendService = BackendService();

  Future<void> initialize() async {
    final available = await _iap.isAvailable();
    if (!available) {
      throw PlatformException(code: 'IAP_NOT_AVAILABLE');
    }

    // Listen to purchase updates
    _iap.purchaseStream.listen(_handlePurchaseUpdate);
  }

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased) {
        // Verify purchase with backend
        await _verifyPurchase(purchase);
      }
    }
  }

  Future<void> _verifyPurchase(PurchaseDetails purchase) async {
    try {
      final response = await verifyPurchase(
        purchase.verificationData.serverVerificationData,
      );

      if (response.isValid) {
        await _enablePremiumAccess();
        await _initiateContentDownload();
      }
    } catch (e) {
      // Handle verification errors
    }
  }

  Future<void> _enablePremiumAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPremium', true);
  }

  Future<void> _initiateContentDownload() async {
    await _downloadService.downloadDictionary();
  }
}

Future<PurchaseVerificationResponse> verifyPurchase(
  String verificationData,
) async {
  final response = await Supabase.instance.client
      .from('purchase_verifications')
      .insert({'verification_data': verificationData})
      .select()
      .single();
  return PurchaseVerificationResponse(isValid: response['is_valid'] ?? false);
}
