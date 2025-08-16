import 'dart:async';
import 'package:flutter/material.dart';
import '../services/words_service.dart' show WordDTO, WordsService;
import '../services/error_handler.dart';
import 'word_details_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_screen.dart';

// --- Main Screen Widget ---

class WordsScreen extends StatefulWidget {
  const WordsScreen({Key? key}) : super(key: key);

  @override
  _WordsScreenState createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  List<WordDTO> _words = [];
  bool _isLoading = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  late final WordsService _wordsService;

  // NOTE: Make sure to add flag assets to your pubspec.yaml
  // assets:
  //   - assets/images/flags/
  static const Map<String, String> _flagMapping = {
    'lb': 'assets/images/flags/lb.png',
    'sa': 'assets/images/flags/sa.png',
    'eg': 'assets/images/flags/eg.png',
  };

  @override
  void initState() {
    super.initState();
    _wordsService = WordsService(
      supabase: Supabase.instance.client,
      onNotification: _showNotification,
    );
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final text = _searchController.text;
      if (text.length >= 2) {
        _searchWords(text);
      } else if (text.isEmpty) {
        setState(() {
          _words = [];
          _isLoading = false;
          _error = null;
        });
      }
    });
  }

  Future<void> _searchWords(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await _wordsService.getWords(
        page: 1,
        pageSize: 20,
        searchTerm: query,
      );
      setState(() {
        _words = response.data;
        _isLoading = false;
      });
    } catch (e) {
      String errorMessage;
      if (e is NetworkException) {
        errorMessage = e.message;
      } else {
        errorMessage = 'An unexpected error occurred. Please try again later.';
      }
      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
      _showNotification(errorMessage);
    }
  }

  void _resetSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _words = [];
      _isLoading = false;
      _error = null;
    });
  }

  void _showNotification(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Go to Profile',
          onPressed: () {
            // Navigate to profile screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildContent(),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildSearchInput()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
              child: const Text('Go to Profile'),
            ),
          ],
        ),
      );
    }
    if (_words.isEmpty && _searchController.text.length >= 2) {
      return const Center(child: Text('No words found'));
    }
    if (_words.isEmpty) {
      return const Center(child: Text('Type at least 2 characters to search'));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _words.length,
      itemBuilder: (context, index) {
        return WordItem(
          word: _words[_words.length - 1 - index],
          flagMapping: _flagMapping,
        );
      },
    );
  }

  Widget _buildSearchInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16,
      ), // Adjust padding as needed
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (_) => _onSearchChanged(),
        decoration: InputDecoration(
          hintText: 'Enter an Arabic or English word',
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _resetSearch,
                )
              : null,
        ),
      ),
    );
  }
}

// --- Word Item Widget ---

class WordItem extends StatelessWidget {
  final WordDTO word;
  final Map<String, String> flagMapping;

  const WordItem({Key? key, required this.word, required this.flagMapping})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WordDetailsScreen(wordId: word.id),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              word.primaryArabicScript,
              style: const TextStyle(fontSize: 24, fontFamily: 'ArabicFont'),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '(${word.partOfSpeech}) - ${word.englishTerm}',
                    style: TextStyle(color: Colors.grey[700]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (word.dialects.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: word.dialects.map((dialect) {
                      final flagAsset =
                          flagMapping[dialect.countryCode.toLowerCase()];
                      return flagAsset != null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Image.asset(
                                flagAsset,
                                width: 20,
                                height: 12,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Container();
                    }).toList(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
