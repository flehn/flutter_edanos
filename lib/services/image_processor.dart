import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

/// Service for preprocessing images before sending to Gemini and Storage.
/// 
/// Handles:
/// - Converting any image format to JPEG
/// - Resizing to max 768px (longest side) while preserving aspect ratio
class ImageProcessor {
  /// Max dimension for the longest side of the image
  static const int maxDimension = 768;
  
  /// JPEG quality (0-100)
  static const int jpegQuality = 85;

  /// Preprocess an image: convert to JPEG and resize to max 768px.
  /// 
  /// This runs in an isolate to avoid blocking the UI thread.
  static Future<Uint8List> preprocessImage(Uint8List imageBytes) async {
    // Run in isolate to avoid blocking UI
    return await compute(_processImage, imageBytes);
  }

  /// Internal processing function that runs in an isolate
  static Uint8List _processImage(Uint8List imageBytes) {
    // Decode the image (supports PNG, JPEG, GIF, WebP, etc.)
    final image = img.decodeImage(imageBytes);
    
    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Calculate new dimensions while preserving aspect ratio
    img.Image resizedImage;
    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        // Landscape: width is the longest side
        resizedImage = img.copyResize(
          image,
          width: maxDimension,
          interpolation: img.Interpolation.linear,
        );
      } else {
        // Portrait or square: height is the longest side
        resizedImage = img.copyResize(
          image,
          height: maxDimension,
          interpolation: img.Interpolation.linear,
        );
      }
    } else {
      // Image is already smaller than max dimension
      resizedImage = image;
    }

    // Encode as JPEG
    final jpegBytes = img.encodeJpg(resizedImage, quality: jpegQuality);
    
    return Uint8List.fromList(jpegBytes);
  }

  /// Get image dimensions without fully decoding
  static Future<({int width, int height})?> getImageDimensions(Uint8List imageBytes) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image != null) {
        return (width: image.width, height: image.height);
      }
    } catch (e) {
      // Ignore decoding errors
    }
    return null;
  }
}
