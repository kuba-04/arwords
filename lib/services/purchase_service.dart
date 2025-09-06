import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'revenue_cat_verifier.dart';
import 'offline_storage_service.dart';
import 'access_manager.dart';
import 'logger_service.dart';
import '../models/purchase_update.dart';

/// iOS-specific payment queue delegate for handling pending transactions
class ExamplePaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
    SKPaymentTransactionWrapper transaction,
    SKStorefrontWrapper storefront,
  ) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return false;
  }
}

/// Cross-platform purchase service supporting both Android (Google Play Store) and iOS (Apple App Store)
class PurchaseService {
  static const String _premiumProductId = 'premium_access';
  // Feature flag for iOS purchases
  static const bool iosPaymentsEnabled =
      true; // Set to true when ready for iOS payments
  final _iap = iap.InAppPurchase.instance;
  late final RevenueCatVerifier _revenueCatVerifier;
  late StreamSubscription<List<iap.PurchaseDetails>> _subscription;
  List<iap.ProductDetails> products = [];
  String? lastError;
  bool _verificationEnabled = true;
  // Stream controllers for purchase updates
  final _purchaseController = StreamController<PurchaseUpdate>.broadcast();
  Stream<PurchaseUpdate> get purchaseUpdates => _purchaseController.stream;

  /// Get the current platform's store name
  String get _storeName =>
      Platform.isAndroid ? 'Google Play Store' : 'Apple App Store';

  PurchaseService() {
    _revenueCatVerifier = RevenueCatVerifier();
  }

