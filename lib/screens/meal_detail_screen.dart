import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/circle_progress_painter.dart';
import '../models/meal.dart';
import '../models/ingredient.dart';
import '../services/firestore_service.dart';
import '../services/meal_repository.dart';
import '../gemini_service.dart';
import '../image_picker_service.dart';

/// Meal Detail Screen - Full nutritional breakdown for a meal
class MealDetailScreen extends StatefulWidget {
  final Meal meal;
  final bool isNewMeal; // True if coming from camera/scan, false if editing existing

  const MealDetailScreen({
    super.key,
    required this.meal,
    this.isNewMeal = false,
  });

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  late Meal _meal;
  late DateTime _originalDate;
  bool _isAddedToQuickAdd = false;
  bool _dateChanged = false;
  UserGoals? _userGoals;
  bool _isLoadingGoals = false;
  String _selectedTab = 'ingredients';
  final TextEditingController _ingredientSearchController =
      TextEditingController();
  bool _isAddingIngredient = false;
  bool _isSearchingIngredient = false;
  final Set<int> _expandedIngredients = {};

  @override
  void initState() {
    super.initState();
    _meal = widget.meal.copyWith();
    _originalDate = widget.meal.scannedAt;
    _loadGoals();
    // Auto-save new meals
    if (widget.isNewMeal) {
      _autoSaveNewMeal();
    }
  }

