import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/words_screen.dart';
import 'screens/favorite_words_screen.dart';
import 'screens/profile_screen.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await dotenv.load();
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
    runApp(const MyApp());
  } catch (error, stackTrace) {
    debugPrint('Error in main: $error');
    debugPrint('Stack trace: $stackTrace');
    // Still run the app even if there's an error, but with an error message
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Error initializing app. Please check your configuration.',
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

  @override
  void initState() {
    super.initState();
    // Listen to auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedOut && _selectedIndex == 1) {
        setState(() => _selectedIndex = 0);
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

    setState(() {
      _selectedIndex = actualIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
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
