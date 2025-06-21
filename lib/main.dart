import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/profile_screen.dart';
import 'screens/words_screen.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Add debug print to verify .env loading
    debugPrint('Loading .env file...');
    await dotenv.load();
    debugPrint('SUPABASE_URL: ${dotenv.env['SUPABASE_URL']}');
    // Don't print the actual key in production!
    debugPrint(
      'SUPABASE_ANON_KEY exists: ${dotenv.env['SUPABASE_ANON_KEY']?.isNotEmpty}',
    );

    // Initialize Supabase
    debugPrint('Initializing Supabase...');
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
    debugPrint('Supabase initialized successfully');

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

  static const List<Widget> _screens = <Widget>[
    WordsScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home), label: 'Words'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
