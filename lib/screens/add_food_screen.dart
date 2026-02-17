import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../gemini_service.dart';
import '../image_picker_service.dart';
import '../audio_service.dart';
import '../models/meal.dart';
import '../services/meal_repository.dart';
import '../services/firestore_service.dart';
import 'meal_detail_screen.dart';

/// Add Food Screen - Main entry point for adding meals
/// Features: Take picture, Choose image, Record description, Quick add, Search
class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key});

  @override
  State<AddFoodScreen> createState() => AddFoodScreenState();
}

class AddFoodScreenState extends State<AddFoodScreen> {
  /// Public method to refresh data (called when tab becomes active)
  void refresh() {
    _loadQuickAddItems();
  }

  bool _isAnalyzing = false;
  String? _errorMessage;
  bool _isInitialized = false;
  List<QuickAddItem> _quickAddItems = [];

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  Map<String, dynamic>? _searchResult;

  // Recording functionality
  bool _isRecording = false;

  // Multi-image capture
  List<Uint8List> _capturedImages = [];
  bool _isInCaptureMode = false;
  bool _multiplePictures = false;

  // Recording timer for 1-minute limit
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initializeGemini();
    _loadQuickAddItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showRetrySnackBar(int attempt, int maxRetries) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Currently High Demand, retrying... ($attempt/$maxRetries)'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _searchIngredient(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResult = null;
      _errorMessage = null;
    });

    try {
      final result = await GeminiService.searchIngredient(
        query,
        onRetry: (attempt, max) => _showRetrySnackBar(attempt, max),
      );

      if (result != null) {
        final jsonData = jsonDecode(result);
        setState(() {
          _searchResult = jsonData;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Search failed: $e';
      });
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchResult = null;
    });
  }

  void _addSearchResultAsMeal() {
    if (_searchResult == null) return;

    try {
      // Search now returns comprehensive schema with ingredients array
      final meal = Meal.fromGeminiJson(_searchResult!, imageBytes: null);

      // Validate that meal has at least one ingredient
      if (meal.ingredients.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No ingredients found in search result'),
              backgroundColor: AppTheme.negativeColor,
            ),
          );
        }
        return;
      }

      // Navigate to food details to adjust and save
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MealDetailScreen(meal: meal, isNewMeal: true),
        ),
      );

      _clearSearch();
    } catch (e) {
      debugPrint('Error creating meal from search result: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add ingredient: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Future<void> _initializeGemini() async {
    try {
      await GeminiService.initialize();
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize AI: $e';
      });
    }
  }

  Future<void> _loadQuickAddItems() async {
    try {
      final items = await MealRepository.getQuickAddItems();
      setState(() => _quickAddItems = items);
    } catch (e) {
      debugPrint('Error loading quick add items: $e');
    }
  }

  Future<void> _addFromQuickAdd(QuickAddItem item) async {
    try {
      final meal = await MealRepository.addMealFromQuickAdd(item);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${meal.name} added!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Future<void> _analyzeImage(Uint8List imageBytes) async {
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      // Validate image
      if (!ImagePickerService.isValidFoodImage(imageBytes)) {
        throw Exception('Invalid image for food analysis');
      }

      // Show a non-blocking snackbar instead of modal dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text('Analyzing your food... You can switch tabs.'),
                ),
              ],
            ),
            duration: const Duration(seconds: 30),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }

      // Load user settings to check if detailed analysis is enabled
      final settings = await MealRepository.getUserSettings();
      final useDetailedAnalysis = settings.useDetailedAnalysis;
      debugPrint('🔍 Detailed Analysis Setting: $useDetailedAnalysis');

      // Analyze with appropriate model based on settings
      final analysisResult = await GeminiService.analyzeImage(
        imageBytes,
        includeVitamins: useDetailedAnalysis,
        onRetry: (attempt, max) => _showRetrySnackBar(attempt, max),
      );
      debugPrint('📊 Analysis complete, parsing response...');

      // Clear the analyzing snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (analysisResult == null) {
        throw Exception('No response from AI');
      }

      // Parse the JSON response
      final jsonData = jsonDecode(analysisResult);

      // Create Meal from the response
      final meal = Meal.fromGeminiJson(jsonData, imageBytes: imageBytes);

      // Show success notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Analysis complete! Opening details...'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Navigate to Food Details screen
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MealDetailScreen(meal: meal, isNewMeal: true),
          ),
        );
      }
    } on NotFoodException catch (e) {
      // Handle non-food image specifically
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      setState(() {
        _errorMessage = e.message;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚫 ${e.message}'),
            backgroundColor: AppTheme.negativeColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      // Clear any snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      setState(() {
        _errorMessage = 'Analysis failed: $e';
      });

      // Show error snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Analysis failed: $e'),
            backgroundColor: AppTheme.negativeColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _takePhoto() async {
    // Check 10 photo limit
    if (_capturedImages.length >= 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum 10 images allowed'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
      return;
    }

    try {
      final imageBytes = await ImagePickerService.takePhoto();
      if (imageBytes != null) {
        if (_multiplePictures) {
          // Multi-image mode: add to captured images list and show preview
          setState(() {
            _capturedImages.add(imageBytes);
            _isInCaptureMode = true;
          });
        } else {
          // Single image mode: immediately analyze
          await _analyzeImage(imageBytes);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to take photo: $e';
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _capturedImages.removeAt(index);
      if (_capturedImages.isEmpty) {
        _isInCaptureMode = false;
      }
    });
  }

  void _cancelCapture() {
    setState(() {
      _capturedImages.clear();
      _isInCaptureMode = false;
    });
  }

  Future<void> _analyzeAllImages() async {
    if (_capturedImages.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _isInCaptureMode = false;
      _errorMessage = null;
    });

    try {
      // Show analyzing indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Text('Analyzing ${_capturedImages.length} image(s)...'),
              ],
            ),
            duration: const Duration(seconds: 30),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }

      // Load user settings
      final settings = await MealRepository.getUserSettings();
      final useDetailedAnalysis = settings.useDetailedAnalysis;
      debugPrint('🔍 Multi-image Analysis - Detailed: $useDetailedAnalysis, Images: ${_capturedImages.length}');

      // Analyze all images together
      final result = await GeminiService.analyzeImages(
        _capturedImages,
        includeVitamins: useDetailedAnalysis,
        onRetry: (attempt, max) => _showRetrySnackBar(attempt, max),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (result == null) {
        throw Exception('No response from AI');
      }

      // Parse response - use first image as representative
      final jsonData = jsonDecode(result);
      final meal = Meal.fromGeminiJson(jsonData, imageBytes: _capturedImages.first);

      // Clear captured images
      _capturedImages.clear();

      // Navigate to food details
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MealDetailScreen(meal: meal, isNewMeal: true),
          ),
        );
      }
    } on NotFoodException {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚫 No food was recognised'),
            backgroundColor: AppTheme.negativeColor,
            duration: Duration(seconds: 4),
          ),
        );
      }
      // Keep images so user can retry
      setState(() => _isInCaptureMode = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Analysis failed: $e'),
            backgroundColor: AppTheme.negativeColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // Keep images so user can retry
      setState(() => _isInCaptureMode = true);
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _chooseImage() async {
    try {
      final imageBytes = await ImagePickerService.pickFromGallery();
      if (imageBytes != null) {
        await _analyzeImage(imageBytes);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to choose image: $e';
      });
    }
  }

  Future<void> _recordDescription() async {
    // If already recording, stop and analyze
    if (_isRecording) {
      await _stopRecordingAndAnalyze();
      return;
    }

    // Start recording
    try {
      final started = await AudioService.startRecording();
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not start recording. Check microphone permissions.'),
              backgroundColor: AppTheme.negativeColor,
            ),
          );
        }
        return;
      }

      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });

      // Start 1-minute timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordingSeconds++;
        });
        // Auto-stop after 60 seconds
        if (_recordingSeconds >= 60) {
          _stopRecordingAndAnalyze();
        }
      });

      // Show recording indicator with countdown
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.mic, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Recording... (max 60s) Tap again to stop')),
              ],
            ),
            duration: const Duration(minutes: 1),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Stop',
              textColor: Colors.white,
              onPressed: _stopRecordingAndAnalyze,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isRecording = false);
      _recordingTimer?.cancel();
      _recordingTimer = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording error: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Future<void> _stopRecordingAndAnalyze() async {
    if (!_isRecording) return;

    // Cancel the recording timer
    _recordingTimer?.cancel();
    _recordingTimer = null;

    setState(() {
      _isRecording = false;
      _isAnalyzing = true;
      _errorMessage = null;
      _recordingSeconds = 0;
    });

    // Hide the recording snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    try {
      // Stop recording and get audio bytes
      final audioBytes = await AudioService.stopRecording();

      if (audioBytes == null || audioBytes.isEmpty) {
        throw Exception('No audio recorded');
      }

      // Show analyzing indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('Analyzing your description...'),
              ],
            ),
            duration: const Duration(seconds: 30),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }

      // Load user settings to check if detailed analysis is enabled
      final settings = await MealRepository.getUserSettings();
      final useDetailedAnalysis = settings.useDetailedAnalysis;
      debugPrint('🎤 Voice Analysis - Detailed Setting: $useDetailedAnalysis');

      // Analyze with Gemini
      final result = await GeminiService.analyzeAudio(
        audioBytes,
        includeVitamins: useDetailedAnalysis,
        onRetry: (attempt, max) => _showRetrySnackBar(attempt, max),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (result == null) {
        throw Exception('No response from AI');
      }

      // Parse response
      final jsonData = jsonDecode(result);
      final meal = Meal.fromGeminiJson(jsonData, imageBytes: null);

      // Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Analysis complete!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Navigate to details
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MealDetailScreen(meal: meal, isNewMeal: true),
          ),
        );
      }
    } on NotFoodException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      setState(() => _errorMessage = e.message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚫 ${e.message}'),
            backgroundColor: AppTheme.negativeColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      setState(() => _errorMessage = 'Analysis failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Analysis failed: $e'),
            backgroundColor: AppTheme.negativeColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),

              // Title
              const Text(
                'Food Analyzer',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 24),

              // Search Bar
              _buildSearchBar(),

              // Search Results (if any)
              if (_searchResult != null) ...[
                const SizedBox(height: 16),
                _buildSearchResultCard(),
              ],

              const SizedBox(height: 24),

              // Food analyzer illustration
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/image_o1.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback to emojis if image not found
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.green.withOpacity(0.1),
                            Colors.orange.withOpacity(0.1),
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildFoodEmoji('🥗'),
                          _buildFoodEmoji('🍕'),
                          _buildFoodEmoji('🥩'),
                          _buildFoodEmoji('🍎'),
                          _buildFoodEmoji('🥦'),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 32),

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.negativeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.negativeColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppTheme.negativeColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppTheme.negativeColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Capture preview or Action buttons
              if (_isInCaptureMode && _capturedImages.isNotEmpty) ...[
                // Show captured images preview
                _buildCapturePreview(),
              ] else ...[
                // Normal action buttons
                _buildActionButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Take a picture',
                  onTap: _isAnalyzing || !_isInitialized ? null : _takePhoto,
                ),

                // Multiple pictures checkbox
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _multiplePictures,
                          onChanged: (value) {
                            setState(() => _multiplePictures = value ?? false);
                          },
                          activeColor: AppTheme.primaryBlue,
                          side: BorderSide(color: AppTheme.textTertiary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() => _multiplePictures = !_multiplePictures);
                        },
                        child: Text(
                          'Multiple pictures',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _buildActionButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Choose Image',
                  onTap: _isAnalyzing || !_isInitialized ? null : _chooseImage,
                ),

                const SizedBox(height: 16),

                _buildActionButton(
                  icon: _isRecording ? Icons.stop : Icons.mic_outlined,
                  label: _isRecording ? 'Stop Recording' : 'Record Description',
                  onTap: _isAnalyzing || !_isInitialized
                      ? null
                      : _recordDescription,
                  isRecording: _isRecording,
                ),
              ],

              // Quick Add Section
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Quick Add',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Quick add items from Firestore
              SizedBox(
                height: 120,
                child: _quickAddItems.isEmpty
                    ? Center(
                        child: Text(
                          'No quick add items yet.\nScan a meal and save it!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _quickAddItems.length,
                        itemBuilder: (context, index) {
                          final item = _quickAddItems[index];
                          return _buildQuickAddItemFromData(item);
                        },
                      ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white, width: 1),
        ),
      ),
      child: TextField(
        controller: _searchController,
        onSubmitted: _searchIngredient,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search any ingredient...',
          hintStyle: TextStyle(color: AppTheme.textTertiary),
          prefixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
              : const Icon(Icons.search, color: Colors.white),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppTheme.textTertiary),
                  onPressed: _clearSearch,
                )
              : null,
          filled: false,
          fillColor: Colors.transparent,
          hoverColor: Colors.transparent,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        textInputAction: TextInputAction.search,
      ),
    );
  }

  Widget _buildSearchResultCard() {
    if (_searchResult == null) return const SizedBox.shrink();

    // Search now returns comprehensive schema with ingredients array
    final dishName = _searchResult!['dishName'] as String? ?? 'Searched Item';
    final ingredients = _searchResult!['ingredients'] as List? ?? [];
    final analysisNotes = _searchResult!['analysisNotes'] as String?;

    // Calculate totals from all ingredients
    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;
    String quantity = '100g';

    for (final ing in ingredients) {
      final ingMap = ing as Map<String, dynamic>;
      calories += (ingMap['calories'] as num?)?.toDouble() ?? 0;
      protein += (ingMap['protein'] as num?)?.toDouble() ?? 0;
      carbs += (ingMap['carbs'] as num?)?.toDouble() ?? 0;
      fat += (ingMap['fat'] as num?)?.toDouble() ?? 0;
      if (ingredients.length == 1) {
        quantity = ingMap['quantity'] as String? ?? '100g';
      }
    }

    final name = dishName;
    final description = analysisNotes ?? '';
    final healthBenefits = analysisNotes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'per $quantity',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _clearSearch,
                icon: const Icon(Icons.close, color: AppTheme.textTertiary),
              ),
            ],
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 16),

          // Macros row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMacroChip(
                '🔥',
                '${calories.round()}',
                'kcal',
                AppTheme.calorieOrange,
              ),
              _buildMacroChip(
                '💪',
                '${protein.toStringAsFixed(1)}',
                'g protein',
                AppTheme.proteinColor,
              ),
              _buildMacroChip(
                '🌾',
                '${carbs.toStringAsFixed(1)}',
                'g carbs',
                AppTheme.carbsColor,
              ),
              _buildMacroChip(
                '💧',
                '${fat.toStringAsFixed(1)}',
                'g fat',
                AppTheme.fatColor,
              ),
            ],
          ),

          if (healthBenefits != null && healthBenefits.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('💚', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      healthBenefits,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Add to meal button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addSearchResultAsMeal,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add to Meal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroChip(
    String emoji,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: AppTheme.textTertiary),
        ),
      ],
    );
  }

  Widget _buildFoodEmoji(String emoji) {
    return Text(emoji, style: const TextStyle(fontSize: 40));
  }

  Widget _buildCapturePreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_capturedImages.length} image${_capturedImages.length > 1 ? 's' : ''} captured',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            TextButton(
              onPressed: _cancelCapture,
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.negativeColor),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Thumbnail strip
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _capturedImages.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.memory(
                        _capturedImages[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Remove button
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // Info text
        Text(
          _capturedImages.length == 1
              ? 'Tap "Analyze" to use this image, or "Add More" to capture additional ingredients.'
              : 'Each image will be treated as one ingredient. Tap "Analyze" when ready.',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textTertiary,
          ),
        ),

        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            // Analyze button
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _analyzeAllImages,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isAnalyzing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.check, size: 20),
                label: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze'),
              ),
            ),

            const SizedBox(width: 12),

            // Add More button
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isAnalyzing ? null : _takePhoto,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: BorderSide(color: AppTheme.textTertiary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_a_photo, size: 18),
                label: const Text('Add'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isRecording = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isRecording ? Colors.red.withOpacity(0.1) : null,
            border: isRecording
                ? Border.all(color: Colors.red, width: 2)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isRecording 
                    ? Colors.red
                    : (onTap == null
                        ? AppTheme.textTertiary
                        : AppTheme.textPrimary),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: onTap == null
                      ? AppTheme.textTertiary
                      : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAddItemFromData(QuickAddItem item) {
    return GestureDetector(
      onTap: () => _addFromQuickAdd(item),
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentOrange.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: item.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.restaurant,
                          color: AppTheme.accentOrange,
                        ),
                      ),
                    )
                  : const Icon(Icons.restaurant, color: AppTheme.accentOrange),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                item.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            Text(
              '${item.calories.round()} kcal',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
