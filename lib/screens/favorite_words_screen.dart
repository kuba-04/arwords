import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/word.dart';
import '../services/words_service.dart';
import 'word_details_screen.dart';

class FavoriteWordsScreen extends StatefulWidget {
  const FavoriteWordsScreen({Key? key}) : super(key: key);

  @override
  State<FavoriteWordsScreen> createState() => _FavoriteWordsScreenState();
}

class _FavoriteWordsScreenState extends State<FavoriteWordsScreen> {
  late final WordsService _wordsService;
  bool _isLoading = true;
  List<Word> _favoriteWords = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _wordsService = WordsService(Supabase.instance.client);
    _loadFavoriteWords();
  }

  Future<void> _loadFavoriteWords() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final words = await _wordsService.getFavoriteWords();
      if (mounted) {
        setState(() {
          _favoriteWords = words;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeFromFavorites(Word word) async {
    try {
      await _wordsService.removeFromFavorites(word.id);
      setState(() {
        _favoriteWords.removeWhere((w) => w.id == word.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Word removed from favorites'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing from favorites: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Favorite Words')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Favorite Words')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Error loading favorites:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadFavoriteWords,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_favoriteWords.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Favorite Words')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No favorite words yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap the heart icon on any word to add it to your favorites',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadFavoriteWords,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorite Words'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFavoriteWords,
            tooltip: 'Refresh favorites',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFavoriteWords,
        child: ListView.builder(
          reverse: true,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            top: 16,
            left: 16,
            right: 16,
          ),
          itemCount: _favoriteWords.length,
          itemBuilder: (context, index) {
            final word = _favoriteWords[_favoriteWords.length - 1 - index];
            return Dismissible(
              key: Key(word.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) => _removeFromFavorites(word),
              child: Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    word.englishTerm,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        word.primaryArabicScript,
                        style: const TextStyle(
                          fontSize: 18,
                          fontFamily: 'ArabicFont',
                        ),
                      ),
                      Text(
                        word.partOfSpeech,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            WordDetailsScreen(wordId: word.id),
                      ),
                    ).then((_) => _loadFavoriteWords());
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
