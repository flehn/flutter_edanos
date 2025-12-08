/// Represents a single ingredient within a meal.
///
/// Each ingredient has its own nutritional values that scale
/// proportionally when the amount is adjusted.
class Ingredient {
  final String id;
  final String name;

  /// Current amount in grams (or ml for liquids)
  double amount;

  /// Original amount from Gemini analysis (used for recalculation)
  final double originalAmount;

  /// Unit of measurement (g, ml, etc.)
  final String unit;

  // Original nutritional values (from Gemini, per originalAmount)
  final double originalCalories;
  final double originalProtein;
  final double originalCarbs;
  final double originalFat;
  final double originalFiber;
  final double originalSugar;
  final double originalSaturatedFat;
  final double originalUnsaturatedFat;

  // Comprehensive nutrients (optional - from detailed analysis)
  final double? originalOmega3;
  final double? originalOmega6;
  final double? originalSodium;
  final double? originalPotassium;
  final double? originalCalcium;
  final double? originalMagnesium;
  final double? originalIron;
  final double? originalZinc;
  final double? originalVitaminA;
  final double? originalVitaminC;
  final double? originalVitaminD;
  final double? originalVitaminE;
  final double? originalVitaminK;
  final double? originalVitaminB12;
  final double? originalFolate;
  final double? originalCholine;
  final double? originalCholesterol;

  Ingredient({
    required this.id,
    required this.name,
    required this.amount,
    required this.originalAmount,
    this.unit = 'g',
    required this.originalCalories,
    required this.originalProtein,
    required this.originalCarbs,
    required this.originalFat,
    this.originalFiber = 0,
    this.originalSugar = 0,
    this.originalSaturatedFat = 0,
    this.originalUnsaturatedFat = 0,
    this.originalOmega3,
    this.originalOmega6,
    this.originalSodium,
    this.originalPotassium,
    this.originalCalcium,
    this.originalMagnesium,
    this.originalIron,
    this.originalZinc,
    this.originalVitaminA,
    this.originalVitaminC,
    this.originalVitaminD,
    this.originalVitaminE,
    this.originalVitaminK,
    this.originalVitaminB12,
    this.originalFolate,
    this.originalCholine,
    this.originalCholesterol,
  });

  // ============================================
  // SCALE FACTOR - The core of recalculation
  // ============================================

  /// Returns the scale factor based on current amount vs original amount
  double get scaleFactor => originalAmount > 0 ? amount / originalAmount : 1.0;

  // ============================================
  // COMPUTED NUTRITIONAL VALUES (scaled)
  // ============================================

  double get calories => originalCalories * scaleFactor;
  double get protein => originalProtein * scaleFactor;
  double get carbs => originalCarbs * scaleFactor;
  double get fat => originalFat * scaleFactor;
  double get fiber => originalFiber * scaleFactor;
  double get sugar => originalSugar * scaleFactor;
  double get saturatedFat => originalSaturatedFat * scaleFactor;
  double get unsaturatedFat => originalUnsaturatedFat * scaleFactor;

  // Comprehensive nutrients (scaled, null-safe)
  double? get omega3 =>
      originalOmega3 != null ? originalOmega3! * scaleFactor : null;
  double? get omega6 =>
      originalOmega6 != null ? originalOmega6! * scaleFactor : null;
  double? get sodium =>
      originalSodium != null ? originalSodium! * scaleFactor : null;
  double? get potassium =>
      originalPotassium != null ? originalPotassium! * scaleFactor : null;
  double? get calcium =>
      originalCalcium != null ? originalCalcium! * scaleFactor : null;
  double? get magnesium =>
      originalMagnesium != null ? originalMagnesium! * scaleFactor : null;
  double? get iron => originalIron != null ? originalIron! * scaleFactor : null;
  double? get zinc => originalZinc != null ? originalZinc! * scaleFactor : null;
  double? get vitaminA =>
      originalVitaminA != null ? originalVitaminA! * scaleFactor : null;
  double? get vitaminC =>
      originalVitaminC != null ? originalVitaminC! * scaleFactor : null;
  double? get vitaminD =>
      originalVitaminD != null ? originalVitaminD! * scaleFactor : null;
  double? get vitaminE =>
      originalVitaminE != null ? originalVitaminE! * scaleFactor : null;
  double? get vitaminK =>
      originalVitaminK != null ? originalVitaminK! * scaleFactor : null;
  double? get vitaminB12 =>
      originalVitaminB12 != null ? originalVitaminB12! * scaleFactor : null;
  double? get folate =>
      originalFolate != null ? originalFolate! * scaleFactor : null;
  double? get choline =>
      originalCholine != null ? originalCholine! * scaleFactor : null;
  double? get cholesterol =>
      originalCholesterol != null ? originalCholesterol! * scaleFactor : null;

