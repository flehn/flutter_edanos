import 'package:firebase_auth/firebase_auth.dart';

/// Authentication service for user management.
/// 
/// Supports anonymous authentication by default - users can use the app
/// without creating an account. Later, they can link their anonymous
/// account to an email/password to preserve their data.
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // ============================================
  // INITIALIZATION
  // ============================================

  /// Ensure user is signed in (anonymously if needed)
  /// Call this at app startup to guarantee a valid user ID
  static Future<User> ensureSignedIn() async {
    if (_auth.currentUser != null) {
      return _auth.currentUser!;
    }
    
    // Sign in anonymously
    final credential = await _auth.signInAnonymously();
    return credential.user!;
  }

  // ============================================
  // AUTH STATE
  // ============================================

  /// Get current user
  static User? get currentUser => _auth.currentUser;

  /// Check if user is signed in (includes anonymous)
  static bool get isSignedIn => currentUser != null;

  /// Check if user has a real account (not anonymous)
  static bool get hasAccount => currentUser != null && !currentUser!.isAnonymous;

  /// Stream of auth state changes
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Get user ID (guaranteed non-null after ensureSignedIn)
  static String? get userId => currentUser?.uid;

  /// Get user email (null for anonymous users)
  static String? get userEmail => currentUser?.email;

  /// Get user display name
  static String? get displayName => currentUser?.displayName;
  
  /// Check if current user is anonymous
  static bool get isAnonymous => currentUser?.isAnonymous ?? true;

  // ============================================
  // SIGN IN / SIGN UP
  // ============================================

  /// Sign in with email and password
  static Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Create account with email and password
  static Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name if provided
    if (displayName != null && displayName.isNotEmpty) {
      await credential.user?.updateDisplayName(displayName);
    }

    return credential;
  }

  /// Sign in anonymously (for quick access without account)
  static Future<UserCredential> signInAnonymously() async {
    return await _auth.signInAnonymously();
  }

  /// Sign out
  static Future<void> signOut() async {
    await _auth.signOut();
  }

  // ============================================
  // PASSWORD MANAGEMENT
  // ============================================

  /// Send password reset email
  static Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Update password (requires recent sign-in)
  static Future<void> updatePassword(String newPassword) async {
    await currentUser?.updatePassword(newPassword);
  }

  // ============================================
  // PROFILE MANAGEMENT
  // ============================================

  /// Update display name
  static Future<void> updateDisplayName(String name) async {
    await currentUser?.updateDisplayName(name);
  }

  /// Update email (requires recent sign-in)
  static Future<void> updateEmail(String newEmail) async {
    await currentUser?.verifyBeforeUpdateEmail(newEmail);
  }

  /// Delete account (requires recent sign-in)
  static Future<void> deleteAccount() async {
    await currentUser?.delete();
  }

  /// Re-authenticate user (for sensitive operations)
  static Future<UserCredential?> reauthenticate({
    required String email,
    required String password,
  }) async {
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    return await currentUser?.reauthenticateWithCredential(credential);
  }

  // ============================================
  // ANONYMOUS TO PERMANENT CONVERSION
  // ============================================

  /// Link anonymous account to email/password.
  /// This preserves all existing data (same UID is kept).
  static Future<UserCredential> linkAnonymousToEmail({
    required String email,
    required String password,
  }) async {
    if (currentUser == null) {
      throw Exception('No user signed in');
    }
    
    if (!currentUser!.isAnonymous) {
      throw Exception('Account is already linked to an email');
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );

    return await currentUser!.linkWithCredential(credential);
  }

  /// Create a new account (for anonymous users wanting to save their data)
  /// This is an alias for linkAnonymousToEmail with a clearer name
  static Future<UserCredential> createAccount({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final credential = await linkAnonymousToEmail(
      email: email,
      password: password,
    );

    // Update display name if provided
    if (displayName != null && displayName.isNotEmpty) {
      await credential.user?.updateDisplayName(displayName);
    }

    return credential;
  }

  // ============================================
  // ERROR HANDLING
  // ============================================

  /// Convert FirebaseAuthException to user-friendly message
  static String getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'requires-recent-login':
        return 'Please sign in again to complete this action.';
      default:
        return e.message ?? 'An error occurred. Please try again.';
    }
  }
}

