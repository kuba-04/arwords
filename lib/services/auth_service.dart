import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final supabase = Supabase.instance.client;

  static Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
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
      // Create user profile after successful registration
      await supabase.from('user_profiles').insert({
        'user_id': response.user!.id,
        'has_offline_dictionary_access': false,
      });
    }

    return response;
  }

  static Future<void> deleteAccount() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      await supabase.from('user_profiles').delete().eq('user_id', user.id);
      await supabase.auth.admin.deleteUser(user.id);
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final response = await supabase
        .from('user_profiles')
        .select()
        .eq('user_id', user.id)
        .single();

    return response;
  }

  static Future<void> updateUserProfile(Map<String, dynamic> updates) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No authenticated user found');

    await supabase.from('user_profiles').update(updates).eq('user_id', user.id);
  }
}