  Future<void> initialize() async {
    try {
      final available = await _iap.isAvailable();
      AppLogger.purchase('IAP available: $available');

      // Platform-specific initialization
      if (Platform.isAndroid) {
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
          AppLogger.purchase('Google Play Billing connection successful');
        } catch (e) {
          AppLogger.purchase(
            'Google Play Billing connection error',
            level: 'warning',
            error: e,
          );
          // Continue with initialization even if this check fails
          // as the main isAvailable() call might still work
        }
      } else if (Platform.isIOS) {
        // iOS-specific initialization
        if (iosPaymentsEnabled) {
          try {
            // Enable pending purchases for iOS
            final InAppPurchaseStoreKitPlatformAddition
            iosPlatformAddition = _iap
                .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
            await iosPlatformAddition.setDelegate(
              ExamplePaymentQueueDelegate(),
            );
            AppLogger.purchase('$_storeName connection successful');
          } catch (e) {
            AppLogger.purchase(
              '$_storeName connection error',
              level: 'warning',
              error: e,
            );
            // Continue with initialization even if this check fails
          }
        } else {
          AppLogger.purchase(
            'iOS payments are disabled in this version',
            level: 'info',
          );
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
          AppLogger.purchase(
            'Purchase stream error',
            level: 'error',
            error: error,
          );
          lastError = 'Error in purchase stream: $error';
          _purchaseController.add(
            PurchaseUpdate(
              status: PurchaseUpdateStatus.error,
              message: 'Purchase stream error: $error',
            ),
          );
        },
      );
      AppLogger.purchase('IAP purchase stream listener set up');

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
          _verificationEnabled = false;
        }
      } catch (e) {
        // Keep purchases working even if RevenueCat init fails
        AppLogger.purchase(
          'RevenueCat initialization failed',
          level: 'warning',
          error: e,
        );
        _verificationEnabled = false;
      }
    } catch (e) {
      AppLogger.purchase('Error initializing IAP', level: 'error', error: e);
      lastError = 'Failed to initialize in-app purchases: $e';
    }
  }

  Future<void> loadPurchases() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        AppLogger.purchase(
          'IAP not available on this device',
          level: 'warning',
        );
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message: 'In-app purchases are not available on this device',
          ),
        );
        return;
      }

      const ids = <String>{_premiumProductId};
      late iap.ProductDetailsResponse response;
      try {
        response = await Future.any([
          _iap.queryProductDetails(ids),
          Future.delayed(const Duration(seconds: 15), () {
            throw TimeoutException(
              'Product details query timed out after 15 seconds. This might be due to $_storeName connectivity issues.',
              const Duration(seconds: 15),
            );
          }),
        ]);
      } on TimeoutException catch (e) {
        AppLogger.purchase('Timeout occurred', level: 'error', error: e);
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

      if (response.notFoundIDs.isNotEmpty) {
        AppLogger.purchase(
          'Products not found in store: ${response.notFoundIDs}',
          level: 'error',
        );
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
        AppLogger.purchase(
          'No products found in store response',
          level: 'error',
        );
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message: 'No products available for purchase',
          ),
        );
        return;
      }

      products = response.productDetails;
      final productSummary =
          'Successfully loaded ${products.length} products:\n'
          'IDs: ${products.map((p) => p.id).toList()}\n'
          'Titles: ${products.map((p) => p.title).toList()}\n'
          'Descriptions: ${products.map((p) => p.description).toList()}\n'
          'Prices: ${products.map((p) => p.price).toList()}';
      AppLogger.purchase(productSummary);
    } catch (e) {
      AppLogger.purchase('Error loading purchases', level: 'error', error: e);
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
      // Check if we're on iOS and payments are disabled
      if (Platform.isIOS && !iosPaymentsEnabled) {
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message:
                'In-app purchases are not available in this version for iOS devices. This feature will be enabled in a future updates.',
          ),
        );
        return;
      }
      // Inform UI that we're launching the billing flow
      _purchaseController.add(
        PurchaseUpdate(
          status: PurchaseUpdateStatus.pending,
          message: 'Opening $_storeName billing...',
        ),
      );

      if (products.isEmpty) {
        await loadPurchases();
      }

      final premiumProduct = products.firstWhere(
        (product) => product.id == _premiumProductId,
        orElse: () => throw Exception(
          'Premium product not found. Available products: ${products.map((p) => p.id).toList()}',
        ),
      );

      final purchaseParam = iap.PurchaseParam(productDetails: premiumProduct);

      // Await to catch immediate launch errors and surface them to UI
      await _iap.buyConsumable(purchaseParam: purchaseParam);
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
            // For restored purchases of consumables, consume them to allow re-purchasing
            if (purchaseDetails.status == iap.PurchaseStatus.restored &&
                purchaseDetails.productID == _premiumProductId) {
              AppLogger.purchase(
                'Found restored consumable purchase, consuming it to allow re-purchasing...',
              );
              try {
                if (Platform.isAndroid) {
                  // Android-specific consumption
                  final InAppPurchaseAndroidPlatformAddition androidAddition =
                      _iap
                          .getPlatformAddition<
                            InAppPurchaseAndroidPlatformAddition
                          >();
                  await androidAddition.consumePurchase(purchaseDetails);
                  AppLogger.purchase(
                    'Successfully consumed restored purchase on Android',
                  );
                } else if (Platform.isIOS) {
                  // iOS automatically handles consumption for consumable products
                  // We just need to complete the purchase
                  AppLogger.purchase(
                    'iOS automatically handles consumable consumption',
                  );
                }

                // Complete the purchase and skip further processing since this is just cleanup
                if (purchaseDetails.pendingCompletePurchase) {
                  await _iap.completePurchase(purchaseDetails);
                }
                continue; // Skip the normal purchase processing for restored consumables
              } catch (e) {
                AppLogger.purchase(
                  'Error consuming restored purchase: $e',
                  level: 'warning',
                  error: e,
                );
              }
            }

            _purchaseController.add(
              PurchaseUpdate(
                status: PurchaseUpdateStatus.pending,
                message: 'Verifying purchase...',
              ),
            );

            try {
              final isValid = await _verifyPurchase(purchaseDetails);
              if (isValid) {
                await _enablePremiumAccessForCurrentUser(purchaseDetails);
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
        AppLogger.purchase(
          'Error processing purchase update',
          level: 'error',
          error: e,
        );
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
        AppLogger.purchase(
          'Purchase not completed: ${purchase.status}',
          level: 'warning',
        );
        return false;
      }

      // If RevenueCat verification is disabled, trust the store purchase
      if (!_verificationEnabled) {
        AppLogger.purchase(
          'RevenueCat verification disabled, trusting store purchase',
          level: 'info',
        );
        return true;
      }

      // Verify with RevenueCat
      final verificationData = purchase.verificationData.serverVerificationData;
      if (verificationData.isEmpty) {
        AppLogger.purchase(
          'No verification data available from store',
          level: 'warning',
        );
        return false;
      }

      final isVerified = await _revenueCatVerifier.verifyPurchase(
        purchase.productID,
        verificationData,
      );

      if (!isVerified) {
        AppLogger.purchase(
          'RevenueCat verification failed for purchase ${purchase.productID}',
          level: 'error',
        );
        return false;
      }

      AppLogger.purchase('Purchase verified with native store');
      return true;
    } catch (e) {
      AppLogger.purchase(
        'Error during purchase verification',
        level: 'error',
        error: e,
      );
      return false;
    }
  }

  Future<void> _enablePremiumAccessForCurrentUser(
    iap.PurchaseDetails purchaseDetails,
  ) async {
    // First consume the purchase (for consumable products)
    if (purchaseDetails.productID == _premiumProductId) {
      AppLogger.purchase('🔄 Consuming purchase to allow future purchases...');

      if (Platform.isAndroid) {
        // For Android, explicitly consume the purchase to allow re-purchasing
        try {
          final InAppPurchaseAndroidPlatformAddition androidAddition = _iap
              .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
          await androidAddition.consumePurchase(purchaseDetails);
          AppLogger.purchase('✅ Purchase consumed successfully on Android');
        } catch (e) {
          AppLogger.purchase(
            '⚠️ Error consuming purchase on Android: $e',
            level: 'warning',
            error: e,
          );
          // Continue anyway - the purchase was successful, just consumption failed
        }
      } else if (Platform.isIOS) {
        // iOS automatically handles consumption for consumable products
        AppLogger.purchase(
          '✅ iOS automatically handles consumable consumption',
        );
      }
    }

    // Update local SharedPreferences for current user
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPremium', true);

    // Update Supabase user profile (user-specific)
    await _updateUserProfile();

    AppLogger.purchase('✅ Premium access granted to current user');
  }

  Future<void> _updateUserProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        // First, try to update the existing profile
        final result = await supabase
            .from('user_profiles')
            .update({
              'has_offline_dictionary_access': true,
              'subscription_valid_until': null, // No expiration for now
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', user.id)
            .select();

        // If no rows were updated, the profile doesn't exist - create it
        if (result.isEmpty) {
          AppLogger.purchase('User profile not found, creating new profile...');
          final now = DateTime.now().toIso8601String();
          await supabase.from('user_profiles').insert({
            'user_id': user.id,
            'has_offline_dictionary_access': true,
            'subscription_valid_until': null,
            'created_at': now,
            'updated_at': now,
          });
        } else {
          AppLogger.purchase(
            'User profile updated with premium access in Supabase',
          );
        }

        // Force clear local cache and refresh profile
        await _clearAndRefreshProfile(user.id);
      }
    } catch (e) {
      AppLogger.purchase(
        'Error updating user profile',
        level: 'error',
        error: e,
      );
      AppLogger.purchase('Error type: ${e.runtimeType}', level: 'debug');
      if (e is Exception) {
        AppLogger.purchase(
          'Exception details: ${e.toString()}',
          level: 'debug',
        );
      }

      // Try to create the profile if the error suggests it doesn't exist
      if (e.toString().contains('not found') ||
          e.toString().contains('No rows') ||
          e.toString().contains('0 rows') ||
          e.toString().contains('no rows affected')) {
        try {
          final supabase = Supabase.instance.client;
          final user = supabase.auth.currentUser;
          if (user != null) {
            AppLogger.purchase(
              'Attempting to create user profile after update failed...',
            );
            final now = DateTime.now().toIso8601String();
            await supabase.from('user_profiles').insert({
              'user_id': user.id,
              'has_offline_dictionary_access': true,
              'subscription_valid_until': null,
              'created_at': now,
              'updated_at': now,
            });
            AppLogger.purchase(
              '✅ User profile created successfully after failed update',
            );
            await _clearAndRefreshProfile(user.id);
          }
        } catch (createError) {
          AppLogger.purchase(
            '❌ Error creating user profile after failed update',
            level: 'error',
            error: createError,
          );
          AppLogger.purchase(
            'Create error type: ${createError.runtimeType}',
            level: 'debug',
          );
        }
      } else {
        AppLogger.purchase(
          '❌ Non-recoverable error, not attempting to create profile',
          level: 'error',
        );
      }

      // Don't throw here - we want the purchase to be marked as successful
      // even if profile update fails, as user can retry later
    }
  }

  /// Restore purchases for both Android and iOS platforms
  Future<void> restorePurchases() async {
    try {
      // Check if we're on iOS and payments are disabled
      if (Platform.isIOS && !iosPaymentsEnabled) {
        _purchaseController.add(
          PurchaseUpdate(
            status: PurchaseUpdateStatus.error,
            message:
                'Restore purchases is not available in this version for iOS devices. This feature will be enabled in a future update.',
          ),
        );
        return;
      }

      AppLogger.purchase('Restoring purchases from $_storeName...');

      _purchaseController.add(
        PurchaseUpdate(
          status: PurchaseUpdateStatus.pending,
          message: 'Restoring purchases from $_storeName...',
        ),
      );

      await _iap.restorePurchases();

      // Give a small delay to allow the purchase stream to process
      await Future.delayed(const Duration(milliseconds: 1000));

      AppLogger.purchase('Purchase restoration completed');
    } catch (e) {
      AppLogger.purchase(
        'Error restoring purchases: $e',
        level: 'error',
        error: e,
      );
      _purchaseController.add(
        PurchaseUpdate(
          status: PurchaseUpdateStatus.error,
          message: 'Failed to restore purchases: $e',
          error: e,
        ),
      );
    }
  }

  Future<void> _clearAndRefreshProfile(String userId) async {
    try {
      // Clear the local SQLite cache
      final offlineStorage = OfflineStorageService();
      await offlineStorage.clearUserProfiles();

      // Clear SharedPreferences cache
      final accessManager = AccessManager();
      await accessManager.clearPremiumAccessCache();

      // Force a fresh fetch from Supabase to verify the update worked
      final supabase = Supabase.instance.client;
      await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .single();
    } catch (e) {
      AppLogger.purchase(
        'Error clearing profile cache',
        level: 'error',
        error: e,
      );
    }
  }

  void dispose() {
    _subscription.cancel();
    _purchaseController.close();
  }
}
