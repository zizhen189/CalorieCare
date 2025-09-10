class WeightValidator {
  // Reasonable weight range: 20kg - 300kg
  static const double minWeight = 20.0;
  static const double maxWeight = 300.0;
  
  /// Validate if weight is within reasonable range
  /// Returns validation result and error message
  static WeightValidationResult validateWeight(double weight) {
    if (weight < minWeight) {
      return WeightValidationResult(
        isValid: false,
        errorMessage: 'Weight too low, please enter a value above ${minWeight}kg',
        suggestion: 'Please check your input, normal adult weight is usually above ${minWeight}kg',
      );
    }
    
    if (weight > maxWeight) {
      return WeightValidationResult(
        isValid: false,
        errorMessage: 'Weight too high, please enter a value below ${maxWeight}kg',
        suggestion: 'Please check your input, normal adult weight is usually below ${maxWeight}kg',
      );
    }
    
    return WeightValidationResult(
      isValid: true,
      errorMessage: '',
      suggestion: '',
    );
  }
  
  /// Validate weight string input
  static WeightValidationResult validateWeightString(String weightText) {
    if (weightText.trim().isEmpty) {
      return WeightValidationResult(
        isValid: false,
        errorMessage: 'Please enter weight',
        suggestion: 'Please enter your weight value (unit: kg)',
      );
    }
    
    final weight = double.tryParse(weightText.trim());
    if (weight == null) {
      return WeightValidationResult(
        isValid: false,
        errorMessage: 'Please enter a valid number',
        suggestion: 'Please enter weight in number format, e.g.: 65.5',
      );
    }
    
    return validateWeight(weight);
  }
  
  /// Get reasonable weight range hint
  static String getWeightRangeHint() {
    return 'Please enter weight between ${minWeight}kg - ${maxWeight}kg';
  }
  
  /// Check if weight is within reasonable range (simple check)
  static bool isWeightInRange(double weight) {
    return weight >= minWeight && weight <= maxWeight;
  }
}

class WeightValidationResult {
  final bool isValid;
  final String errorMessage;
  final String suggestion;
  
  WeightValidationResult({
    required this.isValid,
    required this.errorMessage,
    required this.suggestion,
  });
}
