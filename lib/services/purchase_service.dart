import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'revenue_cat_verifier.dart';
import 'offline_storage_service.dart';
import 'access_manager.dart';
import '../models/purchase_update.dart';

class PurchaseService {
  static const String _premiumProductId = 'premium_access';
  final _iap = iap.InAppPurchase.instance;
  late final RevenueCatVerifier _revenueCatVerifier;
  late StreamSubscription<List<iap.PurchaseDetails>> _subscription;
  List<iap.ProductDetails> products = [];
  String? lastError;
  bool _verificationEnabled = true;
  // Stream controllers for purchase updates
  final _purchaseController = StreamController<PurchaseUpdate>.broadcast();
  Stream<PurchaseUpdate> get purchaseUpdates => _purchaseController.stream;

  PurchaseService() {
    _revenueCatVerifier = RevenueCatVerifier();
  }

  Future<void> initialize() async {
    try {
      print('Checking if IAP is available...');
      print(
        'Platform: ${Platform.isAndroid
            ? 'Android'
            : Platform.isIOS
            ? 'iOS'
            : 'other'}',
      );
      final available = await _iap.isAvailable();
      print('IAP available: $available');
      if (Platform.isAndroid) {
        print('Checking Google Play Billing availability...');
        // Force a connection attempt to Google Play
        try {
          await Future.any([
            _iap.isAvailable(),
            Future.delayed(const Duration(seconds: 10), () {
              throw TimeoutException(
                'Google Play Billing connection timed out',
                const Duration(seconds: 10),
              );
            }),
          ]);
          print('Google Play Billing connection successful');
        } catch (e) {
          print('Google Play Billing connection error: $e');
          // Continue with initialization even if this check fails
          // as the main isAvailable() call might still work
        }
      }
      if (!available) {
        lastError = 'In-app purchases are not available on this device';
        return;
      }

      // Always set up IAP listener first so purchases work even if RevenueCat fails
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription.cancel(),
        onError: (error) {
          print('Purchase stream error: $error');
          lastError = 'Error in purchase stream: $error';
          _purchaseController.add(
            PurchaseUpdate(
              status: PurchaseUpdateStatus.error,
              message: 'Purchase stream error: $error',
            ),
          );
        },
      );
      print('IAP purchase stream listener set up');

      // Load available products for the store UI
      await loadPurchases();
      lastError = null;

