import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'dart:math';

// --- DATA SOURCES ---
const String stationInfoUrl = 'https://gbfs.lyft.com/gbfs/1.1/bos/en/station_information.json';
const String stationStatusUrl = 'https://gbfs.lyft.com/gbfs/1.1/bos/en/station_status.json';

// --- MODELS ---

// Model for a single view's configuration
class ViewConfig {
  final String id;
  String title;
  ViewType type;
  String dataSourceUrl;
  Map<String, dynamic> settings;

  ViewConfig({
    required this.id,
    this.title = 'New View',
    this.type = ViewType.table,
    this.dataSourceUrl = stationInfoUrl,
    this.settings = const {},
  });
}

// Enum for the different types of views available
enum ViewType { table, graph, map }

// --- STATE MANAGEMENT ---

class DashboardState with ChangeNotifier {
  int _gridColumns = 1;
  final List<ViewConfig> _viewConfigs = [];
  
  // Getters
  int get gridColumns => _gridColumns;
  List<ViewConfig> get viewConfigs => _viewConfigs;

  // Set the number of columns in the grid
  void setGridColumns(int columns) {
    _gridColumns = max(1, columns);
    notifyListeners();
  }

  // Add a new view to the dashboard
  void addView() {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    _viewConfigs.add(ViewConfig(id: newId, title: 'View ${_viewConfigs.length + 1}'));
    notifyListeners();
  }

  // Remove a view from the dashboard
  void removeView(String id) {
    _viewConfigs.removeWhere((v) => v.id == id);
    notifyListeners();
  }
    
  // Update an existing view's configuration
  void updateViewConfig(String id, ViewConfig newConfig) {
    final index = _viewConfigs.indexWhere((v) => v.id == id);
    if (index != -1) {
      _viewConfigs[index] = newConfig;
      notifyListeners();
    }
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardState(),
      child: MaterialApp(
        title: 'Dynamic Dashboard',
        theme: ThemeData(
          primarySwatch: Colors.indigo,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.grey[200],
          cardTheme: const CardThemeData(
            elevation: 2,
            margin: EdgeInsets.all(8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        debugShowCheckedModeBanner: false,
        home: const DashboardScreen(),
      ),
    );
  }
}

// --- MAIN DASHBOARD SCREEN ---
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boston Bike Stations Dashboard'),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Layout Settings',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: const SettingsDrawer(),
      body: DashboardGrid(),
    );
  }
}

