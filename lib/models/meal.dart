import 'dart:typed_data';
import 'ingredient.dart';

/// Exception thrown when the analyzed image does not contain food.
/// Includes image data for background upload.
class NotFoodException implements Exception {
  final String message;
  final Uint8List? imageBytes;
  final String? classification;
  
  NotFoodException({
    this.message = 'No food was recognized in this image',
    this.imageBytes,
    this.classification,
  });
  
  @override
  String toString() => message;
}

/// Represents a complete meal with all its ingredients.
///
/// Total nutritional values are computed as the SUM of all ingredients.
/// When an ingredient's amount changes, only that ingredient recalculates,
/// and the totals automatically update (no proportional scaling).
class Meal {
  final String id;
  String name;
  final DateTime scannedAt;
  final List<Ingredient> ingredients;

  /// Image bytes (for display before saving to storage)
  Uint8List? imageBytes;

  /// Image URL (after saving to Firebase Storage)
  String? imageUrl;

  /// Confidence score from Gemini (0-1)
  final double? confidence;

  /// Notes from Gemini analysis
  final String? analysisNotes;

  /// AI evaluation text about the meal's healthiness
  final String? aiEvaluation;

  /// Whether the meal is considered highly processed by AI
  final bool? isHighlyProcessed;

  /// Classification of the source image (food, nutritional_label_on_packed_product, packaged_product_only)
  final String? imageClassification;

  Meal({
    required this.id,
    required this.name,
    required this.scannedAt,
    required this.ingredients,
    this.imageBytes,
    this.imageUrl,
    this.confidence,
    this.analysisNotes,
    this.aiEvaluation,
    this.isHighlyProcessed,
    this.imageClassification,
  });

  // ============================================
  // COMPUTED TOTALS (sum of all ingredients)
  // ============================================

  /// Total calories = sum of all ingredient calories
  double get totalCalories =>
      ingredients.fold(0, (sum, ing) => sum + ing.calories);

  /// Total protein = sum of all ingredient protein
  double get totalProtein =>
      ingredients.fold(0, (sum, ing) => sum + ing.protein);

  /// Total carbs = sum of all ingredient carbs
  double get totalCarbs => ingredients.fold(0, (sum, ing) => sum + ing.carbs);

  /// Total fat = sum of all ingredient fat
  double get totalFat => ingredients.fold(0, (sum, ing) => sum + ing.fat);

  /// Total fiber = sum of all ingredient fiber
  double get totalFiber => ingredients.fold(0, (sum, ing) => sum + ing.fiber);

  /// Total sugar = sum of all ingredient sugar
  double get totalSugar => ingredients.fold(0, (sum, ing) => sum + ing.sugar);

  /// Total saturated fat = sum of all ingredient saturated fat
  double get totalSaturatedFat =>
      ingredients.fold(0, (sum, ing) => sum + ing.saturatedFat);

  /// Total unsaturated fat = sum of all ingredient unsaturated fat
  double get totalUnsaturatedFat =>
      ingredients.fold(0, (sum, ing) => sum + ing.unsaturatedFat);

  // Comprehensive nutrients (sum, with null handling)
  double? get totalOmega3 => _sumNullable((ing) => ing.omega3);
  double? get totalOmega6 => _sumNullable((ing) => ing.omega6);
  double? get totalSodium => _sumNullable((ing) => ing.sodium);
  double? get totalPotassium => _sumNullable((ing) => ing.potassium);
  double? get totalCalcium => _sumNullable((ing) => ing.calcium);
  double? get totalMagnesium => _sumNullable((ing) => ing.magnesium);
  double? get totalIron => _sumNullable((ing) => ing.iron);
  double? get totalZinc => _sumNullable((ing) => ing.zinc);
  double? get totalVitaminA => _sumNullable((ing) => ing.vitaminA);
  double? get totalVitaminC => _sumNullable((ing) => ing.vitaminC);
  double? get totalVitaminD => _sumNullable((ing) => ing.vitaminD);
  double? get totalVitaminE => _sumNullable((ing) => ing.vitaminE);
  double? get totalVitaminK => _sumNullable((ing) => ing.vitaminK);
  double? get totalVitaminB12 => _sumNullable((ing) => ing.vitaminB12);
  double? get totalFolate => _sumNullable((ing) => ing.folate);
  double? get totalCholine => _sumNullable((ing) => ing.choline);
  double? get totalCholesterol => _sumNullable((ing) => ing.cholesterol);

  /// Helper to sum nullable nutrient values
  double? _sumNullable(double? Function(Ingredient) getter) {
    final values = ingredients.map(getter).whereType<double>().toList();
    if (values.isEmpty) return null;
    double total = 0.0;
    for (final val in values) {
      total += val;
    }
    return total;
  }

  // ============================================
  // INGREDIENT MANAGEMENT
  // ============================================

  /// Update an ingredient's amount by index
  void updateIngredientAmount(int index, double newAmount) {
    if (index >= 0 && index < ingredients.length) {
      ingredients[index].updateAmount(newAmount);
    }
  }

  /// Update an ingredient's amount by ID
  void updateIngredientAmountById(String ingredientId, double newAmount) {
    final ingredient = ingredients.firstWhere(
      (ing) => ing.id == ingredientId,
      orElse: () => throw ArgumentError('Ingredient not found: $ingredientId'),
    );
    ingredient.updateAmount(newAmount);
  }

