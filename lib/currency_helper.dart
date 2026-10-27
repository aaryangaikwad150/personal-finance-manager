import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config/api_key.dart';

class CurrencyHelper {
  static const Map<String, String> symbols = {'INR': '₹', 'USD': '\$', 'EUR': '€'};

  static Map<String, double>? _cachedRates;
  static DateTime? _cachedAt;

  static Future<Map<String, double>> _getRates() async {
    if (_cachedRates != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(hours: 6)) {
      return _cachedRates!;
    }
    try {
      final response = await http.get(Uri.parse(
        'https://v6.exchangerate-api.com/v6/${ApiKeys.exchangeRateApiKey}/latest/INR',
      ));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rates = Map<String, double>.from(
          (data['conversion_rates'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        );
        _cachedRates = rates;
        _cachedAt = DateTime.now();
        return rates;
      }
    } catch (e) {
      // fall through to fallback below
    }
    return _cachedRates ?? {'INR': 1.0, 'USD': 0.012, 'EUR': 0.011};
  }

  /// All amounts in Firestore are stored in INR. This converts to the display currency.
  static Future<double> convert(double amountInInr, String toCurrency) async {
    if (toCurrency == 'INR') return amountInInr;
    final rates = await _getRates();
    final rate = rates[toCurrency] ?? 1.0;
    return amountInInr * rate;
  }

  /// Converts a value the user typed in [fromCurrency] back into INR,
  /// so it can be safely stored — every amount in Firestore must be INR.
  static Future<double> toInr(double amountInCurrency, String fromCurrency) async {
    if (fromCurrency == 'INR') return amountInCurrency;
    final rates = await _getRates();
    final rate = rates[fromCurrency] ?? 1.0;
    if (rate == 0) return amountInCurrency;
    return amountInCurrency / rate;
  }

  static String symbolFor(String currency) => symbols[currency] ?? currency;

  static Future<String> format(double amountInInr, String toCurrency) async {
    final converted = await convert(amountInInr, toCurrency);
    return '${symbolFor(toCurrency)}${converted.toStringAsFixed(2)}';
  }
}