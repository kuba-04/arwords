import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../services/error_handler.dart' as app_errors;

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
  String? _error;
  User? _user;
  Map<String, dynamic>? _userProfile;
  final _downloadService = ContentDownloadService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkUser() async {
    try {
      final session = AuthService.supabase.auth.currentSession;
      if (session != null) {
        final profile = await AuthService.getUserProfile();
        setState(() {
          _isAuthenticated = true;
          _user = session.user;
          _userProfile = profile;
        });
      }
    } catch (error) {
      debugPrint('Error checking auth status: $error');
    }
  }

  Future<void> _handleLogin() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final response = await AuthService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (response.user == null) {
        throw Exception('No user returned from login');
      }

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
      await AuthService.supabase.auth.signOut();
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

  Future<void> _handleDownloadDictionary() async {
    try {
      setState(() {
        _isDownloading = true;
        _error = null;
      });
      await _downloadService
          .downloadDictionary()
          .then(
            (_) => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Dictionary downloaded successfully!'),
              ),
            ),
          )
          .catchError((error) {
            String errorMessage = 'Failed to download dictionary';
            if (error is app_errors.NetworkException) {
              errorMessage =
                  'Network error: Please check your internet connection';
            } else if (error is app_errors.StorageException) {
              errorMessage = 'Storage error: Not enough space on your device';
            }
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
            throw error; // Re-throw to be caught by the outer catch
          });
    } catch (error) {
      // This catch block will handle any other unexpected errors
      setState(() {
        _isDownloading = false;
      });
    } finally {
      setState(() {
        _isDownloading = false;
      });
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Text('Email: ${_user?.email}'),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Premium Access: '),
              if (_userProfile != null)
                Icon(
                  _userProfile!['has_offline_dictionary_access']
                      ? Icons.check_circle
                      : Icons.cancel,
                  color: _userProfile!['has_offline_dictionary_access']
                      ? Colors.green
                      : Colors.red,
                ),
            ],
          ),
          if (_userProfile?['subscription_valid_until'] != null) ...[
            const SizedBox(height: 10),
            Text(
              'Subscription Valid Until: ${DateTime.parse(_userProfile!['subscription_valid_until']).toLocal().toString().split('.')[0]}',
            ),
          ],
          const SizedBox(height: 20),
          if (_userProfile?['has_offline_dictionary_access'] == true) ...[
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
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _isAuthenticated ? _buildProfile() : _buildAuthForm(),
          ),
        ),
      ),
    );
  }
}
