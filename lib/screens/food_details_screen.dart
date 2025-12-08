import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/meal.dart';
import '../models/ingredient.dart';
import '../services/meal_repository.dart';
import '../gemini_service.dart';

/// Food Details Screen - Edit ingredients with sliders
/// This is where users can adjust ingredient amounts and see recalculated values
class FoodDetailsScreen extends StatefulWidget {
  final Meal meal;
  final bool isNewMeal; // True if coming from camera, false if editing existing

  const FoodDetailsScreen({
    super.key,
    required this.meal,
    this.isNewMeal = true,
  });

  @override
  State<FoodDetailsScreen> createState() => _FoodDetailsScreenState();
}

class _FoodDetailsScreenState extends State<FoodDetailsScreen> {
  late Meal _meal;
  final TextEditingController _searchController = TextEditingController();
  bool _isSaving = false;
  bool _isSearching = false;
  bool _isAddedToQuickAdd = false;
  Map<String, dynamic>? _searchResult;

  @override
  void initState() {
    super.initState();
    // Create a working copy of the meal
    _meal = widget.meal.copyWith();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateIngredientAmount(int index, double newAmount) {
    setState(() {
      _meal.updateIngredientAmount(index, newAmount);
    });
  }

  void _removeIngredient(int index) {
    setState(() {
      _meal.removeIngredient(index);
    });
  }

  Future<void> _searchIngredient(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResult = null;
    });

