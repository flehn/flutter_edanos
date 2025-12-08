import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  static final ImagePicker _picker = ImagePicker();

  /// Pick an image from the camera
  static Future<Uint8List?> takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85, // Optimize for analysis while maintaining quality
        maxWidth: 1024, // Reasonable size for AI analysis
        maxHeight: 1024,
      );

      if (image != null) {
        return await image.readAsBytes();
      }
      return null;
    } catch (e) {
      print('Error taking photo: $e');
      return null;
    }
  }

  /// Pick an image from the gallery
  static Future<Uint8List?> pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // Optimize for analysis while maintaining quality
        maxWidth: 1024, // Reasonable size for AI analysis
        maxHeight: 1024,
      );

      if (image != null) {
        return await image.readAsBytes();
      }
      return null;
    } catch (e) {
      print('Error picking from gallery: $e');
      return null;
    }
  }

  /// Show options to user - camera or gallery
  static Future<Uint8List?> showImageSourceOptions() async {
    // This method would typically show a dialog/bottom sheet
    // For now, we'll default to gallery - you can customize this
    return await pickFromGallery();
  }

  /// Validate if the image is suitable for food analysis
  static bool isValidFoodImage(Uint8List imageBytes) {
    // Basic validation - check if image has content
    if (imageBytes.isEmpty) {
      return false;
    }

    // Additional validations can be added here:
    // - File size checks
    // - Image format validation
    // - Basic content analysis

    return true;
  }

  /// Get file size in a human-readable format
  static String getFileSizeString(Uint8List imageBytes) {
    int bytes = imageBytes.length;
    if (bytes <= 0) return "0 B";

    const suffixes = ["B", "KB", "MB", "GB"];
    int i = (bytes.bitLength - 1) ~/ 10;

    if (i >= suffixes.length) i = suffixes.length - 1;

    num size = bytes / (1 << (i * 10));
    return "${size.toStringAsFixed(1)} ${suffixes[i]}";
  }
}
