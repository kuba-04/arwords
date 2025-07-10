import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/words_screen.dart';
import 'screens/favorite_words_screen.dart';
import 'screens/profile_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Load environment variables
    await dotenv.load();

    // Validate required environment variables
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (supabaseUrl == null || supabaseUrl.isEmpty) {
      throw Exception('SUPABASE_URL environment variable is not set');
    }
    if (supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
      throw Exception('SUPABASE_ANON_KEY environment variable is not set');
    }

    // Initialize Supabase with proper error handling
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        authOptions: FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
        realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 2),
      );

      debugPrint('Supabase initialized successfully');
    } catch (e) {
      debugPrint('Error initializing Supabase: $e');
      rethrow;
    }

    runApp(const MyApp());
  } catch (error, stackTrace) {
    debugPrint('Critical error in main: $error');
    debugPrint('Stack trace: $stackTrace');

    // Run the app with an error message
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Error initializing app',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arabic Words',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _wasLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _wasLoggedIn = Supabase.instance.client.auth.currentUser != null;

    // Listen to auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final isCurrentlyLoggedIn =
          Supabase.instance.client.auth.currentUser != null;

      // Only reset tab selection when user actually logs out (not on other auth events)
      if (event == AuthChangeEvent.signedOut && _wasLoggedIn) {
        setState(() {
          _selectedIndex = 0; // Go to dictionary tab
          _wasLoggedIn = false;
        });
      } else if (event == AuthChangeEvent.signedIn && !_wasLoggedIn) {
        setState(() {
          _wasLoggedIn = true;
        });
      } else if (isCurrentlyLoggedIn != _wasLoggedIn) {
        // Handle other auth state changes that affect login status
        setState(() {
          _wasLoggedIn = isCurrentlyLoggedIn;
          // Only reset to dictionary tab if user logged out
          if (!isCurrentlyLoggedIn && _selectedIndex == 1) {
            _selectedIndex = 0;
          }
        });
      }
    });
  }

  List<Widget> get _screens {
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    return [
      const WordsScreen(),
      if (isLoggedIn) const FavoriteWordsScreen(),
      const ProfileScreen(),
    ];
  }

  List<NavigationDestination> get _destinations {
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    return [
      const NavigationDestination(icon: Icon(Icons.book), label: 'Dictionary'),
      if (isLoggedIn)
        const NavigationDestination(
          icon: Icon(Icons.favorite),
          label: 'Favorites',
        ),
      const NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
    ];
  }

  void _onItemTapped(int index) {
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    // Convert the tapped index to the actual screen index
    int actualIndex = index;
    if (!isLoggedIn && index == 1) {
      // If not logged in and profile is tapped (visual index 1)
      actualIndex = _screens.length - 1; // This will be the profile screen
    }

    // Ensure we don't select an invalid index
    if (actualIndex >= _screens.length) {
      actualIndex = 0; // Default to dictionary tab
    }

    setState(() {
      _selectedIndex = actualIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ensure selected index is always valid
    if (_selectedIndex >= _screens.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex:
            _selectedIndex == _screens.length - 1 &&
                Supabase.instance.client.auth.currentUser == null
            ? 1 // Show profile tab selected when not logged in
            : _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: _destinations,
      ),
    );
  }
}
