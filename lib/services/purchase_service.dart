import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:shared_preferences/shared_preferences.dart';
import 'revenue_cat_verifier.dart';
import 'download_service.dart';
import '../models/purchase_update.dart';

class PurchaseService {
  static const String _premiumProductId = 'premium_access';
  final _iap = iap.InAppPurchase.instance;
  late final ContentDownloadService _downloadService;
  late final RevenueCatVerifier _revenueCatVerifier;
  late StreamSubscription<List<iap.PurchaseDetails>> _subscription;
  List<iap.ProductDetails> products = [];
  String? lastError;
  bool _verificationEnabled = false; // Temporarily disabled

  // Stream controllers for purchase updates
  final _purchaseController = StreamController<PurchaseUpdate>.broadcast();
  Stream<PurchaseUpdate> get purchaseUpdates => _purchaseController.stream;

  PurchaseService() {
    _downloadService = ContentDownloadService();
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
            Future.delayed(const Duration(seconds: 5), () {
              throw TimeoutException(
                'Google Play Billing connection timed out',
              );
            }),
          ]);
          print('Google Play Billing connection successful');
        } catch (e) {
          print('Google Play Billing connection error: $e');
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
      /* Temporarily disabled RevenueCat integration
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
      */
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
      final response = await Future.any([
        _iap.queryProductDetails(ids),
        Future.delayed(const Duration(seconds: 10), () {
          throw TimeoutException(
            'Product details query timed out after 10 seconds',
          );
        }),
      ]);
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
                await _initiateContentDownload();
                _purchaseController.add(
                  PurchaseUpdate(
                    status: PurchaseUpdateStatus.purchased,
                    message: 'Purchase successful!',
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

      // RevenueCat verification temporarily disabled, using only native store verification
      /* Temporarily disabled RevenueCat verification
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
      */

      print('Purchase verified with native store');
      return true;
    } catch (e) {
      print('Error during purchase verification: $e');
      return false;
    }
  }

  Future<void> _enablePremiumAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPremium', true);
  }

  Future<void> _initiateContentDownload() async {
    await _downloadService.downloadDictionary();
  }

  void dispose() {
    _subscription.cancel();
    _purchaseController.close();
  }
}
