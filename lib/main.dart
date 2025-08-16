import 'dart:convert';
import 'dart:typed_data'; // Required for map icon loading
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for asset loading
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

// --- DATA MODEL ---
// Represents a single bike station.
class Station {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final int capacity;

  Station({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.capacity,
  });

  // Factory constructor to create a Station from JSON.
  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['station_id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      capacity: json['capacity'] as int,
    );
  }
}

// --- API SERVICE ---
// Fetches and parses station data from the Lyft GBFS API.
Future<List<Station>> fetchStations() async {
  // Direct API call without the unreliable CORS proxy.
  const url = 'https://gbfs.lyft.com/gbfs/1.1/bos/en/station_information.json';

  try {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> stationsJson = data['data']['stations'];
      return stationsJson.map((json) => Station.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load station data (Status code: ${response.statusCode})');
    }
  } catch (e) {
    throw Exception('Failed to fetch stations: $e');
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boston Bike Stations Dashboard',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const DashboardScreen(),
    );
  }
}

// --- MAIN DASHBOARD SCREEN ---
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<Station>> futureStations;

  @override
  void initState() {
    super.initState();
    // Fetch the data when the widget is first created.
    futureStations = fetchStations();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Boston Bike Stations Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.table_chart), text: 'Table'),
              Tab(icon: Icon(Icons.bar_chart), text: 'Graph'),
              Tab(icon: Icon(Icons.map), text: 'Map'),
            ],
          ),
        ),
        body: FutureBuilder<List<Station>>(
          future: futureStations,
          builder: (context, snapshot) {
            // Show a loading indicator while data is being fetched.
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            // Show an error message if fetching fails.
            else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            // When data is available, build the tab views.
            else if (snapshot.hasData) {
              final stations = snapshot.data!;
              return TabBarView(
                children: [
                  StationTableView(stations: stations),
                  StationGraphView(stations: stations),
                  StationMapView(stations: stations),
                ],
              );
            }
            // Fallback for any other state.
            else {
              return const Center(child: Text('No data available.'));
            }
          },
        ),
      ),
    );
  }
}

// --- TABLE VIEW WIDGET ---
class StationTableView extends StatelessWidget {
  final List<Station> stations;

  const StationTableView({super.key, required this.stations});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Station Name')),
              DataColumn(label: Text('Capacity'), numeric: true),
            ],
            rows: stations
                .map((station) => DataRow(
                      cells: [
                        DataCell(Text(station.name)),
                        DataCell(Text(station.capacity.toString())),
                      ],
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// --- GRAPH VIEW WIDGET (UPDATED) ---
class StationGraphView extends StatelessWidget {
  final List<Station> stations;

  const StationGraphView({super.key, required this.stations});

  @override
  Widget build(BuildContext context) {
    // We'll show the top 15 stations by capacity for a cleaner graph.
    final topStations = List<Station>.from(stations)
      ..sort((a, b) => b.capacity.compareTo(a.capacity));
    final displayStations = topStations.take(15).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: displayStations.first.capacity.toDouble() * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final station = displayStations[groupIndex];
                return BarTooltipItem(
                  '${station.name}\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  children: <TextSpan>[
                    TextSpan(
                      text: station.capacity.toString(),
                      style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  // FIX: Corrected SideTitleWidget constructor
                  return SideTitleWidget(
                    meta: meta,
                    space: 4.0,
                    child: Text(value.toInt().toString(),
                        style: const TextStyle(fontSize: 10)),
                  );
                },
                reservedSize: 16,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: displayStations.asMap().entries.map((entry) {
            int index = entry.key;
            Station station = entry.value;
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: station.capacity.toDouble(),
                  color: Colors.indigoAccent,
                  width: 16,
                )
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// --- MAP VIEW WIDGET ---
class StationMapView extends StatefulWidget {
  final List<Station> stations;

  const StationMapView({super.key, required this.stations});

  @override
  State<StationMapView> createState() => _StationMapViewState();
}

class _StationMapViewState extends State<StationMapView> {
  MaplibreMapController? mapController;
  String _selectedStyle = 'Positron'; // Default style

  static const satelliteStyleJson = """
  {
    "version": 8,
    "name": "ArcGIS Satellite",
    "glyphs": "https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",
    "sources": {
      "satellite-source": {
        "type": "raster",
        "tiles": [
          "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        ],
        "tileSize": 256
      }
    },
    "layers": [
      {
        "id": "satellite-layer",
        "type": "raster",
        "source": "satellite-source"
      }
    ]
  }
  """;

  Map<String, String> get _mapStyles => {
        'Positron':
            'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
        'Dark Matter':
            'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
        'Satellite':
            'data:application/json,${Uri.encodeComponent(satelliteStyleJson)}',
      };

  void _onMapCreated(MaplibreMapController controller) {
    mapController = controller;
  }

// In _StationMapViewState
  
  void _onStyleLoaded() async {
    if (mapController == null) return;

    // FIX: Removed the redundant 'assets/' prefix from the path.
    final ByteData bytes = await rootBundle.load('icons/icons8-map-pin-64.png');
    final Uint8List list = bytes.buffer.asUint8List();
    
    await mapController!.addImage('bike-icon', list);

    mapController?.clearSymbols();

    for (final station in widget.stations) {
      mapController!.addSymbol(
          SymbolOptions(
            geometry: LatLng(station.lat, station.lon),
            iconImage: 'bike-icon',
            iconSize: 0.8,
          ),
          {'name': station.name, 'capacity': station.capacity});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MaplibreMap(
          key: ValueKey(_selectedStyle),
          styleString: _mapStyles[_selectedStyle]!,
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          initialCameraPosition: const CameraPosition(
            target: LatLng(42.3601, -71.0589), // Centered on Boston
            zoom: 11.0,
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4.0,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedStyle,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedStyle = newValue;
                    });
                  }
                },
                items: _mapStyles.keys
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}