  /// Remove an ingredient by index
  void removeIngredient(int index) {
    if (index >= 0 && index < ingredients.length) {
      ingredients.removeAt(index);
    }
  }

  /// Remove an ingredient by ID
  void removeIngredientById(String ingredientId) {
    ingredients.removeWhere((ing) => ing.id == ingredientId);
  }

  /// Add a new ingredient
  void addIngredient(Ingredient ingredient) {
    ingredients.add(ingredient);
  }

  // ============================================
  // SERIALIZATION
  // ============================================

  /// Create from Gemini JSON response
  factory Meal.fromGeminiJson(
    Map<String, dynamic> json, {
    required Uint8List? imageBytes,
    String? id,
  }) {
    // Check if the image contains food or a valid food product
    final imageClassification = json['image_classification'] as String? ?? 'food';
    if (imageClassification == 'no_food_no_label') {
      throw NotFoodException(
        imageBytes: imageBytes,
        classification: imageClassification,
      );
    }

    List<Ingredient> ingredientsList = [];
    
    try {
      final ingredientsJson = json['ingredients'];
      if (ingredientsJson is List && ingredientsJson.isNotEmpty) {
        ingredientsList = ingredientsJson
            .map((ing) {
              try {
                if (ing is Map<String, dynamic>) {
                  return Ingredient.fromGeminiJson(ing);
                }
                return null;
              } catch (e) {
                // Skip invalid ingredients
                return null;
              }
            })
            .whereType<Ingredient>()
            .toList();
      }
    } catch (e) {
      // If parsing fails, use empty list
      ingredientsList = [];
    }

    return Meal(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['dishName'] as String? ?? 'Scanned Meal',
      scannedAt: DateTime.now(),
      ingredients: ingredientsList,
      imageBytes: imageBytes,
      confidence: (json['confidence'] as num?)?.toDouble(),
      analysisNotes: json['analysisNotes'] as String?,
      aiEvaluation: json['aiEvaluation'] as String? ??
          json['evaluation'] as String? ??
          json['ai_eval'] as String?,
      isHighlyProcessed: _parseBool(json['isHighlyProcessed']) ??
          _parseBool(json['highlyProcessed']) ??
          _parseBool(json['highly_processed']),
      imageClassification: imageClassification,
    );
  }

  static bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == 'yes') return true;
      if (lower == 'false' || lower == 'no') return false;
    }
    return null;
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'scannedAt': scannedAt.toIso8601String(),
      'ingredients': ingredients.map((ing) => ing.toFirestore()).toList(),
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (confidence != null) 'confidence': confidence,
      if (analysisNotes != null) 'analysisNotes': analysisNotes,
      if (aiEvaluation != null) 'aiEvaluation': aiEvaluation,
      if (isHighlyProcessed != null) 'isHighlyProcessed': isHighlyProcessed,
      if (imageClassification != null) 'imageClassification': imageClassification,
      // Store computed totals for quick queries
      'totalCalories': totalCalories,
      'totalProtein': totalProtein,
      'totalCarbs': totalCarbs,
      'totalFat': totalFat,
    };
  }

  /// Create from Firestore document
  factory Meal.fromFirestore(Map<String, dynamic> doc) {
    final ingredientsList =
        (doc['ingredients'] as List?)
            ?.map(
              (ing) => Ingredient.fromFirestore(ing as Map<String, dynamic>),
            )
            .toList() ??
        [];

    return Meal(
      id: doc['id'] as String,
      name: doc['name'] as String,
      scannedAt: DateTime.parse(doc['scannedAt'] as String),
      ingredients: ingredientsList,
      imageUrl: doc['imageUrl'] as String?,
      confidence: (doc['confidence'] as num?)?.toDouble(),
      analysisNotes: doc['analysisNotes'] as String?,
      aiEvaluation: doc['aiEvaluation'] as String?,
      isHighlyProcessed: doc['isHighlyProcessed'] as bool?,
      imageClassification: doc['imageClassification'] as String?,
    );
  }

  /// Create a copy of the meal
  Meal copyWith({
    String? id,
    String? name,
    DateTime? scannedAt,
    List<Ingredient>? ingredients,
    Uint8List? imageBytes,
    String? imageUrl,
    double? confidence,
    String? analysisNotes,
    String? aiEvaluation,
    bool? isHighlyProcessed,
    String? imageClassification,
  }) {
    return Meal(
      id: id ?? this.id,
      name: name ?? this.name,
      scannedAt: scannedAt ?? this.scannedAt,
      ingredients: ingredients ?? List.from(this.ingredients),
      imageBytes: imageBytes ?? this.imageBytes,
      imageUrl: imageUrl ?? this.imageUrl,
      confidence: confidence ?? this.confidence,
      analysisNotes: analysisNotes ?? this.analysisNotes,
      aiEvaluation: aiEvaluation ?? this.aiEvaluation,
      isHighlyProcessed: isHighlyProcessed ?? this.isHighlyProcessed,
      imageClassification: imageClassification ?? this.imageClassification,
    );
  }

  @override
  String toString() {
    return 'Meal($name: ${ingredients.length} ingredients, ${totalCalories.toStringAsFixed(0)}kcal)';
  }
}
