import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isAuthenticated = false;
  bool _isLoginView = true;
  bool _loading = false;
  String? _error;
  User? _user;

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
        setState(() {
          _isAuthenticated = true;
          _user = session.user;
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

      setState(() {
        _isAuthenticated = true;
        _user = response.user;
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

      setState(() {
        _isAuthenticated = true;
        _user = response.user;
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Your Profile',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Text('Email: ${_user?.email}'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _handleLogout,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Log Out'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[100],
                foregroundColor: Colors.red,
              ),
              onPressed: _loading ? null : _handleDeleteAccount,
              child: _loading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red[600],
                      ),
                    )
                  : const Text('Delete Account'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
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
