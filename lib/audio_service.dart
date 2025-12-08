import 'dart:typed_data';
import 'dart:io';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart';

/// Service for handling audio recording functionality.
/// 
/// Uses the `record` package to capture audio which can then
/// be sent to Gemini for food description analysis.
class AudioService {
  static final AudioRecorder _recorder = AudioRecorder();
  static String? _currentRecordingPath;
  static bool _isRecording = false;

  /// Check if currently recording
  static bool get isRecording => _isRecording;

  /// Check if microphone permission is granted
  static Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording audio
  /// Returns true if recording started successfully
  static Future<bool> startRecording() async {
    try {
      if (_isRecording) {
        debugPrint('Already recording');
        return false;
      }

      // Check permission
      if (!await hasPermission()) {
        debugPrint('Microphone permission not granted');
        return false;
      }

      // Create temp file path for recording
      final tempDir = await Directory.systemTemp.createTemp('audio_');
      _currentRecordingPath = '${tempDir.path}/recording.m4a';

      // Configure recording - use AAC which is widely supported
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        numChannels: 1,
      );

      await _recorder.start(config, path: _currentRecordingPath!);
      _isRecording = true;
      debugPrint('Recording started: $_currentRecordingPath');
      return true;
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      _isRecording = false;
      return false;
    }
  }

  /// Stop recording and return the audio bytes
  /// Returns null if recording failed or was cancelled
  static Future<Uint8List?> stopRecording() async {
    try {
      if (!_isRecording) {
        debugPrint('Not currently recording');
        return null;
      }

      final path = await _recorder.stop();
      _isRecording = false;

      if (path == null || path.isEmpty) {
        debugPrint('Recording path is null');
        return null;
      }

      // Read the recorded file
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('Recording file does not exist');
        return null;
      }

      final bytes = await file.readAsBytes();
      debugPrint('Recording stopped: ${bytes.length} bytes');

      // Clean up temp file
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Failed to delete temp recording: $e');
      }

      return bytes;
    } catch (e) {
      debugPrint('Failed to stop recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Cancel recording without saving
  static Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        await _recorder.stop();
        _isRecording = false;

        // Clean up temp file if exists
        if (_currentRecordingPath != null) {
          final file = File(_currentRecordingPath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      debugPrint('Recording cancelled');
    } catch (e) {
      debugPrint('Failed to cancel recording: $e');
      _isRecording = false;
    }
  }

  /// Get the current amplitude (for visualizing recording)
  /// Returns a value between 0.0 and 1.0
  static Future<double> getAmplitude() async {
    try {
      if (!_isRecording) return 0.0;
      final amplitude = await _recorder.getAmplitude();
      // Convert dB to linear scale (rough approximation)
      // Typical range is -60dB to 0dB
      final normalized = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
      return normalized;
    } catch (e) {
      return 0.0;
    }
  }

  /// Dispose resources
  static Future<void> dispose() async {
    await cancelRecording();
    await _recorder.dispose();
  }
}
