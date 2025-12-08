import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for storing meal images in Firebase Storage.
/// 
/// Images are stored in the bucket: gs://calorietracker-74c0d.firebasestorage.app
/// Structure: users/{userId}/meals/{mealId}.jpg
/// 
/// Note: This is separate from Firestore where nutritional data is stored.
class StorageService {
  // Firebase Storage bucket for images
  static final FirebaseStorage _storage = FirebaseStorage.instanceFor(
    bucket: 'gs://calorietracker-74c0d.firebasestorage.app',
  );
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // URL cache to avoid repeated network calls for the same image
  static final Map<String, String> _urlCache = {};

  /// Get current user ID (should always exist after AuthService.ensureSignedIn)
  static String get _userId {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated. Call AuthService.ensureSignedIn() first.');
    }
    return user.uid;
  }

  // ============================================
  // IMAGE STORAGE (Firebase Storage)
  // ============================================

  /// Upload image to Firebase Storage and return the download URL
  static Future<String> storeImage(Uint8List imageBytes, String mealId) async {
    final ref = _storage.ref('users/$_userId/meals/$mealId.jpg');
    
    // Upload with metadata
    await ref.putData(
      imageBytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
    
    // Return the download URL
    return await ref.getDownloadURL();
  }

  /// Get download URL for an image (cached to avoid repeated network calls)
  static Future<String?> getImageUrl(String mealId) async {
    final cacheKey = '$_userId/$mealId';
    
    // Return cached URL if available
    if (_urlCache.containsKey(cacheKey)) {
      return _urlCache[cacheKey];
    }
    
    try {
      final ref = _storage.ref('users/$_userId/meals/$mealId.jpg');
      final url = await ref.getDownloadURL();
      _urlCache[cacheKey] = url; // Cache the URL
      return url;
    } catch (e) {
      // Image might not exist
      return null;
    }
  }
  
  /// Clear URL cache (call when user signs out or data is cleared)
  static void clearCache() {
    _urlCache.clear();
  }

  /// Download image bytes from storage
  static Future<Uint8List?> getImage(String mealId) async {
    try {
      final ref = _storage.ref('users/$_userId/meals/$mealId.jpg');
      // Max 10MB
      return await ref.getData(10 * 1024 * 1024);
    } catch (e) {
      return null;
    }
  }

  /// Delete an image from storage
  static Future<void> deleteImage(String mealId) async {
    final cacheKey = '$_userId/$mealId';
    _urlCache.remove(cacheKey); // Invalidate cache
    
    try {
      final ref = _storage.ref('users/$_userId/meals/$mealId.jpg');
      await ref.delete();
    } catch (e) {
      // Image might not exist, that's okay
    }
  }

  // ============================================
  // BATCH OPERATIONS
  // ============================================

  /// Delete all images for the current user
  static Future<void> deleteAllUserImages() async {
    try {
      final ref = _storage.ref('users/$_userId/meals');
      final listResult = await ref.listAll();
      
      // Delete all items
      await Future.wait(
        listResult.items.map((item) => item.delete()),
      );
    } catch (e) {
      // Folder might not exist
    }
  }

  /// Get total storage used by user (in bytes)
  static Future<int> getUserStorageSize() async {
    try {
      final ref = _storage.ref('users/$_userId/meals');
      final listResult = await ref.listAll();
      
      int totalSize = 0;
      for (final item in listResult.items) {
        final metadata = await item.getMetadata();
        totalSize += metadata.size ?? 0;
      }
      
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  // ============================================
  // UTILITY
  // ============================================

  /// Format bytes to human-readable string
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = (bytes.bitLength - 1) ~/ 10;
    
    if (i >= suffixes.length) i = suffixes.length - 1;
    
    num size = bytes / (1 << (i * 10));
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