// --- SETTINGS DRAWER ---
class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<DashboardState>(context);
    final columnController = TextEditingController(text: state.gridColumns.toString());

    return Drawer(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const Divider(),
                const Text('Layout', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: columnController,
                  decoration: const InputDecoration(
                    labelText: 'Number of Columns',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (value) {
                    final intValue = int.tryParse(value);
                    if (intValue != null) {
                      state.setGridColumns(intValue);
                    }
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add New View'),
                  onPressed: () => state.addView(),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const Divider(height: 30),
                const Text('Active Views', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: state.viewConfigs.length,
              itemBuilder: (context, index) {
                final config = state.viewConfigs[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(config.title, overflow: TextOverflow.ellipsis),
                    subtitle: Text(config.type.toString().split('.').last),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Edit',
                          onPressed: () => _showConfigurationDialog(context, config),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Delete',
                          onPressed: () => state.removeView(config.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showConfigurationDialog(BuildContext context, ViewConfig config) async {
    final dashboardState = Provider.of<DashboardState>(context, listen: false);
    final newConfig = await showDialog<ViewConfig>(
      context: context,
      builder: (_) => ConfigurationDialog(config: config),
    );

    if (newConfig != null) {
      dashboardState.updateViewConfig(config.id, newConfig);
    }
  }
}

// --- DASHBOARD GRID ---
class DashboardGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = Provider.of<DashboardState>(context);

    if (state.viewConfigs.isEmpty) {
      return const Center(
        child: Text(
          'No views added. Open settings to add a new view.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: state.gridColumns,
        childAspectRatio: 1.2,
      ),
      itemCount: state.viewConfigs.length,
      itemBuilder: (context, index) {
        final config = state.viewConfigs[index];
        return ViewContainer(key: ValueKey(config.id), config: config);
      },
    );
  }
}

// --- VIEW CONTAINER WIDGET ---
class ViewContainer extends StatefulWidget {
  final ViewConfig config;

  const ViewContainer({super.key, required this.config});

  @override
  _ViewContainerState createState() => _ViewContainerState();
}

class _ViewContainerState extends State<ViewContainer> {
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didUpdateWidget(ViewContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config.dataSourceUrl != oldWidget.config.dataSourceUrl) {
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse(widget.config.dataSourceUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> stationsJson = data['data']['stations'];
        setState(() {
          _data = stationsJson.cast<Map<String, dynamic>>();
        });
      } else {
        throw Exception('Failed to load data (Code: ${response.statusCode})');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showConfigurationDialog() async {
    final dashboardState = Provider.of<DashboardState>(context, listen: false);
    final newConfig = await showDialog<ViewConfig>(
      context: context,
      builder: (_) => ConfigurationDialog(config: widget.config),
    );

    if (newConfig != null) {
      dashboardState.updateViewConfig(widget.config.id, newConfig);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          // View Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    widget.config.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.filter_alt_outlined),
                      tooltip: 'Filter Data',
                      onPressed: () { /* TODO: Implement Filter Dialog */ },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Configure View',
                      onPressed: _showConfigurationDialog,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // View Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildViewContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_data.isEmpty) {
      return const Center(child: Text("No data to display."));
    }

    switch (widget.config.type) {
      case ViewType.table:
        return DynamicTableView(data: _data);
      case ViewType.graph:
        return DynamicGraphView(data: _data, config: widget.config);
      case ViewType.map:
        return DynamicMapView(data: _data, config: widget.config);
      default:
        return const Center(child: Text('Select a view type in settings.'));
    }
  }
}

// --- DYNAMIC VIEW WIDGETS ---

class DynamicTableView extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const DynamicTableView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No data for table.'));
    final headers = data.first.keys.toList();

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: headers.map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
          rows: data.map((row) => DataRow(
            cells: headers.map((h) => DataCell(Text(row[h]?.toString() ?? ''))).toList(),
          )).toList(),
        ),
      ),
    );
  }
}

class DynamicGraphView extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final ViewConfig config;
  const DynamicGraphView({super.key, required this.data, required this.config});

  @override
  Widget build(BuildContext context) {
    final categoryCol = config.settings['categoryCol'] as String?;
    final valueCol = config.settings['valueCol'] as String?;

    if (categoryCol == null || valueCol == null) {
      return const Center(child: Text('Configure graph columns in settings.'));
    }

    final sortedData = List.from(data)..sort((a, b) {
      final valA = num.tryParse(a[valueCol]?.toString() ?? '0') ?? 0;
      final valB = num.tryParse(b[valueCol]?.toString() ?? '0') ?? 0;
      return valB.compareTo(valA);
    });
    final displayData = sortedData.take(15).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: displayData.asMap().entries.map((entry) {
          final value = num.tryParse(entry.value[valueCol]?.toString() ?? '0') ?? 0;
          return BarChartGroupData(
            x: entry.key,
            barRods: [BarChartRodData(toY: value.toDouble(), color: Colors.indigoAccent, width: 16)],
          );
        }).toList(),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < displayData.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(displayData[index][categoryCol]?.toString() ?? '', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                );
              }
              return const Text('');
            },
            reservedSize: 40,
          )),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }
}

class DynamicMapView extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final ViewConfig config;
  const DynamicMapView({super.key, required this.data, required this.config});

  @override
  _DynamicMapViewState createState() => _DynamicMapViewState();
}

