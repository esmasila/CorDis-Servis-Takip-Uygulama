import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/stop_model.dart';

/// Unified Route Optimization Service
/// This service ensures that both driver and passenger panels always get the most efficient route
/// by using advanced optimization algorithms and Google Maps API
class UnifiedRouteOptimizationService {
  static const String _googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ',
  );

  static const double _earthRadius = 6371000; // meters

  // Cache for consistent results across panels
  static final Map<String, List<Map<String, dynamic>>> _routeCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheValidity = Duration(minutes: 5);

  /// Main optimization method that always returns the most efficient route
  /// Uses Google Maps API with fallback to advanced local algorithms
  /// Ensures consistent results across driver and passenger panels
  static Future<List<Map<String, dynamic>>> optimizeRoute({
    required Map<String, double> driverLocation,
    required List<Map<String, dynamic>> stops,
    bool useGoogleApi = true,
    String? cacheKey,
  }) async {
    if (stops.isEmpty) return stops;
    if (stops.length == 1) return stops;

    // Generate cache key if not provided
    final effectiveCacheKey =
        cacheKey ?? _generateCacheKey(driverLocation, stops);

    // Check cache first for consistency
    if (_routeCache.containsKey(effectiveCacheKey)) {
      final cachedTimestamp = _cacheTimestamps[effectiveCacheKey];
      if (cachedTimestamp != null &&
          DateTime.now().difference(cachedTimestamp) < _cacheValidity) {
        print(
            '[UnifiedRouteOptimization] Cache\'den tutarlı rota alındı: ${_routeCache[effectiveCacheKey]!.length} durak');
        return List.from(_routeCache[effectiveCacheKey]!);
      }
    }

    try {
      if (useGoogleApi) {
        print(
            '[UnifiedRouteOptimization] Google Maps API ile rota optimizasyonu başlatılıyor...');
        final googleOptimized = await _optimizeWithGoogleMapsAPI(
          driverLocation: driverLocation,
          stops: stops,
        );
        if (googleOptimized.isNotEmpty) {
          print(
              '[UnifiedRouteOptimization] Google Maps API optimizasyonu başarılı: ${googleOptimized.length} durak');
          final result = _addOrderAndMetadata(googleOptimized);
          _cacheRoute(effectiveCacheKey, result);
          return result;
        }
      }
    } catch (e) {
      print('[UnifiedRouteOptimization] Google Maps API hatası: $e');
    }

    print(
        '[UnifiedRouteOptimization] Yerel algoritma ile rota optimizasyonu başlatılıyor...');
    final localOptimized = await _optimizeWithLocalAlgorithm(
      driverLocation: driverLocation,
      stops: stops,
    );

    final result = _addOrderAndMetadata(localOptimized);
    _cacheRoute(effectiveCacheKey, result);
    return result;
  }

  /// Generate a unique cache key for the route optimization
  static String _generateCacheKey(
      Map<String, double> driverLocation, List<Map<String, dynamic>> stops) {
    final locationHash =
        '${driverLocation['latitude']?.toStringAsFixed(6)}_${driverLocation['longitude']?.toStringAsFixed(6)}';
    final stopsHash = stops
        .map((s) =>
            '${s['latitude']?.toStringAsFixed(6)}_${s['longitude']?.toStringAsFixed(6)}')
        .join('|');
    return '${locationHash}_${stops.length}_${stopsHash.hashCode}';
  }

  /// Cache the optimized route for consistency
  static void _cacheRoute(String cacheKey, List<Map<String, dynamic>> route) {
    _routeCache[cacheKey] = List.from(route);
    _cacheTimestamps[cacheKey] = DateTime.now();
    print('[UnifiedRouteOptimization] Rota cache\'lendi: $cacheKey');
  }

  /// Clear expired cache entries
  static void _clearExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheValidity) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _routeCache.remove(key);
      _cacheTimestamps.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      print(
          '[UnifiedRouteOptimization] ${expiredKeys.length} cache girişi temizlendi');
    }
  }

  /// Get cached route if available and valid
  static List<Map<String, dynamic>>? getCachedRoute(String cacheKey) {
    _clearExpiredCache();

    if (_routeCache.containsKey(cacheKey)) {
      final cachedTimestamp = _cacheTimestamps[cacheKey];
      if (cachedTimestamp != null &&
          DateTime.now().difference(cachedTimestamp) < _cacheValidity) {
        return List.from(_routeCache[cacheKey]!);
      }
    }
    return null;
  }

  /// Get or create cached route - ensures consistency between panels
  static Future<List<Map<String, dynamic>>> getOrCreateCachedRoute({
    required String cacheKey,
    required Map<String, double> driverLocation,
    required List<Map<String, dynamic>> stops,
    bool useGoogleApi = true,
  }) async {
    // First check if we have a valid cached route
    final cachedRoute = getCachedRoute(cacheKey);
    if (cachedRoute != null) {
      print(
          '[UnifiedRouteOptimization] Cache\'den tutarlı rota alındı: $cacheKey');
      return cachedRoute;
    }

    // If no cached route exists, create one and cache it
    print(
        '[UnifiedRouteOptimization] Cache\'de rota bulunamadı, yeni rota oluşturuluyor: $cacheKey');
    final optimizedRoute = await optimizeRoute(
      driverLocation: driverLocation,
      stops: stops,
      useGoogleApi: useGoogleApi,
      cacheKey: cacheKey,
    );

    // Cache the result for future use
    if (optimizedRoute.isNotEmpty) {
      _cacheRoute(cacheKey, optimizedRoute);
      print('[UnifiedRouteOptimization] Yeni rota cache\'lendi: $cacheKey');
    }

    return optimizedRoute;
  }

  /// Force clear all cache (useful for testing or when routes need to be recalculated)
  static void clearAllCache() {
    _routeCache.clear();
    _cacheTimestamps.clear();
    print('[UnifiedRouteOptimization] Tüm cache temizlendi');
  }

  /// Clear cache for a specific key (useful for debugging)
  static void clearCacheForKey(String cacheKey) {
    if (_routeCache.containsKey(cacheKey)) {
      _routeCache.remove(cacheKey);
      _cacheTimestamps.remove(cacheKey);
      print('[UnifiedRouteOptimization] Cache temizlendi: $cacheKey');
    } else {
      print('[UnifiedRouteOptimization] Cache key bulunamadı: $cacheKey');
    }
  }

  /// Get cache details for a specific key (useful for debugging)
  static Map<String, dynamic>? getCacheDetailsForKey(String cacheKey) {
    if (_routeCache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      final route = _routeCache[cacheKey];
      return {
        'cacheKey': cacheKey,
        'timestamp': timestamp?.toIso8601String(),
        'age': timestamp != null
            ? DateTime.now().difference(timestamp).inSeconds
            : null,
        'routeLength': route?.length,
        'isValid': timestamp != null &&
            DateTime.now().difference(timestamp) < _cacheValidity,
      };
    }
    return null;
  }

  /// Cache'e rota yazar (external servisler için)
  static void cacheRoute(
      String cacheKey, List<Map<String, dynamic>> waypoints) {
    _routeCache[cacheKey] = waypoints;
    _cacheTimestamps[cacheKey] = DateTime.now();
    print(
        '[UnifiedRouteOptimization] Rota cache\'e yazıldı: $cacheKey (${waypoints.length} durak)');
  }

  /// Get cache statistics for monitoring
  static Map<String, dynamic> getCacheStatistics() {
    _clearExpiredCache();
    return {
      'cacheSize': _routeCache.length,
      'timestampCount': _cacheTimestamps.length,
      'cacheValidityMinutes': _cacheValidity.inMinutes,
    };
  }

  /// Optimize route using Google Maps Directions API with waypoints
  static Future<List<Map<String, dynamic>>> _optimizeWithGoogleMapsAPI({
    required Map<String, double> driverLocation,
    required List<Map<String, dynamic>> stops,
  }) async {
    try {
      if (stops.length > 23) {
        print(
            '[UnifiedRouteOptimization] Durak sayısı 23\'ü aşıyor, ilk 23 durak optimize edilecek');
        stops = stops.take(23).toList();
      }

      final origin =
          '${driverLocation['latitude']},${driverLocation['longitude']}';
      final destination =
          '${stops.last['latitude']},${stops.last['longitude']}';

      final waypoints = stops
          .take(stops.length - 1)
          .map((stop) => '${stop['latitude']},${stop['longitude']}')
          .join('|');

      final url =
          Uri.parse('https://maps.googleapis.com/maps/api/directions/json'
              '?origin=$origin'
              '&destination=$destination'
              '&waypoints=optimize:true|$waypoints'
              '&key=$_googleMapsApiKey'
              '&mode=driving'
              '&language=tr'
              '&units=metric'
              '&avoid=tolls'
              '&traffic_model=best_guess');

      final response = await http.get(url).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('Google Maps API timeout'),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final waypointOrder = route['waypoint_order'] as List<int>?;

          if (waypointOrder != null && waypointOrder.isNotEmpty) {
            final optimizedStops = <Map<String, dynamic>>[];

            // Add optimized waypoints in order
            for (final index in waypointOrder) {
              if (index >= 0 && index < stops.length - 1) {
                optimizedStops.add(stops[index]);
              }
            }

            // Add destination
            optimizedStops.add(stops.last);

            // Add route metadata
            final legs = route['legs'] as List;
            double totalDistance = 0;
            int totalDuration = 0;

            for (final leg in legs) {
              totalDistance += (leg['distance']['value'] as int).toDouble();
              totalDuration += (leg['duration']['value'] as int);
            }

            // Add metadata to each stop
            for (final stop in optimizedStops) {
              stop['totalRouteDistance'] =
                  totalDistance / 1000; // Convert to km
              stop['totalRouteDuration'] =
                  totalDuration / 60; // Convert to minutes
              stop['optimizationMethod'] = 'google_maps_api';
            }

            print(
                '[UnifiedRouteOptimization] Google Maps API ile ${optimizedStops.length} durak optimize edildi');
            print(
                '[UnifiedRouteOptimization] Toplam mesafe: ${(totalDistance / 1000).toStringAsFixed(2)} km');
            print(
                '[UnifiedRouteOptimization] Toplam süre: ${(totalDuration / 60).round()} dakika');

            return optimizedStops;
          }
        }
      }

      print(
          '[UnifiedRouteOptimization] Google Maps API\'den geçerli yanıt alınamadı');
      return [];
    } catch (e) {
      print('[UnifiedRouteOptimization] Google Maps API hatası: $e');
      return [];
    }
  }

  /// Advanced local optimization algorithm using multiple strategies
  static Future<List<Map<String, dynamic>>> _optimizeWithLocalAlgorithm({
    required Map<String, double> driverLocation,
    required List<Map<String, dynamic>> stops,
  }) async {
    try {
      print(
          '[UnifiedRouteOptimization] Gelişmiş yerel algoritma başlatılıyor...');

      // Strategy 1: Nearest Neighbor with 2-opt optimization
      final nearestNeighborRoute = await _nearestNeighborWith2Opt(
        driverLocation: driverLocation,
        stops: stops,
      );

      // Strategy 2: Genetic Algorithm (for larger routes)
      List<Map<String, dynamic>> geneticRoute = [];
      if (stops.length > 5) {
        geneticRoute = await _geneticAlgorithmOptimization(
          driverLocation: driverLocation,
          stops: stops,
        );
      }

      // Strategy 3: Ant Colony Optimization (for medium routes)
      List<Map<String, dynamic>> antColonyRoute = [];
      if (stops.length > 3 && stops.length <= 10) {
        antColonyRoute = await _antColonyOptimization(
          driverLocation: driverLocation,
          stops: stops,
        );
      }

      // Compare all strategies and select the best
      final routes = <List<Map<String, dynamic>>>[];
      if (nearestNeighborRoute.isNotEmpty) routes.add(nearestNeighborRoute);
      if (geneticRoute.isNotEmpty) routes.add(geneticRoute);
      if (antColonyRoute.isNotEmpty) routes.add(antColonyRoute);

      if (routes.isEmpty) {
        print(
            '[UnifiedRouteOptimization] Hiçbir algoritma başarılı olmadı, basit sıralama kullanılıyor');
        return _simpleDistanceSort(driverLocation, stops);
      }

      // Find the best route by calculating total distance
      double bestDistance = double.infinity;
      List<Map<String, dynamic>> bestRoute = routes.first;

      for (final route in routes) {
        final totalDistance = _calculateTotalRouteDistance(route);
        if (totalDistance < bestDistance) {
          bestDistance = totalDistance;
          bestRoute = route;
        }
      }

      // Add metadata
      for (final stop in bestRoute) {
        stop['totalRouteDistance'] = bestDistance;
        stop['optimizationMethod'] = 'local_advanced_algorithm';
      }

      print(
          '[UnifiedRouteOptimization] En iyi yerel algoritma seçildi: ${bestDistance.toStringAsFixed(2)} km');
      return bestRoute;
    } catch (e) {
      print('[UnifiedRouteOptimization] Yerel algoritma hatası: $e');
      return _simpleDistanceSort(driverLocation, stops);
    }
  }

  /// Nearest Neighbor with 2-opt optimization
  static Future<List<Map<String, dynamic>>> _nearestNeighborWith2Opt({
    required Map<String, double> driverLocation,
    required List<Map<String, dynamic>> stops,
  }) async {
    try {
      final stopsCopy = List<Map<String, dynamic>>.from(stops);
      final optimizedRoute = <Map<String, dynamic>>[];

      // Start from driver location
      Map<String, dynamic> currentLocation =
          Map<String, dynamic>.from(driverLocation);
      currentLocation['latitude'] = driverLocation['latitude'];
      currentLocation['longitude'] = driverLocation['longitude'];

      while (stopsCopy.isNotEmpty) {
        // Find nearest stop
        double minDistance = double.infinity;
        int nearestIndex = 0;

        for (int i = 0; i < stopsCopy.length; i++) {
          final distance = _calculateDistance(
            currentLocation['latitude'],
            currentLocation['longitude'],
            stopsCopy[i]['latitude']?.toDouble() ?? 0.0,
            stopsCopy[i]['longitude']?.toDouble() ?? 0.0,
          );

          if (distance < minDistance) {
            minDistance = distance;
            nearestIndex = i;
          }
        }

        // Add nearest stop to route
        final nearestStop = stopsCopy.removeAt(nearestIndex);
        optimizedRoute.add(nearestStop);

        // Update current location
        currentLocation['latitude'] =
            nearestStop['latitude']?.toDouble() ?? 0.0;
        currentLocation['longitude'] =
            nearestStop['longitude']?.toDouble() ?? 0.0;
      }

      // Apply 2-opt optimization
      final optimized2Opt = _apply2OptOptimization(optimizedRoute);

      return optimized2Opt;
    } catch (e) {
      print('[UnifiedRouteOptimization] Nearest Neighbor hatası: $e');
      return [];
    }
  }

  /// Apply 2-opt optimization to improve route
  static List<Map<String, dynamic>> _apply2OptOptimization(
      List<Map<String, dynamic>> route) {
    if (route.length < 4) return route;

    bool improved = true;
    List<Map<String, dynamic>> bestRoute = List.from(route);
    double bestDistance = _calculateTotalRouteDistance(bestRoute);

    while (improved) {
      improved = false;

      for (int i = 1; i < route.length - 2; i++) {
        for (int j = i + 1; j < route.length; j++) {
          if (j - i == 1) continue;

          final newRoute = _twoOptSwap(bestRoute, i, j);
          final newDistance = _calculateTotalRouteDistance(newRoute);

          if (newDistance < bestDistance) {
            bestRoute = newRoute;
            bestDistance = newDistance;
            improved = true;
          }
        }
      }
    }

    return bestRoute;
  }

  /// Perform 2-opt swap operation
  static List<Map<String, dynamic>> _twoOptSwap(
      List<Map<String, dynamic>> route, int i, int j) {
    final newRoute = <Map<String, dynamic>>[];

    // Add stops before i
    for (int k = 0; k <= i - 1; k++) {
      newRoute.add(route[k]);
    }

    // Add stops from j to i in reverse order
    for (int k = j; k >= i; k--) {
      newRoute.add(route[k]);
    }

    // Add remaining stops
    for (int k = j + 1; k < route.length; k++) {
      newRoute.add(route[k]);
    }

    return newRoute;
  }

  /// Genetic Algorithm optimization for larger routes
  static Future<List<Map<String, dynamic>>> _geneticAlgorithmOptimization({
    required Map<String, double> driverLocation,
    required List<Map<String, dynamic>> stops,
  }) async {
    try {
      if (stops.length < 6) return [];

      const int populationSize = 50;
      const int generations = 100;
      const double mutationRate = 0.1;

      // Initialize population
      List<List<int>> population = [];
      for (int i = 0; i < populationSize; i++) {
        final individual = List<int>.generate(stops.length, (index) => index);
        individual.shuffle();
        population.add(individual);
      }

      // Evolution
      for (int generation = 0; generation < generations; generation++) {
        // Calculate fitness for each individual
        final fitness = <double>[];
        for (final individual in population) {
          fitness.add(_calculateFitness(individual, stops));
        }

        // Selection and crossover
        final newPopulation = <List<int>>[];
        for (int i = 0; i < populationSize; i++) {
          final parent1 = _tournamentSelection(population, fitness);
          final parent2 = _tournamentSelection(population, fitness);
          final child = _crossover(parent1, parent2);

          // Mutation
          if (Random().nextDouble() < mutationRate) {
            _mutate(child);
          }

          newPopulation.add(child);
        }

        population = newPopulation;
      }

      // Find best individual
      double bestFitness = double.infinity;
      List<int> bestIndividual = population.first;

      for (int i = 0; i < population.length; i++) {
        final fitness = _calculateFitness(population[i], stops);
        if (fitness < bestFitness) {
          bestFitness = fitness;
          bestIndividual = population[i];
        }
      }

      // Convert to route
      final optimizedRoute = <Map<String, dynamic>>[];
      for (final index in bestIndividual) {
        optimizedRoute.add(stops[index]);
      }

      return optimizedRoute;
    } catch (e) {
      print('[UnifiedRouteOptimization] Genetic Algorithm hatası: $e');
      return [];
    }
  }

  /// Ant Colony Optimization for medium routes
  static Future<List<Map<String, dynamic>>> _antColonyOptimization({
    required Map<String, double> driverLocation,
    required List<Map<String, dynamic>> stops,
  }) async {
    try {
      if (stops.length < 4) return [];

      const int antCount = 30;
      const int iterations = 50;
      const double evaporationRate = 0.1;
      const double alpha = 1.0; // Pheromone importance
      const double beta = 2.0; // Distance importance

      // Initialize pheromone matrix
      final pheromone = List.generate(
        stops.length,
        (i) => List.generate(stops.length, (j) => 1.0),
      );

      List<int> bestRoute = [];
      double bestDistance = double.infinity;

      for (int iteration = 0; iteration < iterations; iteration++) {
        // Each ant builds a route
        for (int ant = 0; ant < antCount; ant++) {
          final route = _buildAntRoute(stops, pheromone, alpha, beta);
          final distance = _calculateRouteDistance(route, stops);

          if (distance < bestDistance) {
            bestDistance = distance;
            bestRoute = List.from(route);
          }
        }

        // Evaporate pheromones
        for (int i = 0; i < stops.length; i++) {
          for (int j = 0; j < stops.length; j++) {
            pheromone[i][j] *= (1 - evaporationRate);
          }
        }

        // Deposit pheromones on best route
        for (int i = 0; i < bestRoute.length - 1; i++) {
          final from = bestRoute[i];
          final to = bestRoute[i + 1];
          pheromone[from][to] += 1.0 / bestDistance;
        }
      }

      // Convert to route
      final optimizedRoute = <Map<String, dynamic>>[];
      for (final index in bestRoute) {
        optimizedRoute.add(stops[index]);
      }

      return optimizedRoute;
    } catch (e) {
      print('[UnifiedRouteOptimization] Ant Colony hatası: $e');
      return [];
    }
  }

  /// Build route for a single ant
  static List<int> _buildAntRoute(
    List<Map<String, dynamic>> stops,
    List<List<double>> pheromone,
    double alpha,
    double beta,
  ) {
    final route = <int>[];
    final unvisited = List<int>.generate(stops.length, (i) => i);

    // Start from random position
    int current = unvisited.removeAt(Random().nextInt(unvisited.length));
    route.add(current);

    while (unvisited.isNotEmpty) {
      // Calculate probabilities for next stop
      final probabilities = <double>[];
      double totalProbability = 0.0;

      for (final next in unvisited) {
        final pheromoneLevel = pheromone[current][next];
        final distance = _calculateDistance(
          stops[current]['latitude']?.toDouble() ?? 0.0,
          stops[current]['longitude']?.toDouble() ?? 0.0,
          stops[next]['latitude']?.toDouble() ?? 0.0,
          stops[next]['longitude']?.toDouble() ?? 0.0,
        );

        final probability =
            pow(pheromoneLevel, alpha) * pow(1.0 / distance, beta).toDouble();
        probabilities.add(probability);
        totalProbability += probability;
      }

      // Select next stop based on probabilities
      double random = Random().nextDouble() * totalProbability;
      int selectedIndex = 0;

      for (int i = 0; i < probabilities.length; i++) {
        random -= probabilities[i];
        if (random <= 0) {
          selectedIndex = i;
          break;
        }
      }

      final next = unvisited.removeAt(selectedIndex);
      route.add(next);
      current = next;
    }

    return route;
  }

  /// Calculate fitness for genetic algorithm
  static double _calculateFitness(
      List<int> individual, List<Map<String, dynamic>> stops) {
    double totalDistance = 0.0;

    for (int i = 0; i < individual.length - 1; i++) {
      final from = stops[individual[i]];
      final to = stops[individual[i + 1]];

      totalDistance += _calculateDistance(
        from['latitude']?.toDouble() ?? 0.0,
        from['longitude']?.toDouble() ?? 0.0,
        to['latitude']?.toDouble() ?? 0.0,
        to['longitude']?.toDouble() ?? 0.0,
      );
    }

    return totalDistance;
  }

  /// Tournament selection for genetic algorithm
  static List<int> _tournamentSelection(
      List<List<int>> population, List<double> fitness) {
    const int tournamentSize = 3;
    final random = Random();

    int bestIndex = random.nextInt(population.length);
    double bestFitness = fitness[bestIndex];

    for (int i = 1; i < tournamentSize; i++) {
      final candidateIndex = random.nextInt(population.length);
      if (fitness[candidateIndex] < bestFitness) {
        bestIndex = candidateIndex;
        bestFitness = fitness[candidateIndex];
      }
    }

    return List.from(population[bestIndex]);
  }

  /// Crossover operation for genetic algorithm
  static List<int> _crossover(List<int> parent1, List<int> parent2) {
    final child = List<int>.filled(parent1.length, -1);
    final random = Random();

    // Order Crossover (OX)
    int start = random.nextInt(parent1.length);
    int end = random.nextInt(parent1.length);

    if (start > end) {
      final temp = start;
      start = end;
      end = temp;
    }

    // Copy segment from parent1
    for (int i = start; i <= end; i++) {
      child[i] = parent1[i];
    }

    // Fill remaining positions from parent2
    int parent2Index = 0;
    for (int i = 0; i < child.length; i++) {
      if (child[i] == -1) {
        while (child.contains(parent2[parent2Index])) {
          parent2Index++;
        }
        child[i] = parent2[parent2Index];
        parent2Index++;
      }
    }

    return child;
  }

  /// Mutation operation for genetic algorithm
  static void _mutate(List<int> individual) {
    final random = Random();

    // Swap mutation
    final i = random.nextInt(individual.length);
    final j = random.nextInt(individual.length);

    if (i != j) {
      final temp = individual[i];
      individual[i] = individual[j];
      individual[j] = temp;
    }
  }

  /// Simple distance-based sorting as fallback
  static List<Map<String, dynamic>> _simpleDistanceSort(
    Map<String, double> driverLocation,
    List<Map<String, dynamic>> stops,
  ) {
    final sortedStops = List<Map<String, dynamic>>.from(stops);

    sortedStops.sort((a, b) {
      final distanceA = _calculateDistance(
        driverLocation['latitude']!,
        driverLocation['longitude']!,
        a['latitude']?.toDouble() ?? 0.0,
        a['longitude']?.toDouble() ?? 0.0,
      );

      final distanceB = _calculateDistance(
        driverLocation['latitude']!,
        driverLocation['longitude']!,
        b['latitude']?.toDouble() ?? 0.0,
        b['longitude']?.toDouble() ?? 0.0,
      );

      return distanceA.compareTo(distanceB);
    });

    return sortedStops;
  }

  /// Calculate total route distance
  static double _calculateTotalRouteDistance(List<Map<String, dynamic>> route) {
    if (route.length < 2) return 0.0;

    double totalDistance = 0.0;

    for (int i = 0; i < route.length - 1; i++) {
      totalDistance += _calculateDistance(
        route[i]['latitude']?.toDouble() ?? 0.0,
        route[i]['longitude']?.toDouble() ?? 0.0,
        route[i + 1]['latitude']?.toDouble() ?? 0.0,
        route[i + 1]['longitude']?.toDouble() ?? 0.0,
      );
    }

    return totalDistance;
  }

  /// Calculate distance between two points
  static double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadius * c / 1000; // Convert to kilometers
  }

  /// Convert degrees to radians
  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  /// Calculate route distance for ant colony
  static double _calculateRouteDistance(
      List<int> route, List<Map<String, dynamic>> stops) {
    if (route.length < 2) return 0.0;

    double totalDistance = 0.0;

    for (int i = 0; i < route.length - 1; i++) {
      totalDistance += _calculateDistance(
        stops[route[i]]['latitude']?.toDouble() ?? 0.0,
        stops[route[i]]['longitude']?.toDouble() ?? 0.0,
        stops[route[i + 1]]['latitude']?.toDouble() ?? 0.0,
        stops[route[i + 1]]['longitude']?.toDouble() ?? 0.0,
      );
    }

    return totalDistance;
  }

  /// Add order and metadata to stops
  static List<Map<String, dynamic>> _addOrderAndMetadata(
      List<Map<String, dynamic>> stops) {
    for (int i = 0; i < stops.length; i++) {
      stops[i]['order'] = i + 1;
      stops[i]['optimizedAt'] = DateTime.now().toIso8601String();
    }
    return stops;
  }

  /// Get route statistics
  static Map<String, dynamic> getRouteStatistics(
      List<Map<String, dynamic>> route) {
    if (route.isEmpty) {
      return {
        'totalDistance': 0.0,
        'totalDuration': 0,
        'stopCount': 0,
        'optimizationMethod': 'none',
      };
    }

    final totalDistance = route.first['totalRouteDistance'] ?? 0.0;
    final totalDuration = route.first['totalRouteDuration'] ?? 0;
    final optimizationMethod = route.first['optimizationMethod'] ?? 'unknown';

    return {
      'totalDistance': totalDistance,
      'totalDuration': totalDuration,
      'stopCount': route.length,
      'optimizationMethod': optimizationMethod,
      'averageStopDistance':
          route.length > 1 ? totalDistance / (route.length - 1) : 0.0,
    };
  }
}