      // Initialize RevenueCat verifier for all platforms
      try {
        await dotenv.load();
        final revenueCatApiKey = dotenv.env['REVENUECAT_API_KEY'];
        if (revenueCatApiKey != null && revenueCatApiKey.isNotEmpty) {
          await _revenueCatVerifier.initialize(revenueCatApiKey);
          _verificationEnabled = true;
        } else {
          print('RevenueCat API key not found in .env file');
          _verificationEnabled = false;
        }
      } catch (e) {
        // Keep purchases working even if RevenueCat init fails
        print('RevenueCat initialization failed: $e');
        _verificationEnabled = false;
      }
    } catch (e) {
      print('Error initializing IAP: $e');
      lastError = 'Failed to initialize in-app purchases: $e';
    }
  }

  Future<void> loadPurchases() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        print('IAP not available on this device');
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message: 'In-app purchases are not available on this device',
          ),
        );
        return;
      }

      print('Querying product details for ID: $_premiumProductId');
      const ids = <String>{_premiumProductId};
      print('Product IDs to query: $ids');
      print('Awaiting product details response...');

      late iap.ProductDetailsResponse response;
      try {
        response = await Future.any([
          _iap.queryProductDetails(ids),
          Future.delayed(const Duration(seconds: 15), () {
            throw TimeoutException(
              'Product details query timed out after 15 seconds. This might be due to Google Play Billing connectivity issues.',
              const Duration(seconds: 15),
            );
          }),
        ]);
      } on TimeoutException catch (e) {
        print('Timeout occurred: ${e.message}');
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message:
                'Connection to store timed out. Please check your internet connection and try again.',
            error: e,
          ),
        );
        return;
      }
      print('Product details response received:');
      print('- Product count: ${response.productDetails.length}');
      print('- Not found products: ${response.notFoundIDs}');
      print('- Error: ${response.error?.message ?? "none"}');

      if (response.notFoundIDs.isNotEmpty) {
        print('Products not found in store: ${response.notFoundIDs}');
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message:
                'Product not found in store. Please check store configuration.',
          ),
        );
        return;
      }

      if (response.productDetails.isEmpty) {
        print('No products found in store response');
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message: 'No products available for purchase',
          ),
        );
        return;
      }

      products = response.productDetails;
      print(
        'Successfully loaded ${products.length} products:\n'
        'IDs: ${products.map((p) => p.id).toList()}\n'
        'Titles: ${products.map((p) => p.title).toList()}\n'
        'Descriptions: ${products.map((p) => p.description).toList()}\n'
        'Prices: ${products.map((p) => p.price).toList()}',
      );
    } catch (e) {
      print('Error loading purchases: $e');
      _purchaseController.add(
        PurchaseUpdate(
          status: PurchaseUpdateStatus.error,
          message: 'Failed to load products: $e',
          error: e,
        ),
      );
    }
  }

  Future<void> buyPremiumAccess() async {
    try {
      // Inform UI that we're launching the billing flow
      _purchaseController.add(
        PurchaseUpdate(
          status: PurchaseUpdateStatus.pending,
          message: 'Opening Google Play billing...',
        ),
      );

      if (products.isEmpty) {
        await loadPurchases();
      }

      final premiumProduct = products.firstWhere(
        (product) => product.id == _premiumProductId,
        orElse: () => throw Exception('Premium product not found'),
      );
      print('Launching billing flow for product: ${premiumProduct.id}');

      final purchaseParam = iap.PurchaseParam(productDetails: premiumProduct);

      // Await to catch immediate launch errors and surface them to UI
      print('Attempting to launch billing flow...');
      final launchResult = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      print('Billing flow launch result: $launchResult');
    } catch (e) {
      lastError = 'Failed to start purchase: $e';
      _purchaseController.add(
        PurchaseUpdate(
          status: PurchaseUpdateStatus.error,
          message: 'Failed to start purchase: $e',
          error: e,
        ),
      );
      rethrow;
    }
  }

  Future<void> restorePurchases() async {
    try {
      _purchaseController.add(
        PurchaseUpdate(
          status: PurchaseUpdateStatus.pending,
          message: 'Restoring purchases...',
        ),
      );

      await _iap.restorePurchases();
    } catch (e) {
      print('Error restoring purchases: $e');
      _purchaseController.add(
        PurchaseUpdate(
          status: PurchaseUpdateStatus.error,
          message: 'Failed to restore purchases: $e',
          error: e,
        ),
      );
      rethrow;
    }
  }

  Future<void> _onPurchaseUpdate(
    List<iap.PurchaseDetails> purchaseDetailsList,
  ) async {
    for (var purchaseDetails in purchaseDetailsList) {
      try {
        switch (purchaseDetails.status) {
          case iap.PurchaseStatus.pending:
            _purchaseController.add(
              PurchaseUpdate(
                status: PurchaseUpdateStatus.pending,
                message: 'Processing purchase...',
              ),
            );
            break;
          case iap.PurchaseStatus.error:
            lastError = 'Error purchasing product: ${purchaseDetails.error}';
            _purchaseController.add(
              PurchaseUpdate(
                status: PurchaseUpdateStatus.error,
                message: 'Purchase failed: ${purchaseDetails.error}',
                error: purchaseDetails.error,
              ),
            );
            break;
          case iap.PurchaseStatus.purchased:
          case iap.PurchaseStatus.restored:
            _purchaseController.add(
              PurchaseUpdate(
                status: PurchaseUpdateStatus.pending,
                message: 'Verifying purchase...',
              ),
            );

            try {
              final isValid = await _verifyPurchase(purchaseDetails);
              if (isValid) {
                await _enablePremiumAccess();
                _purchaseController.add(
                  PurchaseUpdate(
                    status: PurchaseUpdateStatus.purchased,
                    message:
                        'Purchase successful! You can now download the dictionary.',
                  ),
                );
              } else {
                throw Exception('Purchase verification failed');
              }
            } catch (e) {
              lastError = 'Purchase verification failed: $e';
              _purchaseController.add(
                PurchaseUpdate(
                  status: PurchaseUpdateStatus.error,
                  message: 'Purchase verification failed: $e',
                  error: e,
                ),
              );
              continue;
            }
            break;
          case iap.PurchaseStatus.canceled:
            _purchaseController.add(
              PurchaseUpdate(
                status: PurchaseUpdateStatus.error,
                message: 'Purchase cancelled',
              ),
            );
            break;
        }

        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
        }
      } catch (e) {
        print('Error processing purchase update: $e');
        lastError = 'Error processing purchase: $e';
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message: 'Error processing purchase: $e',
            error: e,
          ),
        );
      }
    }
  }

  Future<bool> _verifyPurchase(iap.PurchaseDetails purchase) async {
    try {
      // First verify with native store
      if (purchase.status != iap.PurchaseStatus.purchased) {
        print('Purchase not completed: ${purchase.status}');
        return false;
      }

      // If RevenueCat verification is disabled, trust the store purchase
      if (!_verificationEnabled) {
        print('RevenueCat verification disabled, trusting store purchase');
        return true;
      }

      // Verify with RevenueCat
      final verificationData = purchase.verificationData.serverVerificationData;
      if (verificationData.isEmpty) {
        print('No verification data available from store');
        return false;
      }

      final isVerified = await _revenueCatVerifier.verifyPurchase(
        purchase.productID,
        verificationData,
      );

      if (!isVerified) {
        print(
          'RevenueCat verification failed for purchase ${purchase.productID}',
        );
        return false;
      }

      print('Purchase verified with native store');
      return true;
    } catch (e) {
      print('Error during purchase verification: $e');
      return false;
    }
  }

  Future<void> _enablePremiumAccess() async {
    // Update local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPremium', true);

    // Update Supabase user profile
    await _updateUserProfile();
  }

  Future<void> _updateUserProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase
            .from('user_profiles')
            .update({
              'has_offline_dictionary_access': true,
              'subscription_valid_until': null, // No expiration for now
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', user.id);
        print('User profile updated with premium access in Supabase');

        // Force clear local cache and refresh profile
        await _clearAndRefreshProfile(user.id);
      }
    } catch (e) {
      print('Error updating user profile: $e');
      // Don't throw here - we want the purchase to be marked as successful
      // even if profile update fails, as user can retry later
    }
  }

  Future<void> _clearAndRefreshProfile(String userId) async {
    try {
      // Clear the local SQLite cache
      final offlineStorage = OfflineStorageService();
      await offlineStorage.clearUserProfiles();
      print('SQLite user profiles cache cleared');

      // Clear SharedPreferences cache
      final accessManager = AccessManager();
      await accessManager.clearPremiumAccessCache();
      print('SharedPreferences premium cache cleared');

      // Force a fresh fetch from Supabase to verify the update worked
      final supabase = Supabase.instance.client;
      final freshProfile = await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .single();
      print('Fresh profile verification from Supabase: $freshProfile');

      print(
        'Local profile cache cleared, fresh data will be fetched on next access',
      );
    } catch (e) {
      print('Error clearing profile cache: $e');
    }
  }

  void dispose() {
    _subscription.cancel();
    _purchaseController.close();
  }
}