class _DynamicMapViewState extends State<DynamicMapView> {
  MaplibreMapController? _mapController;

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
  }

  void _onStyleLoaded() => _addSymbols();

  @override
  void didUpdateWidget(covariant DynamicMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data || widget.config != oldWidget.config) {
      _addSymbols();
    }
  }

  void _addSymbols() async {
    if (_mapController == null || widget.data.isEmpty) return;
    final latCol = widget.config.settings['latCol'] as String?;
    final lonCol = widget.config.settings['lonCol'] as String?;
    if (latCol == null || lonCol == null) return;

    final ByteData bytes = await rootBundle.load('assets/icons/icons8-map-pin-64.png');
    await _mapController!.addImage('bike-icon', bytes.buffer.asUint8List());
    _mapController!.clearSymbols();

    for (final item in widget.data) {
      final lat = num.tryParse(item[latCol]?.toString() ?? '0.0');
      final lon = num.tryParse(item[lonCol]?.toString() ?? '0.0');
      if (lat != null && lon != null) {
        _mapController!.addSymbol(SymbolOptions(
          geometry: LatLng(lat.toDouble(), lon.toDouble()),
          iconImage: 'bike-icon',
          iconSize: 0.5,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.settings['latCol'] == null || widget.config.settings['lonCol'] == null) {
      return const Center(child: Text('Configure Lat/Lon columns in settings.'));
    }
    return MaplibreMap(
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      styleString: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
      initialCameraPosition: const CameraPosition(target: LatLng(42.3601, -71.0589), zoom: 11.0),
    );
  }
}

// --- CONFIGURATION DIALOG ---
class ConfigurationDialog extends StatefulWidget {
  final ViewConfig config;
  const ConfigurationDialog({super.key, required this.config});

  @override
  _ConfigurationDialogState createState() => _ConfigurationDialogState();
}

class _ConfigurationDialogState extends State<ConfigurationDialog> {
  late TextEditingController _titleController;
  late ViewType _selectedType;
  late String _selectedDataSourceUrl;
  late Map<String, dynamic> _currentSettings;
  List<String> _availableColumns = [];
  bool _isLoadingColumns = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.config.title);
    _selectedType = widget.config.type;
    _selectedDataSourceUrl = widget.config.dataSourceUrl;
    _currentSettings = Map.from(widget.config.settings);
    _fetchColumnsForUrl(_selectedDataSourceUrl);
  }

  Future<void> _fetchColumnsForUrl(String url) async {
    setState(() => _isLoadingColumns = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> stationsJson = data['data']['stations'];
        if (stationsJson.isNotEmpty) {
          setState(() {
            _availableColumns = (stationsJson.first as Map<String, dynamic>).keys.toList();
          });
        }
      }
    } catch (e) {
      // Handle error appropriately
    } finally {
      setState(() => _isLoadingColumns = false);
    }
  }

  void _onDataSourceChanged(String? url) {
    if (url != null && url != _selectedDataSourceUrl) {
      setState(() {
        _selectedDataSourceUrl = url;
        _currentSettings = {}; // Reset settings on source change
        _availableColumns = [];
      });
      _fetchColumnsForUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure View'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'View Title'),
            ),
            const SizedBox(height: 16),
            // Data Source Selection
            const Text('Data Source', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile<String>(
              title: const Text('Information'),
              value: stationInfoUrl,
              groupValue: _selectedDataSourceUrl,
              onChanged: _onDataSourceChanged,
            ),
            RadioListTile<String>(
              title: const Text('Status'),
              value: stationStatusUrl,
              groupValue: _selectedDataSourceUrl,
              onChanged: _onDataSourceChanged,
            ),
            const Divider(),
            // View Type Selection
            DropdownButtonFormField<ViewType>(
              value: _selectedType,
              decoration: const InputDecoration(labelText: 'View Type'),
              items: ViewType.values.map((type) => DropdownMenuItem(value: type, child: Text(type.toString().split('.').last))).toList(),
              onChanged: (type) {
                if (type != null) setState(() => _selectedType = type);
              },
            ),
            const SizedBox(height: 16),
            if (_isLoadingColumns) const Center(child: CircularProgressIndicator()) else ..._buildSettingsWidgets(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final newConfig = ViewConfig(
              id: widget.config.id,
              title: _titleController.text,
              type: _selectedType,
              dataSourceUrl: _selectedDataSourceUrl,
              settings: _currentSettings,
            );
            Navigator.of(context).pop(newConfig);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  List<Widget> _buildSettingsWidgets() {
    switch (_selectedType) {
      case ViewType.graph:
        return [
          _buildColumnSelector('Category Column (X-Axis)', 'categoryCol'),
          _buildColumnSelector('Value Column (Y-Axis)', 'valueCol'),
        ];
      case ViewType.map:
        return [
          _buildColumnSelector('Latitude Column', 'latCol'),
          _buildColumnSelector('Longitude Column', 'lonCol'),
        ];
      default:
        return [];
    }
  }

  Widget _buildColumnSelector(String label, String settingKey) {
    return DropdownButtonFormField<String>(
      value: _currentSettings[settingKey],
      decoration: InputDecoration(labelText: label),
      items: _availableColumns.map((col) => DropdownMenuItem(value: col, child: Text(col))).toList(),
      onChanged: (value) {
        if (value != null) setState(() => _currentSettings[settingKey] = value);
      },
    );
  }
}