    try {
      final result = await GeminiService.searchIngredient(query);

      if (result != null) {
        final jsonData = jsonDecode(result);
        setState(() {
          _searchResult = jsonData;
        });
      }
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
      setState(() => _isSearching = false);
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchResult = null;
    });
  }

  void _addSearchedIngredient() {
    if (_searchResult == null) return;

    // Search now returns comprehensive schema with ingredients array
    final ingredients = _searchResult!['ingredients'] as List? ?? [];
    if (ingredients.isEmpty) return;
    
    // Add all ingredients from the search result
    int addedCount = 0;
    for (final ing in ingredients) {
      final ingredient = Ingredient.fromGeminiJson(ing as Map<String, dynamic>);
      _meal.addIngredient(ingredient);
      addedCount++;
    }

    setState(() {
      _clearSearch();
    });

    final firstIngredient = ingredients.first as Map<String, dynamic>;
    final name = firstIngredient['name'] as String? ?? 'Ingredient';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(addedCount == 1 ? '$name added!' : '$addedCount ingredients added!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _saveMeal() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      if (widget.isNewMeal) {
        // Save new meal to Firestore
        await MealRepository.saveMeal(_meal);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Meal saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Update existing meal
        await MealRepository.updateMeal(_meal.id, _meal);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Meal updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop(_meal);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppTheme.negativeColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _addToQuickAdds() async {
    if (_isAddedToQuickAdd) return; // Already added
    
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left, color: AppTheme.primaryBlue),
              Text(
                'Back',
                style: TextStyle(color: AppTheme.primaryBlue, fontSize: 16),
              ),
            ],
          ),
        ),
        leadingWidth: 100,
        title: const Text('Food Details'),
        centerTitle: true,
        actions: [
          // Add to Quick Add button - shows outlined when not added, filled when added
          if (widget.isNewMeal)
            IconButton(
              onPressed: _isAddedToQuickAdd ? null : _addToQuickAdds,
              icon: Icon(
                _isAddedToQuickAdd 
                    ? Icons.bookmark_added 
                    : Icons.bookmark_add_outlined,
                color: _isAddedToQuickAdd 
                    ? AppTheme.accentOrange.withOpacity(0.5) 
                    : AppTheme.accentOrange,
              ),
              tooltip: _isAddedToQuickAdd ? 'Added to Quick Add' : 'Add to Quick Add',
            ),
          TextButton(
            onPressed: _isSaving ? null : _saveMeal,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Done',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // All content scrollable together
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meal image (if available)
                  if (_meal.imageBytes != null)
                    Container(
                      height: 200,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        image: DecorationImage(
                          image: MemoryImage(_meal.imageBytes!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else if (_meal.imageUrl != null && _meal.imageUrl!.isNotEmpty)
                    Container(
                      height: 200,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
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
                                size: 60,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // Meal name and total calories
                  Text(
                    _meal.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        color: AppTheme.calorieOrange,
                        size: 20,
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

                  const SizedBox(height: 16),

                  // Nutritional summary
                  _buildNutritionalSummary(),

                  const SizedBox(height: 16),

                  // Ingredients header
                  const Text(
                    'Ingredients:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Ingredients list (not in a separate scrollable)
                  ...List.generate(
                    _meal.ingredients.length,
                    (index) => _buildIngredientCard(index, _meal.ingredients[index]),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Add ingredient section (fixed at bottom)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.backgroundDark,
              border: Border(
                top: BorderSide(color: AppTheme.textTertiary.withOpacity(0.2)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add Ingredient',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onSubmitted: _searchIngredient,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search for ingredient ...',
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
                            icon: const Icon(
                              Icons.clear,
                              color: AppTheme.textTertiary,
                            ),
                            onPressed: _clearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.black,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 1),
                    ),
                  ),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  textInputAction: TextInputAction.search,
                ),

                // Search result
                if (_searchResult != null) ...[
                  const SizedBox(height: 12),
                  _buildSearchResultPreview(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionalSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nutritional Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildNutrientItem(
                'Protein',
                '${_meal.totalProtein.toStringAsFixed(1)}g',
                AppTheme.proteinColor,
                Icons.fitness_center,
              ),
              _buildNutrientItem(
                'Carbs',
                '${_meal.totalCarbs.toStringAsFixed(1)}g',
                AppTheme.carbsColor,
                Icons.grain,
              ),
              _buildNutrientItem(
                'Fat',
                '${_meal.totalFat.toStringAsFixed(1)}g',
                AppTheme.fatColor,
                Icons.water_drop,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSmallNutrient(
                'Fiber',
                '${_meal.totalFiber.toStringAsFixed(1)}g',
              ),
              _buildSmallNutrient(
                'Sugars',
                '${_meal.totalSugar.toStringAsFixed(1)}g',
              ),
              _buildSmallNutrient(
                'Sat. Fat',
                '${_meal.totalSaturatedFat.toStringAsFixed(1)}g',
              ),
              _buildSmallNutrient(
                'Unsat. Fat',
                '${_meal.totalUnsaturatedFat.toStringAsFixed(1)}g',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientItem(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallNutrient(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultPreview() {
    if (_searchResult == null) return const SizedBox.shrink();

    // Search now returns comprehensive schema with ingredients array
    final dishName = _searchResult!['dishName'] as String? ?? 'Searched Item';
    final ingredients = _searchResult!['ingredients'] as List? ?? [];
    
    // Calculate totals from all ingredients
    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;
    String quantity = '100g';
    String name = dishName;
    
    for (final ing in ingredients) {
      final ingMap = ing as Map<String, dynamic>;
      calories += (ingMap['calories'] as num?)?.toDouble() ?? 0;
      protein += (ingMap['protein'] as num?)?.toDouble() ?? 0;
      carbs += (ingMap['carbs'] as num?)?.toDouble() ?? 0;
      fat += (ingMap['fat'] as num?)?.toDouble() ?? 0;
      if (ingredients.length == 1) {
        quantity = ingMap['quantity'] as String? ?? '100g';
        name = ingMap['name'] as String? ?? dishName;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'per $quantity',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _clearSearch,
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppTheme.textTertiary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniMacro(
                '${calories.round()}',
                'kcal',
                AppTheme.calorieOrange,
              ),
              _buildMiniMacro(
                '${protein.toStringAsFixed(1)}g',
                'protein',
                AppTheme.proteinColor,
              ),
              _buildMiniMacro(
                '${carbs.toStringAsFixed(1)}g',
                'carbs',
                AppTheme.carbsColor,
              ),
              _buildMiniMacro(
                '${fat.toStringAsFixed(1)}g',
                'fat',
                AppTheme.fatColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addSearchedIngredient,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add to Meal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMacro(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
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

  Widget _buildIngredientCard(int index, Ingredient ingredient) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.textTertiary.withOpacity(0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Delete button
              GestureDetector(
                onTap: () => _removeIngredient(index),
                child: Container(
                  width: 24,
                  height: 24,
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
              const SizedBox(width: 12),

              // Ingredient name
              Expanded(
                child: Text(
                  ingredient.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),

              // Amount badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${ingredient.amount.round()}${ingredient.unit}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Calories badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${ingredient.calories.round()}kcal',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: AppTheme.primaryBlue,
              inactiveTrackColor: AppTheme.textTertiary.withOpacity(0.3),
              thumbColor: AppTheme.primaryBlue,
              overlayColor: AppTheme.primaryBlue.withOpacity(0.2),
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
}