  @override
  void dispose() {
    _ingredientSearchController.dispose();
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

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _meal.scannedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryBlue,
              onPrimary: Colors.white,
              surface: AppTheme.cardDark,
              onSurface: AppTheme.textPrimary,
            ),
            dialogBackgroundColor: AppTheme.backgroundDark,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final newDateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _meal.scannedAt.hour,
        _meal.scannedAt.minute,
      );
      await _updateMealDateTime(newDateTime);
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.input,
      initialTime: TimeOfDay.fromDateTime(_meal.scannedAt),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryBlue,
              onPrimary: Colors.white,
              surface: AppTheme.cardDark,
              onSurface: AppTheme.textPrimary,
            ),
            dialogBackgroundColor: AppTheme.backgroundDark,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final newDateTime = DateTime(
        _meal.scannedAt.year,
        _meal.scannedAt.month,
        _meal.scannedAt.day,
        picked.hour,
        picked.minute,
      );
      await _updateMealDateTime(newDateTime);
    }
  }

  Future<void> _updateMealDateTime(DateTime newDateTime) async {
    final updatedMeal = _meal.copyWith(scannedAt: newDateTime);
    
    try {
      await FirestoreService.updateMeal(_meal.id, updatedMeal);
      
      // Check if the date (day) changed
      final originalDay = DateTime(_originalDate.year, _originalDate.month, _originalDate.day);
      final newDay = DateTime(newDateTime.year, newDateTime.month, newDateTime.day);
      
      setState(() {
        _meal = updatedMeal;
        _dateChanged = originalDay != newDay;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Date/time updated'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Future<void> _addToQuickAdds() async {
    if (_isAddedToQuickAdd) return;
    
    try {
      final quickAddItem = MealRepository.mealToQuickAdd(_meal);
      await MealRepository.saveQuickAddItem(quickAddItem);

      setState(() {
        _isAddedToQuickAdd = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to Quick Add!'),
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

  Future<void> _loadGoals() async {
    setState(() => _isLoadingGoals = true);
    try {
      final goals = await MealRepository.getUserGoals();
      if (mounted) {
        setState(() {
          _userGoals = goals;
        });
      }
    } catch (e) {
      debugPrint('Error loading goals: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingGoals = false);
      }
    }
  }

  int _perMealProteinTarget() => _userGoals?.perMealProtein ?? 40;
  int _perMealCarbTarget() => _userGoals?.perMealCarbs ?? 40;
  int _perMealFatTarget() => _userGoals?.perMealFat ?? 20;

  Future<void> _editMealName() async {
    final controller = TextEditingController(text: _meal.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: const Text(
          'Edit Meal Name',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter meal name',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.textTertiary),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.primaryBlue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _meal.name) {
      setState(() {
        _meal = _meal.copyWith(name: newName);
      });
      await _saveMealChanges();
    }
  }

  Future<void> _saveMealChanges() async {
    try {
      await FirestoreService.updateMeal(_meal.id, _meal);
    } catch (e) {
      debugPrint('Failed to save meal changes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save changes: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Future<void> _autoSaveNewMeal() async {
    try {
      // Save the new meal to Firestore
      await MealRepository.saveMeal(_meal);
      debugPrint('Auto-saved new meal: ${_meal.name}');
    } catch (e) {
      debugPrint('Failed to auto-save new meal: $e');
    }
  }

  Future<void> _deleteMeal() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: const Text(
          'Delete Meal',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to delete this meal?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.negativeColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await MealRepository.deleteMeal(_meal.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meal deleted'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(); // Go back to previous screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Future<void> _addIngredientsFromJson(Map<String, dynamic> data) async {
    try {
      final ingredientsJson = data['ingredients'];
      if (ingredientsJson is! List || ingredientsJson.isEmpty) {
        throw Exception('No ingredients found');
      }

      final newIngredients = <Ingredient>[];
      for (final ing in ingredientsJson) {
        if (ing is Map<String, dynamic>) {
          try {
            newIngredients.add(Ingredient.fromGeminiJson(ing));
          } catch (_) {
            // skip invalid ingredient
          }
        }
      }

      if (newIngredients.isEmpty) {
        throw Exception('No valid ingredients found');
      }

      setState(() {
        _meal.ingredients.addAll(newIngredients);
      });

      await _saveMealChanges();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not add ingredient: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    }
  }

  Future<void> _handleSearchIngredient(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearchingIngredient = true);
    try {
      final result = await GeminiService.searchIngredient(
        query,
        onRetry: (attempt, max) => _showRetrySnackBar(attempt, max),
      );
      if (result == null) {
        throw Exception('No response from AI');
      }

      final data = jsonDecode(result) as Map<String, dynamic>;
      await _addIngredientsFromJson(data);
      _ingredientSearchController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSearchingIngredient = false);
      }
    }
  }

  Future<void> _handleCameraIngredient() async {
    try {
      final Uint8List? imageBytes = await ImagePickerService.takePhoto();
      if (imageBytes == null) return;

      setState(() => _isAddingIngredient = true);

      final result = await GeminiService.analyzeImage(
        imageBytes,
        onRetry: (attempt, max) => _showRetrySnackBar(attempt, max),
      );
      if (result == null) {
        throw Exception('No response from AI');
      }

      final data = jsonDecode(result) as Map<String, dynamic>;
      await _addIngredientsFromJson(data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera add failed: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingIngredient = false);
      }
    }
  }

  void _updateIngredientAmount(int index, double newAmount) {
    if (index < 0 || index >= _meal.ingredients.length) return;
    setState(() {
      _meal.updateIngredientAmount(index, newAmount);
    });
    _saveMealChanges();
  }

  Future<void> _removeIngredient(int index) async {
    if (index < 0 || index >= _meal.ingredients.length) return;
    setState(() {
      _meal.removeIngredient(index);
    });
    await _saveMealChanges();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: CustomScrollView(
        slivers: [
          // Collapsible app bar with meal image
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppTheme.backgroundDark,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(
                _dateChanged ? _meal : null, // Return meal if date changed so food log can refresh
              ),
            ),
            actions: [
              // Quick Add button
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _isAddedToQuickAdd 
                          ? Icons.bookmark_added 
                          : Icons.bookmark_add_outlined,
                      color: _isAddedToQuickAdd 
                          ? AppTheme.accentOrange.withOpacity(0.5) 
                          : AppTheme.accentOrange,
                      size: 20,
                    ),
                  ),
                  onPressed: _isAddedToQuickAdd ? null : _addToQuickAdds,
                  tooltip: _isAddedToQuickAdd ? 'Added to Quick Add' : 'Add to Quick Add',
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildMealImage(),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meal name (tappable to edit)
                  GestureDetector(
                    onTap: _editMealName,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _meal.name,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.edit,
                          color: AppTheme.textTertiary,
                          size: 18,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Calories and date/time
                  Row(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            color: AppTheme.calorieOrange,
                            size: 22,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_meal.totalCalories.round()} calories',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.calorieOrange,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _buildDateChip(_formatDate(_meal.scannedAt), onTap: _selectDate),
                      const SizedBox(width: 8),
                      _buildDateChip(_formatTime(_meal.scannedAt), onTap: _selectTime),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Macro rings vs per-meal targets
                  _buildMacroRings(),

                  const SizedBox(height: 20),

                  // Secondary nutrients
                  _buildSecondaryNutrients(),

                  const SizedBox(height: 24),

                  // Tabbed content
                  _buildTabSelector(),

                  const SizedBox(height: 16),

                  _buildTabContent(),

                  const SizedBox(height: 32),

                  // Delete meal button
                  Center(
                    child: TextButton.icon(
                      onPressed: _deleteMeal,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppTheme.negativeColor,
                      ),
                      label: const Text(
                        'Delete Meal',
                        style: TextStyle(
                          color: AppTheme.negativeColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealImage() {
    // First try imageBytes (available for newly scanned meals)
    if (_meal.imageBytes != null) {
      return Image.memory(_meal.imageBytes!, fit: BoxFit.cover);
    }
    
    // Then try imageUrl (available for meals loaded from Firestore)
    if (_meal.imageUrl != null && _meal.imageUrl!.isNotEmpty) {
      return Image.network(
        _meal.imageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: AppTheme.cardDark,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: AppTheme.cardDark,
            child: const Center(
              child: Icon(
                Icons.restaurant,
                size: 80,
                color: AppTheme.textTertiary,
              ),
            ),
          );
        },
      );
    }
    
    // Fallback: no image available
    return Container(
      color: AppTheme.cardDark,
      child: const Center(
        child: Icon(
          Icons.restaurant,
          size: 80,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }

  Widget _buildDateChip(String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        ),
      ),
    );
  }

  Widget _buildMacroRings() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildMacroRing(
          label: 'Protein',
          value: _meal.totalProtein,
          target: _perMealProteinTarget().toDouble(),
          unit: 'g',
          color: AppTheme.proteinColor,
        ),
        _buildMacroRing(
          label: 'Carbs',
          value: _meal.totalCarbs,
          target: _perMealCarbTarget().toDouble(),
          unit: 'g',
          color: AppTheme.carbsColor,
        ),
        _buildMacroRing(
          label: 'Fat',
          value: _meal.totalFat,
          target: _perMealFatTarget().toDouble(),
          unit: 'g',
          color: AppTheme.fatColor,
        ),
      ],
    );
  }

  Widget _buildMacroRing({
    required String label,
    required double value,
    required double target,
    required String unit,
    required Color color,
  }) {
    final progress = target > 0 ? (value / target).clamp(0.0, 2.0) : 0.0;
    final percentage = (progress * 100).round();

    return Column(
      children: [
        SizedBox(
          width: 90,
          height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: CustomPaint(
                  painter: CircleProgressPainter(
                    progress: 1.0,
                    progressColor: Colors.white,
                    backgroundColor: Colors.transparent,
                    strokeWidth: 2,
                    isDotted: true,
                  ),
                ),
              ),
              SizedBox(
                width: 82,
                height: 82,
                child: CustomPaint(
                  painter: CircleProgressPainter(
                    progress: progress > 1 ? 1 : progress,
                    progressColor: color,
                    backgroundColor: Colors.transparent,
                    strokeWidth: 5,
                    isDotted: false,
                  ),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.backgroundDark,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${value.toStringAsFixed(0)}$unit',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '/${target.toStringAsFixed(0)}$unit',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Text(
          '$percentage%',
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildTabSelector() {
    final tabs = [
      {'key': 'ai', 'label': 'AI Evaluation'},
      {
        'key': 'ingredients',
        'label': '${_meal.ingredients.length} Ingredients'
      },
      {'key': 'micros', 'label': 'Micronutrients'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: tabs
            .map(
              (tab) => Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedTab = tab['key'] as String);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _selectedTab == tab['key']
                          ? Colors.white.withOpacity(0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        tab['label'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _selectedTab == tab['key']
                              ? Colors.white
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 'ingredients':
        return _buildIngredientsTab();
      case 'micros':
        return _buildMicronutrientsTab();
      case 'ai':
      default:
        return _buildAiEvaluationTab();
    }
  }

  Widget _buildAiEvaluationTab() {
    final evaluation =
        _meal.aiEvaluation ?? _meal.analysisNotes ?? 'No AI evaluation yet.';
    final processed = _meal.isHighlyProcessed ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: processed
                      ? AppTheme.negativeColor.withOpacity(0.15)
                      : Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Icon(
                      processed ? Icons.warning_amber_rounded : Icons.check,
                      size: 16,
                      color: processed
                          ? AppTheme.negativeColor
                          : Colors.greenAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      processed ? 'Highly processed' : 'Minimally processed',
                      style: TextStyle(
                        color: processed
                            ? AppTheme.negativeColor
                            : Colors.greenAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoadingGoals) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            evaluation,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsTab() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(
            _meal.ingredients.length,
            (index) => _buildIngredientRow(index, _meal.ingredients[index]),
          ),
          const SizedBox(height: 12),
          _buildIngredientSearchBar(),
        ],
      ),
    );
  }

  Widget _buildIngredientSearchBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add ingredient',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _isSearchingIngredient
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.search, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ingredientSearchController,
                onSubmitted: _handleSearchIngredient,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search for ingredient ...',
                  hintStyle: TextStyle(color: AppTheme.textTertiary),
                  filled: false,
                  fillColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primaryBlue),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: _ingredientSearchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _ingredientSearchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close, color: AppTheme.textTertiary),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed:
                  _isAddingIngredient ? null : () => _handleCameraIngredient(),
              icon: _isAddingIngredient
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.camera_alt_outlined,
                      color: AppTheme.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMicronutrientsTab() {
    final microItems = <Widget>[];

    void addMicro(String label, String? value) {
      if (value != null) {
        microItems.add(_buildMicroRow(label, value));
      }
    }

    addMicro(
        'Vitamin A',
        _meal.totalVitaminA != null
            ? '${_meal.totalVitaminA!.toStringAsFixed(0)}mcg'
            : null);
    addMicro(
        'Vitamin C',
        _meal.totalVitaminC != null
            ? '${_meal.totalVitaminC!.toStringAsFixed(0)}mg'
            : null);
    addMicro(
        'Vitamin D',
        _meal.totalVitaminD != null
            ? '${_meal.totalVitaminD!.toStringAsFixed(0)}IU'
            : null);
    addMicro(
        'Calcium',
        _meal.totalCalcium != null
            ? '${_meal.totalCalcium!.toStringAsFixed(0)}mg'
            : null);
    addMicro(
        'Iron',
        _meal.totalIron != null
            ? '${_meal.totalIron!.toStringAsFixed(1)}mg'
            : null);
    addMicro(
        'Potassium',
        _meal.totalPotassium != null
            ? '${_meal.totalPotassium!.toStringAsFixed(0)}mg'
            : null);
    addMicro(
        'Magnesium',
        _meal.totalMagnesium != null
            ? '${_meal.totalMagnesium!.toStringAsFixed(0)}mg'
            : null);
    addMicro(
        'Zinc',
        _meal.totalZinc != null
            ? '${_meal.totalZinc!.toStringAsFixed(1)}mg'
            : null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: microItems.isEmpty
          ? const Text(
              'No micronutrients available for this meal.',
              style: TextStyle(color: AppTheme.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: microItems,
            ),
    );
  }
  Widget _buildSecondaryNutrients() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSecondaryNutrient(
          'Fiber',
          '${_meal.totalFiber.toStringAsFixed(1)}g',
        ),
        _buildSecondaryNutrient(
          'Sugars',
          '${_meal.totalSugar.toStringAsFixed(1)}g',
        ),
        _buildSecondaryNutrient(
          'Sat. Fat',
          '${_meal.totalSaturatedFat.toStringAsFixed(1)}g',
        ),
        _buildSecondaryNutrient(
          'Unsat. Fat',
          '${_meal.totalUnsaturatedFat.toStringAsFixed(1)}g',
        ),
      ],
    );
  }

  Widget _buildSecondaryNutrient(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildMicroRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientRow(int index, Ingredient ingredient) {
    final isExpanded = _expandedIngredients.contains(index);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.textTertiary.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row with delete button, name, amount/kcal and expand chevron
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Delete button (fixed left)
              GestureDetector(
                onTap: () => _removeIngredient(index),
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 12, top: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.negativeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.remove,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              // Name, amount/kcal and chevron — tappable to expand macros
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedIngredients.remove(index);
                      } else {
                        _expandedIngredients.add(index);
                      }
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Ingredient name
                            Text(
                              ingredient.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            // Amount and kcal
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${ingredient.amount.round()}${ingredient.unit}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${ingredient.calories.round()} kcal',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Chevron to indicate expandable
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: AppTheme.textTertiary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Expandable macro nutrition section
          if (isExpanded) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMacroChip('Protein', ingredient.protein, AppTheme.proteinColor),
                _buildMacroChip('Carbs', ingredient.carbs, AppTheme.carbsColor),
                _buildMacroChip('Fat', ingredient.fat, AppTheme.fatColor),
                _buildMacroChip('Sugar', ingredient.sugar, AppTheme.sugarColor),
              ],
            ),
            const SizedBox(height: 6),
          ],

          const SizedBox(height: 8),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: AppTheme.primaryBlue,
              inactiveTrackColor: AppTheme.textTertiary.withValues(alpha: 0.3),
              thumbColor: AppTheme.primaryBlue,
              overlayColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: ingredient.amount.clamp(
                ingredient.minAmount,
                ingredient.maxAmount,
              ),
              min: ingredient.minAmount,
              max: ingredient.maxAmount,
              onChanged: (value) => _updateIngredientAmount(index, value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroChip(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          '${value.toStringAsFixed(1)}g',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