  // ============================================
  // AMOUNT MODIFICATION
  // ============================================

  /// Update the amount - this triggers recalculation via scaleFactor
  void updateAmount(double newAmount) {
    amount = newAmount.clamp(0, originalAmount * 10); // Max 10x original
  }

  /// Reset amount to original
  void resetAmount() {
    amount = originalAmount;
  }

  // ============================================
  // SLIDER BOUNDS
  // ============================================

  /// Minimum amount for slider (0 or small value)
  double get minAmount => 0;

  /// Maximum amount for slider (e.g., 3x the original)
  double get maxAmount => originalAmount * 3;

  // ============================================
  // SERIALIZATION
  // ============================================

  /// Create from Gemini JSON response
  factory Ingredient.fromGeminiJson(Map<String, dynamic> json, {String? id}) {
    try {
      // Parse quantity string like "75g" or "30 ml" to extract number and unit
      final quantityStr = json['quantity'] as String? ?? '100g';
      final parsed = _parseQuantity(quantityStr);
      
      // Ensure amount is at least 1g to avoid division by zero
      final amount = (parsed['amount'] as double) > 0 
          ? (parsed['amount'] as double) 
          : 100.0;

      return Ingredient(
        id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Unknown',
        amount: amount,
        originalAmount: amount,
        unit: parsed['unit'] as String,
        originalCalories: _safeDouble(json['calories']) ?? 0,
        originalProtein: _safeDouble(json['protein']) ?? 0,
        originalCarbs: _safeDouble(json['carbs']) ?? 0,
        originalFat: _safeDouble(json['fat']) ?? 0,
        originalFiber: _safeDouble(json['fiber']) ?? 0,
        originalSugar: _safeDouble(json['sugar']) ?? 0,
        originalSaturatedFat: _safeDouble(json['saturatedFat']) ?? 0,
        originalUnsaturatedFat: _safeDouble(json['unsaturatedFat']) ?? 0,
        // Comprehensive nutrients
        originalOmega3: _safeDouble(json['omega3']),
        originalOmega6: _safeDouble(json['omega6']),
        originalSodium: _safeDouble(json['sodium']),
        originalPotassium: _safeDouble(json['potassium']),
        originalCalcium: _safeDouble(json['calcium']),
        originalMagnesium: _safeDouble(json['magnesium']),
        originalIron: _safeDouble(json['iron']),
        originalZinc: _safeDouble(json['zinc']),
        originalVitaminA: _safeDouble(json['vitaminA']),
        originalVitaminC: _safeDouble(json['vitaminC']),
        originalVitaminD: _safeDouble(json['vitaminD']),
        originalVitaminE: _safeDouble(json['vitaminE']),
        originalVitaminK: _safeDouble(json['vitaminK']),
        originalVitaminB12: _safeDouble(json['vitaminB12']),
        originalFolate: _safeDouble(json['folate']),
        originalCholine: _safeDouble(json['choline']),
        originalCholesterol: _safeDouble(json['cholesterol']),
      );
    } catch (e) {
      // Return a default ingredient if parsing fails
      return Ingredient(
        id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Unknown',
        amount: 100.0,
        originalAmount: 100.0,
        unit: 'g',
        originalCalories: 0,
        originalProtein: 0,
        originalCarbs: 0,
        originalFat: 0,
      );
    }
  }
  
