import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Model
// One row on the menu galing filter.php
class MenuDish {
  final String id;
  final String name;
  final String thumb;

  MenuDish({required this.id, required this.name, required this.thumb});

  factory MenuDish.fromJson(Map<String, dynamic> json) {
    return MenuDish(
      id: json['idMeal'].toString(),
      name: json['strMeal'].toString(),
      thumb: json['strMealThumb'].toString(),
    );
  }
}

// One plate on the belt from random.php
class Plate {
  final String name;
  final String category;
  final String area;
  final String thumb;

  Plate({
    required this.name,
    required this.category,
    required this.area,
    required this.thumb,
  });

// Kapag walang category o area sa JSON, 'Unknown' ang gagamitin
  factory Plate.fromJson(Map<String, dynamic> json) {
    return Plate(
      name: json['strMeal'].toString(),
      category: (json['strCategory'] ?? 'Unknown').toString(),
      area: (json['strArea'] ?? 'Unknown').toString(),
      thumb: json['strMealThumb'].toString(),
    );
  }
}

// ine-emit ng Stream. Normal values lang ang errors, so the stream never dies.
class BeltEvent {
  final Plate? plate;
  final int plateNo;
  final String? error;

  BeltEvent.ok(this.plate, this.plateNo) : error = null;
  BeltEvent.fail(this.error) : plate = null, plateNo = 0;
}


// API service
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class KitchenApi {
  static const _base = 'https://www.themealdb.com/api/json/v1/1'; //api link
  static const _timeout = Duration(seconds: 8);

  // request + timeout + status code check + JSON decode all in one place onli
  static Future<Map<String, dynamic>> _get(String path) async {
    try {
      final response = await http
          .get(Uri.parse('$_base$path'))
          .timeout(_timeout);

 // Kapag hindi 200 ang status code may problema
      if (response.statusCode != 200) {
        throw ApiException('Kitchen error (${response.statusCode})');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on TimeoutException {
      throw ApiException('The kitchen took too long to answer.');
    } on ApiException {
      rethrow;
    } on FormatException {
      throw ApiException('The kitchen sent a messy order slip.');
    } catch (_) {
      // airplane mode, no wifi, DNS failure, etc.
      throw ApiException('Cannot reach the kitchen. Are you offline?');
    }
  }
  // Kinukuha ang buong menu (Seafood category)
  static Future<List<MenuDish>> fetchMenu() async {
    final json = await _get('/filter.php?c=Seafood');
    final list = (json['meals'] as List<dynamic>?) ?? [];
    return list
        .map((e) => MenuDish.fromJson(e as Map<String, dynamic>))
        .toList();
  }

 // Kinukuha ang isang random na plate
  static Future<Plate> fetchRandomPlate() async {
    final json = await _get('/random.php');
    final list = (json['meals'] as List<dynamic>?) ?? [];
    if (list.isEmpty) {
      throw ApiException('The chef sent an empty plate.');
    }
    return Plate.fromJson(list.first as Map<String, dynamic>);
  }

 // May bagong plate kada 5 seconds. Kapag nag-fail ang fetch, nagiging BeltEvent.fail,tapos tuloy lang ang loop, kaya hindi mapapatay ng isang error ang belt.
  static Stream<BeltEvent> belt() async* {
    var served = 0;
    while (true) {
      try {
        final plate = await fetchRandomPlate();
        served++;
        yield BeltEvent.ok(plate, served);
      } catch (e) {
        yield BeltEvent.fail(e.toString());
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }
}

// App shell 
//starting of an app
void main() => runApp(const KaitenApp());

class KaitenApp extends StatelessWidget {
  const KaitenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kaiten Kitchen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final width = mq.size.width > 480 ? 480.0 : mq.size.width;
        return ColoredBox(
          color: Colors.grey.shade300,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: mq.size.height,
              child: MediaQuery(
                data: mq.copyWith(size: Size(width, mq.size.height)),
                child: ClipRect(child: child!),
              ),
            ),
          ),
        );
      },
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'The Order' : 'The Belt'),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _index,
        children: const [OrderScreen(), BeltScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Order'),
          NavigationDestination(icon: Icon(Icons.restaurant), label: 'Belt'),
        ],
      ),
    );
  }
}

