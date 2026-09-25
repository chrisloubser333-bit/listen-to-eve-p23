import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/tool_result.dart';
import 'ai_tool.dart';

/// Dedicated, provider-independent real-time weather tool for Listen to Eve.
///
/// Uses Open-Meteo Free APIs (Geocoding & Forecast):
/// - No API keys or server secrets required
/// - Works directly on mobile clients over HTTPS
/// - Provides accurate live temperatures, conditions, wind, and humidity
class WeatherTool implements AiTool {
  final http.Client _client;
  final Duration timeout;

  WeatherTool({
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  @override
  String get id => 'weather_lookup';

  @override
  String get name => 'Live Weather Lookup';

  @override
  String get description =>
      'Retrieves accurate, real-time live weather, temperatures, and forecasts without requiring private keys.';

  @override
  bool shouldTrigger(
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
  }) {
    final lower = userMessage.trim().toLowerCase();
    if (lower.isEmpty) return false;

    // Check for negative memory / casual filters
    if (lower.contains('do you remember') ||
        lower.contains('onthou jy') ||
        lower.contains('write a poem') ||
        lower.contains('skryf \'n gedig')) {
      return false;
    }

    const weatherKeywords = [
      'weather',
      'temperature',
      'forecast',
      'rain',
      'raining',
      'rainy',
      'sunny',
      'cloudy',
      'snow',
      'snowing',
      'wind',
      'windy',
      'how hot is it',
      'how cold is it',
      'is it raining',
      'is it sunny',
      'is it hot',
      'is it cold',
      // Afrikaans
      'weer',
      'weervoorspelling',
      'temperatuur',
      'reën',
      'reën dit',
      'sonnig',
      'bewolk',
      'sneeu',
      'waai die wind',
      'hoe warm is dit',
      'hoe koud is dit',
      'is dit sonnig',
      'is dit warm',
      'is dit koud',
    ];

    for (final kw in weatherKeywords) {
      final regex = RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false);
      if (regex.hasMatch(lower)) {
        return true;
      }
    }

    return false;
  }

  /// Extracts location from natural weather queries (e.g. "What is the weather in Cape Town?" -> "Cape Town")
  String extractLocation(String userMessage) {
    final trimmed = userMessage.trim();

    final locationPatterns = [
      // English
      RegExp(r'(?:weather|forecast|temperature|how is it|what is it like)\s+(?:in|for|at|around)\s+([a-zA-Z\s\-\,\.]+)', caseSensitive: false),
      RegExp(r'(?:will it|is it going to|is it)\s+(?:rain|snow|be sunny|be hot|be cold)\s+(?:today\s+|tomorrow\s+|now\s+)?(?:in|at|around|for)\s+([a-zA-Z\s\-\,\.]+)', caseSensitive: false),
      RegExp(r'(?:in|for|at)\s+([a-zA-Z\s\-\,\.]+)\s+(?:weather|forecast|temperature)', caseSensitive: false),
      RegExp(r"what(?:'s| is) the weather (?:like )?in ([a-zA-Z\s\-\,\.]+)", caseSensitive: false),
      RegExp(r"what(?:'s| is) the temperature (?:like )?in ([a-zA-Z\s\-\,\.]+)", caseSensitive: false),
      RegExp(r'^([a-zA-Z\s\-\,\.]+)\s+(?:weather|forecast|temperature)', caseSensitive: false),
      RegExp(r'(?:weather|forecast|temperature)\s+([a-zA-Z\s\-\,\.]+)', caseSensitive: false),
      // Afrikaans
      RegExp(r'(?:weer|weervoorspelling|temperatuur)\s+(?:in|vir|by)\s+([a-zA-Z\s\-\,\.]+)', caseSensitive: false),
      RegExp(r'(?:gaan dit|sal dit)\s+(?:reën|sneeu)\s+(?:vandag\s+|môre\s+|nou\s+)?(?:in|by|vir)\s+([a-zA-Z\s\-\,\.]+)', caseSensitive: false),
      RegExp(r'(?:in|vir|by)\s+([a-zA-Z\s\-\,\.]+)\s+(?:se weer|weer)', caseSensitive: false),
      RegExp(r'hoe lyk die weer in ([a-zA-Z\s\-\,\.]+)', caseSensitive: false),
      RegExp(r'^([a-zA-Z\s\-\,\.]+)\s+(?:se weer|weer|weervoorspelling)', caseSensitive: false),
    ];

    for (final pattern in locationPatterns) {
      final match = pattern.firstMatch(trimmed);
      if (match != null && match.groupCount >= 1) {
        var loc = match.group(1)?.trim() ?? '';
        // Remove trailing punctuation and temporal indicators
        loc = loc.replaceAll(RegExp(r'[\?\.!\s]+$'), '').trim();
        loc = loc.replaceAll(
          RegExp(
            r'\b(today|tonight|now|right now|currently|this week|this afternoon|this morning|tomorrow|vandag|vanaand|nou|tans|môre|vanoggend|vanmiddag)\b',
            caseSensitive: false,
          ),
          '',
        ).trim();
        // Clean leading/trailing prepositions or punctuation left over
        loc = loc.replaceAll(RegExp(r'^(?:in|for|at|around|by|vir)\s+', caseSensitive: false), '').trim();
        if (loc.isNotEmpty && loc.length > 1) {
          return loc;
        }
      }
    }

    // Default location if none mentioned in standalone query
    return 'Cape Town';
  }