  /// Safely convert a value to double, handling null and invalid types
  static double? _safeDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }

  /// Parse quantity string like "75g" or "30 ml"
  static Map<String, dynamic> _parseQuantity(String quantity) {
    final cleaned = quantity.trim().toLowerCase();
    final regex = RegExp(r'([\d.]+)\s*(\w+)?');
    final match = regex.firstMatch(cleaned);

    if (match != null) {
      final amount = double.tryParse(match.group(1) ?? '0') ?? 0;
      final unit = match.group(2) ?? 'g';
      return {'amount': amount, 'unit': unit};
    }

    return {'amount': 0.0, 'unit': 'g'};
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'originalAmount': originalAmount,
      'unit': unit,
      'originalCalories': originalCalories,
      'originalProtein': originalProtein,
      'originalCarbs': originalCarbs,
      'originalFat': originalFat,
      'originalFiber': originalFiber,
      'originalSugar': originalSugar,
      'originalSaturatedFat': originalSaturatedFat,
      'originalUnsaturatedFat': originalUnsaturatedFat,
      // Comprehensive (only if present)
      if (originalOmega3 != null) 'originalOmega3': originalOmega3,
      if (originalOmega6 != null) 'originalOmega6': originalOmega6,
      if (originalSodium != null) 'originalSodium': originalSodium,
      if (originalPotassium != null) 'originalPotassium': originalPotassium,
      if (originalCalcium != null) 'originalCalcium': originalCalcium,
      if (originalMagnesium != null) 'originalMagnesium': originalMagnesium,
      if (originalIron != null) 'originalIron': originalIron,
      if (originalZinc != null) 'originalZinc': originalZinc,
      if (originalVitaminA != null) 'originalVitaminA': originalVitaminA,
      if (originalVitaminC != null) 'originalVitaminC': originalVitaminC,
      if (originalVitaminD != null) 'originalVitaminD': originalVitaminD,
      if (originalVitaminE != null) 'originalVitaminE': originalVitaminE,
      if (originalVitaminK != null) 'originalVitaminK': originalVitaminK,
      if (originalVitaminB12 != null) 'originalVitaminB12': originalVitaminB12,
      if (originalFolate != null) 'originalFolate': originalFolate,
      if (originalCholine != null) 'originalCholine': originalCholine,
      if (originalCholesterol != null)
        'originalCholesterol': originalCholesterol,
    };
  }

  /// Create from Firestore document
  factory Ingredient.fromFirestore(Map<String, dynamic> doc) {
    return Ingredient(
      id: doc['id'] as String,
      name: doc['name'] as String,
      amount: (doc['amount'] as num).toDouble(),
      originalAmount: (doc['originalAmount'] as num).toDouble(),
      unit: doc['unit'] as String? ?? 'g',
      originalCalories: (doc['originalCalories'] as num).toDouble(),
      originalProtein: (doc['originalProtein'] as num).toDouble(),
      originalCarbs: (doc['originalCarbs'] as num).toDouble(),
      originalFat: (doc['originalFat'] as num).toDouble(),
      originalFiber: (doc['originalFiber'] as num?)?.toDouble() ?? 0,
      originalSugar: (doc['originalSugar'] as num?)?.toDouble() ?? 0,
      originalSaturatedFat:
          (doc['originalSaturatedFat'] as num?)?.toDouble() ?? 0,
      originalUnsaturatedFat:
          (doc['originalUnsaturatedFat'] as num?)?.toDouble() ?? 0,
      originalOmega3: (doc['originalOmega3'] as num?)?.toDouble(),
      originalOmega6: (doc['originalOmega6'] as num?)?.toDouble(),
      originalSodium: (doc['originalSodium'] as num?)?.toDouble(),
      originalPotassium: (doc['originalPotassium'] as num?)?.toDouble(),
      originalCalcium: (doc['originalCalcium'] as num?)?.toDouble(),
      originalMagnesium: (doc['originalMagnesium'] as num?)?.toDouble(),
      originalIron: (doc['originalIron'] as num?)?.toDouble(),
      originalZinc: (doc['originalZinc'] as num?)?.toDouble(),
      originalVitaminA: (doc['originalVitaminA'] as num?)?.toDouble(),
      originalVitaminC: (doc['originalVitaminC'] as num?)?.toDouble(),
      originalVitaminD: (doc['originalVitaminD'] as num?)?.toDouble(),
      originalVitaminE: (doc['originalVitaminE'] as num?)?.toDouble(),
      originalVitaminK: (doc['originalVitaminK'] as num?)?.toDouble(),
      originalVitaminB12: (doc['originalVitaminB12'] as num?)?.toDouble(),
      originalFolate: (doc['originalFolate'] as num?)?.toDouble(),
      originalCholine: (doc['originalCholine'] as num?)?.toDouble(),
      originalCholesterol: (doc['originalCholesterol'] as num?)?.toDouble(),
    );
  }

  /// Create a copy with modified amount
  Ingredient copyWithAmount(double newAmount) {
    return Ingredient(
      id: id,
      name: name,
      amount: newAmount,
      originalAmount: originalAmount,
      unit: unit,
      originalCalories: originalCalories,
      originalProtein: originalProtein,
      originalCarbs: originalCarbs,
      originalFat: originalFat,
      originalFiber: originalFiber,
      originalSugar: originalSugar,
      originalSaturatedFat: originalSaturatedFat,
      originalUnsaturatedFat: originalUnsaturatedFat,
      originalOmega3: originalOmega3,
      originalOmega6: originalOmega6,
      originalSodium: originalSodium,
      originalPotassium: originalPotassium,
      originalCalcium: originalCalcium,
      originalMagnesium: originalMagnesium,
      originalIron: originalIron,
      originalZinc: originalZinc,
      originalVitaminA: originalVitaminA,
      originalVitaminC: originalVitaminC,
      originalVitaminD: originalVitaminD,
      originalVitaminE: originalVitaminE,
      originalVitaminK: originalVitaminK,
      originalVitaminB12: originalVitaminB12,
      originalFolate: originalFolate,
      originalCholine: originalCholine,
      originalCholesterol: originalCholesterol,
    );
  }

  @override
  String toString() {
    return 'Ingredient($name: ${amount.toStringAsFixed(0)}$unit, ${calories.toStringAsFixed(0)}kcal)';
  }
}
