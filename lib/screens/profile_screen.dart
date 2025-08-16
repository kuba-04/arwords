import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show User, Session, AuthChangeEvent, AuthException;
import '../models/purchase_update.dart';
import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../services/error_handler.dart' as app_errors;
import '../services/purchase_service.dart';
import '../services/logger_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isAuthenticated = false;
  bool _isLoginView = true;
  bool _loading = false;
  bool _isDownloading = false;
  bool _isLoadingProfile = true;
  bool _isPurchasing = false;
  String? _error;
  User? _user;
  Map<String, dynamic>? _userProfile;
  late final ContentDownloadService _downloadService;
  late final PurchaseService _purchaseService;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _downloadService = ContentDownloadService();
    _purchaseService = PurchaseService();
    _checkUser();
    _initializePurchases();

    // Listen to auth state changes
    AuthService.supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      if (mounted) {
        if (session != null &&
            (event == AuthChangeEvent.signedIn ||
                event == AuthChangeEvent.tokenRefreshed)) {
          _checkUser();
        } else if (event == AuthChangeEvent.signedOut) {
          setState(() {
            _isAuthenticated = false;
            _user = null;
            _userProfile = null;
          });
        }
      }
    });
  }

  Future<void> _initializePurchases() async {
    try {
      await _purchaseService.initialize();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize in-app purchases: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _purchaseService.dispose();
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkUser() async {
    if (!mounted) return;

    setState(() {
      _isLoadingProfile = true;
      _error = null;
    });

    try {
      final session = await AuthService.supabase.auth.currentSession;
      final currentUser = AuthService.supabase.auth.currentUser;

      AppLogger.profile('Session exists: ${session != null}', level: 'debug');
      AppLogger.profile(
        'Current user exists: ${currentUser != null}',
        level: 'debug',
      );

      if (session != null && currentUser != null) {
        final profile = await AuthService.getUserProfile();
        AppLogger.profile(
          'Profile data retrieved in _checkUser',
          level: 'debug',
        );
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
            _user = currentUser;
            _userProfile = profile;
            _error = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _user = null;
            _userProfile = null;
          });
        }
      }
    } catch (error, stackTrace) {
      AppLogger.profile(
        'Error checking auth status',
        level: 'error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _user = null;
          _userProfile = null;
          _error = 'Error loading profile: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!mounted) return;

    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final response = await AuthService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (response.user == null) {
        throw Exception('No user returned from login');
      }

      final profile = await AuthService.getUserProfile();

      if (!mounted) return;

      setState(() {
        _isAuthenticated = true;
        _user = response.user;
        _userProfile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      String errorMessage;
      if (error is AuthException) {
        // Handle Supabase auth errors with user-friendly messages
        switch (error.message) {
          case 'Invalid login credentials':
            errorMessage = 'Incorrect email or password. Please try again.';
            break;
          case 'Email not confirmed':
            errorMessage =
                'Please verify your email address before logging in.';
            break;
          default:
            errorMessage =
                'Login failed. Please check your credentials and try again.';
        }
      } else {
        errorMessage = 'An unexpected error occurred. Please try again later.';
      }

      setState(() {
        _error = errorMessage;
        _loading = false;
      });
    }
  }

  Future<void> _handleRegister() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final response = await AuthService.register(
        email: _emailController.text,
        password: _passwordController.text,
      );

      final profile = await AuthService.getUserProfile();
      setState(() {
        _isAuthenticated = true;
        _user = response.user;
        _userProfile = profile;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    try {
      setState(() {
        _loading = true;
      });
      await AuthService.logout();
      setState(() {
        _isAuthenticated = false;
        _user = null;
        _userProfile = null;
        _emailController.clear();
        _passwordController.clear();
      });
    } catch (error) {
      setState(() {
        _error = 'Failed to logout';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _handleDeleteAccount() async {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'Are you sure you want to delete your account? This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  await AuthService.deleteAccount();
                  setState(() {
                    _isAuthenticated = false;
                    _user = null;
                    _userProfile = null;
                    _emailController.clear();
                    _passwordController.clear();
                  });
                } catch (error) {
                  setState(() {
                    _error = error.toString();
                  });
                } finally {
                  setState(() {
                    _loading = false;
                  });
                }
              },
            ),
          ],
        );
      },
    );
  }

  StreamSubscription<PurchaseUpdate>? _purchaseSubscription;

  Future<void> _handlePurchase() async {
    try {
      setState(() {
        _isPurchasing = true;
        _error = null;
      });

      // Cancel any previous subscription to avoid duplicate listeners
      try {
        await _purchaseSubscription?.cancel();
      } catch (_) {}

      bool completed = false;
      _purchaseSubscription = _purchaseService.purchaseUpdates.listen(
        (update) {
          switch (update.status) {
            case PurchaseUpdateStatus.pending:
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(update.message),
                  duration: const Duration(seconds: 2),
                ),
              );
              break;
            case PurchaseUpdateStatus.purchased:
              completed = true;
              setState(() {
                _isPurchasing = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(update.message),
                  backgroundColor: Colors.green,
                ),
              );
              // Refresh user profile to show new purchase status
              AppLogger.profile(
                'Purchase successful, refreshing user profile...',
              );
              // Add a small delay to ensure Supabase update propagates
              Future.delayed(const Duration(milliseconds: 1000), () {
                if (mounted) {
                  AppLogger.profile(
                    'Delayed refresh executing...',
                    level: 'debug',
                  );
                  _checkUser();
                }
              });
              break;
            case PurchaseUpdateStatus.error:
              completed = true;
              setState(() {
                _isPurchasing = false;
                _error = update.message;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(update.message),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'Retry',
                    textColor: Colors.white,
                    onPressed: _handlePurchase,
                  ),
                ),
              );
              break;
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isPurchasing = false;
            _error = 'Purchase error: $error';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Purchase error: $error'),
              backgroundColor: Colors.red,
            ),
          );
        },
      );

      // Safety timeout in case no events are received
      Future.delayed(const Duration(seconds: 30), () {
        if (!mounted || completed) return;
        setState(() {
          _isPurchasing = false;
          _error = 'Purchase timed out. Please try again.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase timed out. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      });

      await _purchaseService.buyPremiumAccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPurchasing = false;
        _error = 'Failed to initiate purchase: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Purchase failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _handlePurchase,
          ),
        ),
      );
    }
  }

  Future<void> _handleDownloadDictionary() async {
    try {
      setState(() {
        _isDownloading = true;
        _error = null;
      });

      await _downloadService.downloadDictionary();

      AppLogger.profile(
        'Dictionary download completed, showing success message',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dictionary downloaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      AppLogger.profile(
        'Dictionary download failed',
        level: 'error',
        error: error,
      );

      String errorMessage = 'Failed to download dictionary';
      if (error is app_errors.NetworkException) {
        errorMessage = 'Network error: Please check your internet connection';
      } else if (error is app_errors.StorageException) {
        errorMessage = 'Storage error: Not enough space on your device';
      }

      if (mounted) {
        setState(() {
          _error = errorMessage;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _handleDownloadDictionary,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Widget _buildAuthForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Welcome to Arabic Words',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading
                  ? null
                  : (_isLoginView ? _handleLogin : _handleRegister),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isLoginView ? 'Log In' : 'Register'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _isLoginView = !_isLoginView;
                      _error = null;
                    });
                  },
            child: Text(
              _isLoginView
                  ? 'Don\'t have an account? Register'
                  : 'Already have an account? Log In',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    final hasPremiumAccess =
        _userProfile?['has_offline_dictionary_access'] == true;

    if (_isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _checkUser, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: _isLoadingProfile
                    ? null
                    : () {
                        AppLogger.profile('Manual refresh triggered');
                        _checkUser();
                      },
                icon: _isLoadingProfile
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Refresh Profile',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Email: ${_user?.email}'),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Premium Access: '),
              if (_userProfile != null) ...[
                Icon(
                  _userProfile!['has_offline_dictionary_access'] == true
                      ? Icons.check_circle
                      : Icons.cancel,
                  color: _userProfile!['has_offline_dictionary_access'] == true
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _userProfile!['has_offline_dictionary_access'] == true
                      ? 'Active'
                      : 'Inactive',
                  style: TextStyle(
                    color:
                        _userProfile!['has_offline_dictionary_access'] == true
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ],
          ),
          if (_userProfile?['subscription_valid_until'] != null) ...[
            const SizedBox(height: 10),
            Text(
              'Subscription Valid Until: ${DateTime.parse(_userProfile!['subscription_valid_until']).toLocal().toString().split('.')[0]}',
              style: TextStyle(
                color:
                    DateTime.parse(
                      _userProfile!['subscription_valid_until'],
                    ).isAfter(DateTime.now())
                    ? Colors.green
                    : Colors.red,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (hasPremiumAccess) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isDownloading ? null : _handleDownloadDictionary,
                icon: _isDownloading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  _isDownloading
                      ? 'Downloading...'
                      : 'Download Dictionary for Offline Use',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Premium Feature',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Get offline access to the entire dictionary! Purchase premium to download words and use them without internet connection.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isPurchasing ? null : _handlePurchase,
                          icon: _isPurchasing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.shopping_cart),
                          label: Text(
                            _isPurchasing
                                ? 'Processing...'
                                : 'Purchase Premium Access',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _handleLogout,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Log Out'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _loading ? null : _handleDeleteAccount,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete Account'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: _isAuthenticated ? _buildProfile() : _buildAuthForm(),
            ),
          ),
        ),
      ),
    );
  }
}
