import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/word.dart';
import 'access_manager.dart';
import 'dart:io';
import 'package:arwords/services/auth_service.dart';

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
}

class OfflineStorageService {
  static OfflineStorageService? _instance;
  static Database? _database;
  final AccessManager _accessManager;

  OfflineStorageService._() : _accessManager = AccessManager();

  factory OfflineStorageService() {
    _instance ??= OfflineStorageService._();
    return _instance!;
  }

  Future<Database> get database async {
    try {
      if (_database != null) {
        if (_database!.isOpen) {
          return _database!;
        } else {
          _database = null;
        }
      }

      _database = await _initDatabase();
      return _database!;
    } catch (e) {
      _database = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      String path = join(documentsDirectory.path, 'arwords.db');

      // Open the database with proper initialization
      return await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          // Tables will be created by the download service
        },
        onOpen: (db) async {
          // Verify tables exist
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND (name='words' OR name='word_forms')",
          );

          if (tables.length != 2) {
            throw Exception(
              'Database schema not initialized. Please download dictionary first.',
            );
          }
        },
      );
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  Future<bool> isDatabaseValid() async {
    try {
      final db = await database;

      // Check if required tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND (name='words' OR name='word_forms')",
      );

      if (tables.length != 2) {
        return false;
      }

      // Check if we have actual data
      final wordCount = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM words WHERE english_term IS NOT NULL',
        ),
      );

      return wordCount != null && wordCount > 0;
    } catch (e) {
      return false;
    }
  }

  Future<void> initializeDatabase() async {
    try {
      final db = await database;

      // Verify tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND (name='words' OR name='word_forms')",
      );

      if (tables.length != 2) {
        throw Exception(
          'Database schema not initialized. Please download dictionary first.',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearDatabase() async {
    try {
      final db = await database;
      await db.delete('word_forms');
      await db.delete('words');
    } catch (e) {
      rethrow;
    }
  }

  Future<Word?> getWord(String wordId) async {
    if (!await _accessManager.verifyPremiumAccess()) {
      throw UnauthorizedException(
        'Premium access required for offline dictionary',
      );
    }

    final currentUserId = AuthService.supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      throw UnauthorizedException('User must be logged in');
    }

    final db = await database;
    final List<Map<String, dynamic>> words = await db.query(
      'words',
      where: 'id = ?',
      whereArgs: [wordId],
    );

    if (words.isEmpty) return null;

    // Create a modifiable copy of the word map
    final Map<String, dynamic> modifiableWordData = Map<String, dynamic>.from(
      words.first,
    );

    final wordForms = await db.query(
      'word_forms',
      where: 'word_id = ?',
      whereArgs: [modifiableWordData['id']],
    );

    // Convert word forms to modifiable maps as well
    final List<Map<String, dynamic>> modifiableWordForms = wordForms
        .map((form) => Map<String, dynamic>.from(form))
        .toList();

    modifiableWordData['word_forms'] = modifiableWordForms;
    return Word.fromJson(modifiableWordData);
  }

  Future<List<Word>> searchWords(String query) async {
    if (!await _accessManager.verifyPremiumAccess()) {
      throw UnauthorizedException(
        'Premium access required for offline dictionary',
      );
    }

    final currentUserId = AuthService.supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      throw UnauthorizedException('User must be logged in');
    }

    final db = await database;
    final List<Map<String, dynamic>> words = await db.rawQuery(
      'SELECT * FROM words WHERE english_term LIKE ? OR primary_arabic_script LIKE ? ORDER BY english_term',
      ['%$query%', '%$query%'],
    );

    final List<Word> results = [];
    for (var word in words) {
      // Create a modifiable copy of the word map
      final Map<String, dynamic> modifiableWordData = Map<String, dynamic>.from(
        word,
      );

      final wordForms = await db.rawQuery(
        'SELECT * FROM word_forms WHERE word_id = ?',
        [modifiableWordData['id']],
      );

      // Convert word forms to modifiable maps as well
      final List<Map<String, dynamic>> modifiableWordForms = wordForms
          .map((form) => Map<String, dynamic>.from(form))
          .toList();

      modifiableWordData['word_forms'] = modifiableWordForms;
      results.add(Word.fromJson(modifiableWordData));
    }

    return results;
  }

  Future<void> toggleFavorite(String wordId, bool isFavorite) async {
    final currentUserId = AuthService.supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      throw UnauthorizedException('User must be logged in');
    }

    final db = await database;
    await db.update(
      'words',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [wordId],
    );
  }

  Future<void> saveUserProfile(Map<String, dynamic> profile) async {
    final db = await database;

    // Drop the existing table to update the schema
    await db.execute('DROP TABLE IF EXISTS user_profiles');

    // Create the table with the correct schema
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_profiles (
        user_id TEXT PRIMARY KEY,
        has_offline_dictionary_access INTEGER DEFAULT 0,
        subscription_valid_until TEXT,
        last_synced TEXT
      )
    ''');

    // Convert boolean to integer for SQLite and prepare data
    final Map<String, dynamic> dbProfile = {
      'user_id': profile['user_id'],
      'has_offline_dictionary_access':
          profile['has_offline_dictionary_access'] == true ? 1 : 0,
      'subscription_valid_until': profile['subscription_valid_until'],
      'last_synced': DateTime.now().toIso8601String(),
    };

    // Insert or update the profile
    await db.insert(
      'user_profiles',
      dbProfile,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final db = await database;

    try {
      final List<Map<String, dynamic>> results = await db.query(
        'user_profiles',
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      if (results.isEmpty) return null;

      // Convert integer back to boolean for the app
      final profile = Map<String, dynamic>.from(results.first);
      profile['has_offline_dictionary_access'] =
          profile['has_offline_dictionary_access'] == 1;

      return profile;
    } catch (e) {
      return null;
    }
  }

  Future<void> clearUserData() async {
    try {
      final db = await database;
      // Clear user profiles
      await db.delete('user_profiles');
      // Clear dictionary data and favorites
      await db.delete('words');
      await db.delete('word_forms');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearUserProfiles() async {
    final db = await database;
    await db.delete('user_profiles');
  }

  Future<List<Word>> getFavoriteWords() async {
    final db = await database;
    final List<Map<String, dynamic>> words = await db.rawQuery(
      'SELECT * FROM words WHERE is_favorite = 1 ORDER BY english_term',
    );

    final List<Word> results = [];
    for (var word in words) {
      // Create a modifiable copy of the word map
      final Map<String, dynamic> modifiableWordData = Map<String, dynamic>.from(
        word,
      );

      final wordForms = await db.rawQuery(
        'SELECT * FROM word_forms WHERE word_id = ?',
        [modifiableWordData['id']],
      );

      // Convert word forms to modifiable maps as well
      final List<Map<String, dynamic>> modifiableWordForms = wordForms
          .map((form) => Map<String, dynamic>.from(form))
          .toList();

      modifiableWordData['word_forms'] = modifiableWordForms;
      results.add(Word.fromJson(modifiableWordData));
    }

    return results;
  }
}
