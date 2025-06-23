import 'package:flutter/material.dart';
import '../services/words_service.dart';

class WordDetailsScreen extends StatefulWidget {
  final String wordId;

  const WordDetailsScreen({Key? key, required this.wordId}) : super(key: key);

  @override
  _WordDetailsScreenState createState() => _WordDetailsScreenState();
}

class _WordDetailsScreenState extends State<WordDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  DetailedWordDTO? _word;

  static const Map<String, String> _flagMapping = {
    'lb': 'assets/images/flags/lb.png',
    'sa': 'assets/images/flags/sa.png',
    'eg': 'assets/images/flags/eg.png',
  };

  @override
  void initState() {
    super.initState();
    _loadWordDetails();
  }

  Future<void> _loadWordDetails() async {
    try {
      final details = await WordsService.getWordDetails(widget.wordId);
      setState(() {
        _word = details;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildDialectFlag(String dialectCode) {
    final flagAsset = _flagMapping[dialectCode.toLowerCase()];
    if (flagAsset == null) return Container();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Image.asset(
        flagAsset,
        width: 20,
        height: 12,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildWordForm(WordForm form) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  form.arabicScript,
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
              const SizedBox(width: 8),
              _buildDialectFlag(form.dialect),
              const SizedBox(width: 4),
              Text(
                form.dialect,
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  _word!.primaryArabicScript,
                  style: const TextStyle(
                    fontSize: 32,
                    fontFamily: 'ArabicFont',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '(${_word!.partOfSpeech}) - ',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    Text(
                      _word!.englishTerm,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _word!.frequencyTag.replaceAll('_', ' '),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: _word!.usageRegions.map((region) => _buildDialectFlag(region)).toList(),
                ),
                const SizedBox(height: 24),

                // Definition
                if (_word!.englishDefinition != null && _word!.englishDefinition!.isNotEmpty) ...[
                  const Text(
                    'Definition',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _word!.englishDefinition!,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                ],

                // Forms
                const Text(
                  'Forms',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: _word!.forms.map((form) => _buildWordForm(form)).toList(),
                  ),
                ),
                const SizedBox(height: 80), // Bottom padding for FAB
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              onPressed: () => Navigator.pop(context),
              backgroundColor: Colors.white,
              child: const Icon(Icons.chevron_left, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
} 