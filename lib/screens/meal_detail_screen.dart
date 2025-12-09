import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/meal.dart';
import '../models/ingredient.dart';
import '../services/firestore_service.dart';
import '../services/meal_repository.dart';
import 'food_details_screen.dart';

/// Meal Detail Screen - Full nutritional breakdown for a meal
class MealDetailScreen extends StatefulWidget {
  final Meal meal;

  const MealDetailScreen({super.key, required this.meal});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  late Meal _meal;
  late DateTime _originalDate;
  bool _isAddedToQuickAdd = false;
  bool _dateChanged = false;

  @override
  void initState() {
    super.initState();
    _meal = widget.meal.copyWith();
    _originalDate = widget.meal.scannedAt;
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
                  // Meal name
                  Text(
                    _meal.name,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
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

                  // Nutritional Information Card
                  _buildNutritionalCard(),

                  const SizedBox(height: 16),

                  // Secondary nutrients
                  _buildSecondaryNutrients(),

                  const SizedBox(height: 24),

                  // Micronutrients section (expandable)
                  _buildMicronutrientsSection(context),

                  const SizedBox(height: 24),

                  // Ingredients section
                  _buildIngredientsSection(context),

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

  Widget _buildNutritionalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nutritional Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildMainNutrient(
                'Protein',
                '${_meal.totalProtein.toStringAsFixed(0)}g',
                AppTheme.proteinColor,
                Icons.fitness_center,
              ),
              _buildMainNutrient(
                'Carbs',
                '${_meal.totalCarbs.toStringAsFixed(0)}g',
                AppTheme.carbsColor,
                Icons.grain,
              ),
              _buildMainNutrient(
                'Fat',
                '${_meal.totalFat.toStringAsFixed(0)}g',
                AppTheme.fatColor,
                Icons.water_drop,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainNutrient(
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
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 13, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
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

  Widget _buildMicronutrientsSection(BuildContext context) {
    // Check if any micronutrients are available
    final hasComprehensive =
        _meal.totalVitaminA != null ||
        _meal.totalVitaminC != null ||
        _meal.totalVitaminD != null ||
        _meal.totalIron != null ||
        _meal.totalCalcium != null;

    return GestureDetector(
      onTap: () {
        if (hasComprehensive) {
          _showMicronutrientsSheet(context);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Micronutrients',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: hasComprehensive
                  ? AppTheme.primaryBlue
                  : AppTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _showMicronutrientsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Micronutrients',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            if (_meal.totalVitaminA != null)
              _buildMicroRow(
                'Vitamin A',
                '${_meal.totalVitaminA!.toStringAsFixed(0)}mcg',
              ),
            if (_meal.totalVitaminC != null)
              _buildMicroRow(
                'Vitamin C',
                '${_meal.totalVitaminC!.toStringAsFixed(0)}mg',
              ),
            if (_meal.totalVitaminD != null)
              _buildMicroRow(
                'Vitamin D',
                '${_meal.totalVitaminD!.toStringAsFixed(0)}IU',
              ),
            if (_meal.totalCalcium != null)
              _buildMicroRow(
                'Calcium',
                '${_meal.totalCalcium!.toStringAsFixed(0)}mg',
              ),
            if (_meal.totalIron != null)
              _buildMicroRow('Iron', '${_meal.totalIron!.toStringAsFixed(1)}mg'),
            if (_meal.totalPotassium != null)
              _buildMicroRow(
                'Potassium',
                '${_meal.totalPotassium!.toStringAsFixed(0)}mg',
              ),
            if (_meal.totalMagnesium != null)
              _buildMicroRow(
                'Magnesium',
                '${_meal.totalMagnesium!.toStringAsFixed(0)}mg',
              ),
            if (_meal.totalZinc != null)
              _buildMicroRow('Zinc', '${_meal.totalZinc!.toStringAsFixed(1)}mg'),
            const SizedBox(height: 16),
          ],
        ),
      ),
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

  Widget _buildIngredientsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Ingredients',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<Meal>(
                  MaterialPageRoute(
                    builder: (context) => FoodDetailsScreen(
                      meal: _meal,
                      isNewMeal: false, // This is an existing meal being edited
                    ),
                  ),
                );
                // Update local state if meal was edited
                if (result != null) {
                  setState(() {
                    _meal = result;
                  });
                }
              },
              child: const Text(
                'Edit',
                style: TextStyle(color: AppTheme.primaryBlue, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._meal.ingredients.map(
          (ingredient) => _buildIngredientRow(ingredient),
        ),
      ],
    );
  }

  Widget _buildIngredientRow(Ingredient ingredient) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.textTertiary.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          // Bullet point
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          // Ingredient name and amount
          Expanded(
            child: Text(
              '${ingredient.name}: ${ingredient.amount.round()} ${ingredient.unit}',
              style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
            ),
          ),
          // Calories
          Text(
            '${ingredient.calories.round()} kcal',
            style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
          ),
        ],
      ),
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
