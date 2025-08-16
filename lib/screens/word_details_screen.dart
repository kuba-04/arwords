import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/words_service.dart' hide WordForm;
import '../services/error_handler.dart';
import '../services/access_manager.dart';
import '../models/word.dart';

class WordDetailsScreen extends StatefulWidget {
  final String wordId;

  const WordDetailsScreen({Key? key, required this.wordId}) : super(key: key);

  @override
  _WordDetailsScreenState createState() => _WordDetailsScreenState();
}

class _WordDetailsScreenState extends State<WordDetailsScreen> {
  late final WordsService _wordsService;
  late final AccessManager _accessManager;
  bool _isFavorite = false;
  bool _isLoading = true;
  bool _isPremium = false;
  String? _error;
  Word? _word;

  static const Map<String, String> _flagMapping = {
    'lb': 'assets/images/flags/lb.png',
    'sa': 'assets/images/flags/sa.png',
    'eg': 'assets/images/flags/eg.png',
  };

  @override
  void initState() {
    super.initState();
    _accessManager = AccessManager();
    _checkPremiumStatus();
    // Initialize WordsService with Supabase client only if we can connect
    try {
      final supabase = Supabase.instance.client;
      // Test the connection by trying to access the client's properties
      final _ = supabase.auth.currentSession;
      _wordsService = WordsService(
        supabase: supabase,
        onNotification: (message) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(
                  bottom: MediaQuery.of(context).size.height - 100,
                  left: 16,
                  right: 16,
                ),
              ),
            );
          }
        },
      );
    } catch (e) {
      // If we can't connect, initialize in offline mode
      _wordsService = WordsService(
        supabase: null,
        onNotification: (message) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(
                  bottom: MediaQuery.of(context).size.height - 100,
                  left: 16,
                  right: 16,
                ),
              ),
            );
          }
        },
      );
    }

    _loadWordDetails();
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final isPremium = await _accessManager.verifyPremiumAccess();
      setState(() {
        _isPremium = isPremium;
      });
    } catch (e) {
      // Handle error silently
      setState(() {
        _isPremium = false;
      });
    }
  }

  Future<void> _loadWordDetails() async {
    setState(() => _isLoading = true);
    try {
      final isFavorite = await _wordsService.isFavorited(widget.wordId);
      final details = await _wordsService.getWordDetails(widget.wordId);

      setState(() {
        _isFavorite = isFavorite;
        _word = details;
        _error = null;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 100,
              left: 16,
              right: 16,
            ),
            action: SnackBarAction(label: 'Retry', onPressed: _loadWordDetails),
          ),
        );
      }
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final newState = !_isFavorite;
      if (_isFavorite) {
        await _wordsService.removeFromFavorites(widget.wordId);
      } else {
        await _wordsService.addToFavorites(widget.wordId);
      }
      setState(() => _isFavorite = newState);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFavorite ? 'Added to favorites' : 'Removed from favorites',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 100,
            left: 16,
            right: 16,
          ),
        ),
      );
    } catch (e) {
      String errorMessage;
      if (e.toString().contains('User not authenticated')) {
        errorMessage = 'Please log in to use the favorites feature.';
      } else if (e.toString().contains('ClientException') ||
          e.toString().contains('Failed to remove from favorite')) {
        errorMessage =
            'Managing favorites requires an internet connection. Please check your connection and try again.';
      } else {
        errorMessage = 'Error updating favorites. Please try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 100,
            left: 16,
            right: 16,
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _toggleFavorite,
            textColor: Colors.white,
          ),
        ),
      );
    }
  }

  Widget _buildFrequencyTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(tag, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
    );
  }

  Widget _buildDialectFlag(String dialectCode) {
    final flagAsset = _flagMapping[dialectCode.toLowerCase()];
    if (flagAsset == null) return Container();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Image.asset(flagAsset, width: 20, height: 12, fit: BoxFit.cover),
    );
  }

  Widget _buildWordForm(WordForm form) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  form.arabicScriptVariant ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    fontFamily: 'ArabicFont',
                  ),
                ),
                Text(
                  form.transliteration,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                form.conjugationDetails,
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (form.audioUrl != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.volume_up, size: 16),
                    onPressed: () {
                      // TODO: Implement audio playback
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null || _word == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            _error ?? 'Word not found',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_word!.englishTerm),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isPremium ||
              (_wordsService.isOnline &&
                  _wordsService
                      .isAuthenticated)) // Show for premium users (even offline) or online authenticated users
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? Colors.red : null,
              ),
              onPressed: _isLoading ? null : _toggleFavorite,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              _word!.primaryArabicScript,
              style: const TextStyle(fontSize: 32, fontFamily: 'ArabicFont'),
            ),
            const SizedBox(height: 8),
            Text(
              _word!.partOfSpeech,
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (_word!.englishDefinition != null) ...[
              const SizedBox(height: 16),
              Text(
                'Definition',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(_word!.englishDefinition!),
            ],
            const SizedBox(height: 24),
            Text('Word Forms', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...(_word!.wordForms.map((form) => _buildWordForm(form)).toList()),
          ],
        ),
      ),
    );
  }
}
