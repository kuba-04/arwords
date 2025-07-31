import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_storage_service.dart';
import 'access_manager.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final supabase = Supabase.instance.client;
  static final _offlineStorage = OfflineStorageService();
  static final _accessManager = AccessManager();

  static Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user != null) {
      // Get and store profile locally after successful login
      final profile = await _fetchAndSaveProfile(response.user!.id);
      if (profile == null) {
        throw Exception('Failed to fetch user profile');
      }
    }

    return response;
  }

  static Future<AuthResponse> register({
    required String email,
    required String password,
  }) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user != null) {
      // Create profile in Supabase
      final now = DateTime.now().toIso8601String();
      final profile = {
        'user_id': response.user!.id,
        'has_offline_dictionary_access': false,
        'subscription_valid_until': null,
        'created_at': now,
        'updated_at': now,
      };

      await supabase.from('user_profiles').insert(profile);

      // Store locally
      await _offlineStorage.saveUserProfile(profile);
    }

    return response;
  }

  static Future<void> deleteAccount() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      await supabase.from('user_profiles').delete().eq('user_id', user.id);
      await _offlineStorage.clearUserData();
      await supabase.auth.admin.deleteUser(user.id);
    }
  }

  static Future<void> logout() async {
    try {
      // Clear premium access cache first to prevent race conditions
      await _accessManager.clearPremiumAccessCache();

      // Then clear SQLite data
      await _offlineStorage.clearUserData();

      // Finally clear user profiles from SQLite
      await _offlineStorage.clearUserProfiles();
    } catch (e) {
      // Log error but continue with logout
      debugPrint('Error clearing local data during logout: $e');
    }

    try {
      // Try to sign out from Supabase, but don't fail if it errors
      await supabase.auth.signOut();
    } catch (e) {
      // Log error but don't fail the logout
      debugPrint('Error signing out from Supabase: $e');
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    try {
      // First try to get from local storage
      final localProfile = await _offlineStorage.getUserProfile(user.id);

      // If online, try to sync with server
      if (await _isOnline()) {
        final profile = await _fetchAndSaveProfile(user.id);
        return profile;
      }

      return localProfile;
    } catch (error) {
      return null;
    }
  }

  static Future<bool> _isOnline() async {
    try {
      final response = await supabase.from('user_profiles').select().limit(1);
      return response != null;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> _fetchAndSaveProfile(
    String userId,
  ) async {
    try {
      final response = await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .single();

      if (response != null) {
        // Prepare profile data with only the fields we need
        final Map<String, dynamic> profile = {
          'user_id': response['user_id'],
          'has_offline_dictionary_access':
              response['has_offline_dictionary_access'],
          'subscription_valid_until': response['subscription_valid_until'],
        };

        await _offlineStorage.saveUserProfile(profile);
        return profile;
      }
      return null;
    } catch (e, stackTrace) {
      return null;
    }
  }

  static Future<void> updateUserProfile(Map<String, dynamic> updates) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No authenticated user found');

    // Add updated_at timestamp
    final updatedData = {
      ...updates,
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Update in Supabase if online
    if (await _isOnline()) {
      await supabase
          .from('user_profiles')
          .update(updatedData)
          .eq('user_id', user.id);
    }

    // Update locally
    final currentProfile = await _offlineStorage.getUserProfile(user.id);
    if (currentProfile != null) {
      final updatedProfile = {...currentProfile, ...updatedData};
      await _offlineStorage.saveUserProfile(updatedProfile);
    }
  }
}