// Small helper so image problems never crash the screen
Widget _foodImage(String url, {double? width, double? height}) {
  return Image.network(
    url,
    width: width,
    height: height,
    fit: BoxFit.cover,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : SizedBox(
            width: width,
            height: height,
            child: const Center(child: CircularProgressIndicator()),
          ),
    errorBuilder: (context, error, stack) => SizedBox(
      width: width,
      height: height,
      child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 32))),
    ),
  );
}

// Opens a bottom sheet with a bigger photo when a menu item is tapped
void _showDish(BuildContext context, MenuDish dish, int orderNo) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _foodImage(dish.thumb),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                dish.name,
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Order #$orderNo  •  Seafood  •  ID ${dish.id}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// Screen 1- The Order (FutureBuilder)
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  // Created once in initState, so rebuilds do not refetch.
  late Future<List<MenuDish>> _future;

  @override
  void initState() {
    super.initState();
    _future = KitchenApi.fetchMenu();
  }

  void _reopenKitchen() {
    setState(() {
      _future = KitchenApi.fetchMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MenuDish>>(
      future: _future,
      builder: (context, snapshot) {
        // 1.waiting
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Chef is preparing the menu...'),
              ],
            ),
          );
        }

        // 2. error + retry
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔒', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  const Text(
                    'Kitchen is closed',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _reopenKitchen,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        // 3. empty
        final menu = snapshot.data ?? [];
        if (menu.isEmpty) {
          return const Center(child: Text('The menu is empty today. 🍽️'));
        }

        // 4. real data
        // thumbnail size follows the screen width (between 56 and 88)
        final thumb = (MediaQuery.of(context).size.width * 0.22).clamp(
          56.0,
          88.0,
        );

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: menu.length,
          itemBuilder: (context, i) {
            final dish = menu[i];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _foodImage(dish.thumb, width: thumb, height: thumb),
                title: Text(
                  dish.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('Order #${i + 1}  •  Seafood'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDish(context, dish, i + 1),
              ),
            );
          },
        );
      },
    );
  }
}


// Screen 2 - The Belt (StreamBuilder)
class BeltScreen extends StatefulWidget {
  const BeltScreen({super.key});

  @override
  State<BeltScreen> createState() => _BeltScreenState();
}

class _BeltScreenState extends State<BeltScreen> {
 // Isang beses lang ginagawa, kaya hindi nire-restart ang stream kapag nag-rebuild.
  late final Stream<BeltEvent> _stream = KitchenApi.belt();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BeltEvent>(
      stream: _stream,
      builder: (context, snapshot) {
        // loading: first plate has not arrived yet
        if (!snapshot.hasData) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Starting the belt...'),
              ],
            ),
          );
        }

        final event = snapshot.data!;

        // error: belt is paused but the stream is alive (retry in 5s)
        if (event.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  const Text(
                    'The belt jammed!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(event.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('Restarting in 5 seconds...'),
                ],
              ),
            ),
          );
        }

        final plate = event.plate!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Plates served: ${event.plateNo}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              // plates slide in from the right like a conveyor belt
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
                child: Card(
                  key: ValueKey(event.plateNo),
                  clipBehavior: Clip.antiAlias,
                  elevation: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: _foodImage(plate.thumb),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Text(
                              plate.name,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              alignment: WrapAlignment.center,
                              children: [
                                Chip(label: Text(plate.category)),
                                Chip(label: Text(plate.area)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Next plate in 5 seconds 🍣'),
            ],
          ),
        );
      },
    );
  }
}
