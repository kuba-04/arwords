import 'package:supabase_flutter/supabase_flutter.dart' hide StorageException;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/word.dart';
import '../services/error_handler.dart';
import 'logger_service.dart';

class ContentDownloadService {
  static final ContentDownloadService _instance =
      ContentDownloadService._internal();
  final SupabaseClient _supabase = Supabase.instance.client;

  factory ContentDownloadService() {
    return _instance;
  }

  ContentDownloadService._internal();

  Future<bool> _verifyTables(Database db) async {
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND (name='words' OR name='word_forms')",
      );

      // Check if both tables exist
      final hasWordTable = tables.any((table) => table['name'] == 'words');
      final hasWordFormsTable = tables.any(
        (table) => table['name'] == 'word_forms',
      );

      if (!hasWordTable || !hasWordFormsTable) {
        AppLogger.download(
          'Missing tables - words: $hasWordTable, word_forms: $hasWordFormsTable',
          level: 'warning',
        );
        return false;
      }

      // Verify table structure
      try {
        await db.rawQuery(
          'SELECT id, english_term, primary_arabic_script, part_of_speech, english_definition, is_favorite FROM words LIMIT 1',
        );
        await db.rawQuery(
          'SELECT id, word_id, arabic_script_variant, transliteration, conjugation_details, audio_url FROM word_forms LIMIT 1',
        );
        return true;
      } catch (e) {
        AppLogger.download(
          'Table structure verification failed',
          level: 'warning',
          error: e,
        );
        return false;
      }
    } catch (e) {
      AppLogger.download(
        'Table verification failed',
        level: 'warning',
        error: e,
      );
      return false;
    }
  }

  Future<void> _createTables(Database db) async {
    try {
      // Drop existing tables if they exist but are invalid
      AppLogger.download(
        'Dropping existing tables if they exist...',
        level: 'debug',
      );
      await db.execute('DROP TABLE IF EXISTS word_forms');
      await db.execute('DROP TABLE IF EXISTS words');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS words (
          id TEXT PRIMARY KEY,
          english_term TEXT NOT NULL,
          primary_arabic_script TEXT NOT NULL,
          part_of_speech TEXT NOT NULL,
          english_definition TEXT,
          is_favorite INTEGER DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS word_forms (
          id TEXT PRIMARY KEY,
          word_id TEXT NOT NULL,
          arabic_script_variant TEXT,
          transliteration TEXT NOT NULL,
          conjugation_details TEXT NOT NULL,
          audio_url TEXT,
          FOREIGN KEY (word_id) REFERENCES words (id)
        )
      ''');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_words_english_term ON words(english_term)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_words_primary_arabic_script ON words (primary_arabic_script)',
      );

      // Verify tables were created
      if (!await _verifyTables(db)) {
        throw StorageException(
          'Failed to verify database tables after creation',
        );
      }
    } catch (e) {
      AppLogger.download(
        'Failed to create database schema',
        level: 'error',
        error: e,
      );
      throw StorageException('Failed to create local database: $e');
    }
  }

  Future<void> downloadDictionary({Function(double)? onProgress}) async {
    Database? db;
    try {
      AppLogger.download('Starting dictionary download process...');

      // Check authentication
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Check if user has offline dictionary access
      AppLogger.download('Checking user profile for user ID: ${user.id}');
      final userProfile = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user.id)
          .single();

      AppLogger.download(
        'User profile retrieved: $userProfile',
        level: 'debug',
      );

      if (userProfile == null ||
          userProfile['has_offline_dictionary_access'] != true) {
        AppLogger.download(
          'User does not have offline dictionary access. Profile: $userProfile',
          level: 'error',
        );
        throw Exception('User does not have offline dictionary access');
      }

      AppLogger.download('User has offline dictionary access confirmed');

      // Initialize database
      Directory documentsDirectory = await getApplicationDocumentsDirectory();
      String path = join(documentsDirectory.path, 'arwords.db');
      // Ensure the directory exists
      final targetDir = Directory(dirname(path));
      if (!await targetDir.exists()) {
        AppLogger.download(
          'Creating target directory: ${targetDir.path}',
          level: 'debug',
        );
        try {
          await targetDir.create(recursive: true);
        } catch (e) {
          throw StorageException('Failed to create database directory: $e');
        }
      }

      try {
        db = await openDatabase(
          path,
          version: 1,
          onCreate: (db, version) async {
            AppLogger.download('Creating database tables...', level: 'debug');
            await _createTables(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            AppLogger.download('Upgrading database...', level: 'debug');
            await _createTables(db);
          },
        );

        // Verify tables exist and are valid
        if (!await _verifyTables(db)) {
          AppLogger.download(
            'Tables verification failed after database open, recreating...',
            level: 'warning',
          );
          await _createTables(db);
        }
      } catch (e) {
        throw StorageException('Failed to open/create database: $e');
      }

      try {
        // Fetch all words from Supabase
        final words = await _supabase.from('words').select('''
          id,
          english_term,
          primary_arabic_script,
          part_of_speech,
          english_definition,
          word_forms (
            id,
            arabic_script_variant,
            transliteration,
            conjugation_details,
            audio_url
          )
        ''');

        if (words == null || words.isEmpty) {
          throw NetworkException('No words available in the dictionary');
        }

        // Fetch user's favorite words
        final favoriteWords = await _supabase
            .from('user_favorite_words')
            .select('word_id')
            .eq('user_id', user.id);

        // Create a set of favorite word IDs for faster lookup
        final favoriteWordIds = Set<String>.from(
          favoriteWords?.map((fw) => fw['word_id'] as String) ?? [],
        );

        final totalWords = words.length;

        // Process words in batches
        const batchSize = 100;
        for (var i = 0; i < words.length; i += batchSize) {
          final end = (i + batchSize < words.length)
              ? i + batchSize
              : words.length;
          final batch = words.sublist(i, end);

          try {
            await db.transaction((txn) async {
              for (final wordData in batch) {
                try {
                  final word = Word.fromJson(wordData);
                  final isFavorite = favoriteWordIds.contains(word.id);

                  await txn.rawInsert(
                    '''
                    INSERT OR REPLACE INTO words 
                    (id, english_term, primary_arabic_script, part_of_speech, english_definition, is_favorite) 
                    VALUES (?, ?, ?, ?, ?, ?)
                  ''',
                    [
                      word.id,
                      word.englishTerm,
                      word.primaryArabicScript,
                      word.partOfSpeech,
                      word.englishDefinition,
                      isFavorite ? 1 : 0,
                    ],
                  );

                  // Delete existing word forms before inserting new ones
                  await txn.delete(
                    'word_forms',
                    where: 'word_id = ?',
                    whereArgs: [word.id],
                  );

                  for (final form in word.wordForms) {
                    await txn.rawInsert(
                      '''
                      INSERT OR REPLACE INTO word_forms 
                      (id, word_id, arabic_script_variant, transliteration, conjugation_details, audio_url) 
                      VALUES (?, ?, ?, ?, ?, ?)
                    ''',
                      [
                        form.id,
                        word.id,
                        form.arabicScriptVariant,
                        form.transliteration,
                        form.conjugationDetails,
                        form.audioUrl,
                      ],
                    );
                  }
                } catch (e) {
                  AppLogger.download(
                    'Failed to store word: ${wordData['id']}',
                    level: 'error',
                    error: e,
                  );
                  throw StorageException(
                    'Failed to store word in local database: $e',
                  );
                }
              }
            });
          } catch (e) {
            AppLogger.download(
              'Failed to process batch ${i ~/ batchSize + 1}',
              level: 'error',
              error: e,
            );
            rethrow;
          }

          if (onProgress != null) {
            onProgress(end / totalWords);
          }
        }

        // Verify the download by counting records
        final wordCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM words'),
        );

        if (wordCount != totalWords) {
          throw StorageException(
            'Data verification failed: Expected $totalWords words, but found $wordCount',
          );
        }
      } catch (e) {
        if (e is PostgrestException) {
          throw NetworkException('Database error: ${e.message}');
        }
        rethrow;
      }
    } catch (e) {
      AppLogger.download(
        'Dictionary download failed',
        level: 'error',
        error: e,
      );
      rethrow;
    } finally {
      if (db != null) {
        await db.close();
      }
    }
  }
}