  @override
  Future<ToolResult?> execute(
    String userMessage, {
    Map<String, dynamic>? parameters,
  }) async {
    final location = extractLocation(userMessage);
    debugPrint('[WeatherTool] Extracted location: "$location" from "$userMessage"');

    try {
      // 1. Geocoding lookup via Open-Meteo Geocoding API
      final geoUri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(location)}&count=1&language=en&format=json',
      );

      final geoResponse = await _client.get(geoUri).timeout(const Duration(seconds: 4));
      if (geoResponse.statusCode != 200) {
        debugPrint('[WeatherTool] Geocoding HTTP error: ${geoResponse.statusCode}');
        return null;
      }

      final geoData = jsonDecode(geoResponse.body) as Map<String, dynamic>;
      final results = geoData['results'] as List?;
      if (results == null || results.isEmpty) {
        debugPrint('[WeatherTool] No coordinates found for location: "$location"');
        return null;
      }

      final firstGeo = results.first as Map<String, dynamic>;
      final lat = firstGeo['latitude'] as num;
      final lon = firstGeo['longitude'] as num;
      final resolvedName = firstGeo['name'] as String? ?? location;
      final country = firstGeo['country'] as String? ?? '';
      final admin1 = firstGeo['admin1'] as String? ?? '';

      final locationTitle = country.isNotEmpty
          ? (admin1.isNotEmpty && admin1 != resolvedName
              ? '$resolvedName, $admin1, $country'
              : '$resolvedName, $country')
          : resolvedName;

      // 2. Fetch live forecast and current metrics
      final forecastUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m&timezone=auto',
      );

      final forecastResponse = await _client.get(forecastUri).timeout(const Duration(seconds: 4));
      if (forecastResponse.statusCode != 200) {
        debugPrint('[WeatherTool] Forecast HTTP error: ${forecastResponse.statusCode}');
        return null;
      }

      final forecastData = jsonDecode(forecastResponse.body) as Map<String, dynamic>;
      final current = forecastData['current'] as Map<String, dynamic>?;
      if (current == null) return null;

      final temp = current['temperature_2m'] ?? 0;
      final feelsLike = current['apparent_temperature'] ?? temp;
      final humidity = current['relative_humidity_2m'] ?? 0;
      final precip = current['precipitation'] ?? 0;
      final wind = current['wind_speed_10m'] ?? 0;
      final weatherCode = current['weather_code'] as int? ?? 0;

      final conditionDesc = _decodeWmoWeatherCode(weatherCode);

      final buffer = StringBuffer();
      buffer.writeln('Live Weather Report for $locationTitle:');
      buffer.writeln('- Current Temperature: $temp°C (Feels like $feelsLike°C)');
      buffer.writeln('- Condition: $conditionDesc');
      buffer.writeln('- Relative Humidity: $humidity%');
      buffer.writeln('- Wind Speed: $wind km/h');
      buffer.writeln('- Precipitation: $precip mm');

      return ToolResult(
        toolId: id,
        title: 'Live Weather for $locationTitle',
        snippet: buffer.toString().trim(),
        url: 'https://open-meteo.com',
        retrievedAt: DateTime.now(),
        confidence: 0.98,
        metadata: {
          'location': locationTitle,
          'temperature_celsius': temp,
          'condition': conditionDesc,
          'humidity': humidity,
          'wind_kmh': wind,
        },
      );
    } catch (e, stack) {
      debugPrint('[WeatherTool] Execution failed: $e');
      debugPrint(stack.toString());
      // Return null so IntelligenceOrchestrator cleanly falls back to WebSearchTool
      return null;
    }
  }

  String _decodeWmoWeatherCode(int code) {
    switch (code) {
      case 0:
        return 'Clear sky / Sunny';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
        return 'Foggy';
      case 48:
        return 'Depositing rime fog';
      case 51:
        return 'Light drizzle';
      case 53:
        return 'Moderate drizzle';
      case 55:
        return 'Dense drizzle';
      case 61:
        return 'Slight rain';
      case 63:
        return 'Moderate rain';
      case 65:
        return 'Heavy rain';
      case 71:
        return 'Slight snow fall';
      case 73:
        return 'Moderate snow fall';
      case 75:
        return 'Heavy snow fall';
      case 80:
        return 'Slight rain showers';
      case 81:
        return 'Moderate rain showers';
      case 82:
        return 'Violent rain showers';
      case 95:
        return 'Thunderstorm';
      case 96:
      case 99:
        return 'Thunderstorm with hail';
      default:
        return 'Partly cloudy / Clear';
    }
  }
}
