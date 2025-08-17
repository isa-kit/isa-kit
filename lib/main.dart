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

// --- DYNAMIC WIDGET MODELS ---

// Represents a single configurable widget in the UI tree.
class DynamicWidgetConfig {
  final String id;
  String widgetType; // e.g., 'container', 'row', 'column', 'tableView'
  Map<String, dynamic> properties;
  List<DynamicWidgetConfig> children;

  DynamicWidgetConfig({
    required this.id,
    required this.widgetType,
    this.properties = const {},
    this.children = const [],
  });
    
  // Helper to create a default empty container
  static DynamicWidgetConfig empty() {
      return DynamicWidgetConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          widgetType: 'container',
          properties: {'title': 'New Container', 'isDataEnabled': true},
          children: [],
      );
  }
}

class Filter {
  String column;
  FilterType type;
  dynamic value;
  Filter({required this.column, required this.type, this.value});
}

enum FilterType { equals, contains, greaterThan, lessThan }

// --- STATE MANAGEMENT ---

class DashboardState with ChangeNotifier {
  DynamicWidgetConfig _rootConfig = DynamicWidgetConfig.empty();
  final Map<String, List<Map<String, dynamic>>> _dataCache = {};
  final Map<String, bool> _loadingStatus = {};

  DynamicWidgetConfig get rootConfig => _rootConfig;
  Map<String, List<Map<String, dynamic>>> get dataCache => _dataCache;

  // Finds a widget config by its ID in the tree
  DynamicWidgetConfig? findWidget(String id, {DynamicWidgetConfig? searchNode}) {
    final node = searchNode ?? _rootConfig;
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = findWidget(id, searchNode: child);
      if (found != null) return found;
    }
    return null;
  }

  // Adds a new child to a widget
  void addWidget(String parentId) {
    final parent = findWidget(parentId);
    if (parent != null) {
      parent.children.add(DynamicWidgetConfig.empty());
      notifyListeners();
    }
  }

  // Removes a widget from the tree
  void removeWidget(String id, {DynamicWidgetConfig? searchNode}) {
      final node = searchNode ?? _rootConfig;
      final initialCount = node.children.length;
      node.children.removeWhere((child) => child.id == id);
      if (node.children.length < initialCount) {
          notifyListeners();
          return;
      }
      for (final child in node.children) {
          removeWidget(id, searchNode: child);
      }
  }


  // Updates a widget's configuration
  void updateWidget(String id, DynamicWidgetConfig newConfig) {
    final parent = _findParent(id);
    if (parent != null) {
      final index = parent.children.indexWhere((w) => w.id == id);
      if (index != -1) {
        parent.children[index] = newConfig;
        notifyListeners();
      }
    } else if (_rootConfig.id == id) {
      _rootConfig = newConfig;
      notifyListeners();
    }
  }
    
  // Helper to find the parent of a widget
  DynamicWidgetConfig? _findParent(String id, {DynamicWidgetConfig? searchNode}) {
      final node = searchNode ?? _rootConfig;
      for (final child in node.children) {
          if (child.id == id) return node;
          final parent = _findParent(id, searchNode: child);
          if (parent != null) return parent;
      }
      return null;
  }

  // Fetches and caches data from a URL
  Future<void> fetchDataForUrl(String url) async {
    if (_dataCache.containsKey(url) || _loadingStatus[url] == true) return;
    _loadingStatus[url] = true;
    notifyListeners();
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _dataCache[url] = List<Map<String, dynamic>>.from(data['data']['stations']);
      } else {
        throw Exception('Failed to load data (Code: ${response.statusCode})');
      }
    } finally {
      _loadingStatus[url] = false;
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
        ),
        debugShowCheckedModeBanner: false,
        home: const DashboardScreen(),
      ),
    );
  }
}

// --- MAIN SCREEN ---
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
      body: Consumer<DashboardState>(
        builder: (context, state, child) {
          return DynamicWidgetBuilder(config: state.rootConfig);
        },
      ),
    );
  }
}

// --- RECURSIVE WIDGET BUILDER ---
class DynamicWidgetBuilder extends StatelessWidget {
  final DynamicWidgetConfig config;
  final bool isParentDataEnabled;

  const DynamicWidgetBuilder({
    super.key,
    required this.config,
    this.isParentDataEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDataEnabled = isParentDataEnabled && (config.properties['isDataEnabled'] ?? true);
    final title = config.properties['title'] ?? 'Untitled';

    Widget content;
    switch (config.widgetType) {
      case 'container':
        content = config.children.isEmpty
            ? Center(child: Text(title))
            : DynamicWidgetBuilder(config: config.children.first, isParentDataEnabled: isDataEnabled);
        break;
      case 'row':
        content = Row(
          children: config.children.map((child) => Expanded(
            child: DynamicWidgetBuilder(config: child, isParentDataEnabled: isDataEnabled),
          )).toList(),
        );
        break;
      case 'column':
        content = Column(
          children: config.children.map((child) => Expanded(
            child: DynamicWidgetBuilder(config: child, isParentDataEnabled: isDataEnabled),
          )).toList(),
        );
        break;
      case 'tableView':
      case 'graphView':
      case 'mapView':
        content = DataView(config: config, isDataEnabled: isDataEnabled);
        break;
      default:
        content = Center(child: Text('Unknown Widget: ${config.widgetType}'));
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: content,
    );
  }
}

// --- DATA-DRIVEN VIEW ---
class DataView extends StatefulWidget {
  final DynamicWidgetConfig config;
  final bool isDataEnabled;

  const DataView({super.key, required this.config, required this.isDataEnabled});

  @override
  _DataViewState createState() => _DataViewState();
}

class _DataViewState extends State<DataView> {
  @override
  void initState() {
    super.initState();
    if (widget.isDataEnabled) {
      final url = widget.config.properties['dataSourceUrl'] ?? stationInfoUrl;
      Provider.of<DashboardState>(context, listen: false).fetchDataForUrl(url);
    }
  }

  @override
  void didUpdateWidget(DataView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDataEnabled && (widget.config.properties['dataSourceUrl'] != oldWidget.config.properties['dataSourceUrl'])) {
      final url = widget.config.properties['dataSourceUrl'] ?? stationInfoUrl;
      Provider.of<DashboardState>(context, listen: false).fetchDataForUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isDataEnabled) {
      return const Center(child: Icon(Icons.power_off, color: Colors.grey, size: 40));
    }

    final state = Provider.of<DashboardState>(context);
    final url = widget.config.properties['dataSourceUrl'] ?? stationInfoUrl;
    final data = state.dataCache[url];

    if (data == null) return const Center(child: CircularProgressIndicator());

    final filters = (widget.config.properties['filters'] as List<dynamic>?)
        ?.map((f) => Filter(column: f['column'], type: FilterType.values.byName(f['type']), value: f['value']))
        .toList() ?? [];
    
    final filteredData = _applyFilters(data, filters);

    if (filteredData.isEmpty) return const Center(child: Text("No data to display."));

    switch (widget.config.widgetType) {
      case 'tableView':
        return DynamicTableView(data: filteredData);
      case 'graphView':
        return DynamicGraphView(data: filteredData, config: widget.config);
      case 'mapView':
        return DynamicMapView(data: filteredData, config: widget.config);
      default:
        return const SizedBox.shrink();
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> data, List<Filter> filters) {
    if (filters.isEmpty) return data;
    return data.where((row) {
      return filters.every((filter) {
        final value = row[filter.column];
        if (value == null) return false;
        try {
          switch (filter.type) {
            case FilterType.equals: return value.toString() == filter.value;
            case FilterType.contains: return value.toString().contains(filter.value);
            case FilterType.greaterThan: return num.parse(value.toString()) > num.parse(filter.value);
            case FilterType.lessThan: return num.parse(value.toString()) < num.parse(filter.value);
          }
        } catch (e) {
          return false;
        }
      });
    }).toList();
  }
}


// --- SETTINGS DRAWER & DIALOGS ---
class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    final state = Provider.of<DashboardState>(context);
    return Drawer(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 40, 16, 16),
            child: Text('UI Layout', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              child: WidgetTreeEditor(config: state.rootConfig),
            ),
          ),
        ],
      ),
    );
  }
}

class WidgetTreeEditor extends StatelessWidget {
  final DynamicWidgetConfig config;
  const WidgetTreeEditor({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<DashboardState>(context, listen: false);
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(config.properties['title'] ?? config.widgetType),
      subtitle: Text(config.widgetType),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (['row', 'column', 'container'].contains(config.widgetType))
            IconButton(icon: const Icon(Icons.add), tooltip: 'Add Child', onPressed: () => state.addWidget(config.id)),
          IconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () => _showConfigurationDialog(context, config)),
        ],
      ),
      children: config.children.map((child) => Padding(
        padding: const EdgeInsets.only(left: 16.0),
        child: WidgetTreeEditor(config: child),
      )).toList(),
    );
  }

  void _showConfigurationDialog(BuildContext context, DynamicWidgetConfig config) async {
    final newConfig = await showDialog<DynamicWidgetConfig>(
      context: context,
      builder: (_) => ConfigurationDialog(config: config),
    );
    if (newConfig != null) {
      Provider.of<DashboardState>(context, listen: false).updateWidget(config.id, newConfig);
    }
  }
}

class ConfigurationDialog extends StatefulWidget {
  final DynamicWidgetConfig config;
  const ConfigurationDialog({super.key, required this.config});
  @override
  _ConfigurationDialogState createState() => _ConfigurationDialogState();
}

class _ConfigurationDialogState extends State<ConfigurationDialog> {
  late DynamicWidgetConfig _tempConfig;
  List<String> _availableColumns = [];
  bool _isLoadingColumns = false;

  @override
  void initState() {
    super.initState();
    // Deep copy for editing
    _tempConfig = DynamicWidgetConfig(
      id: widget.config.id,
      widgetType: widget.config.widgetType,
      properties: Map.from(widget.config.properties),
      children: List.from(widget.config.children),
    );
    _fetchColumnsForUrl(_tempConfig.properties['dataSourceUrl'] ?? stationInfoUrl);
  }

  Future<void> _fetchColumnsForUrl(String url) async {
    setState(() => _isLoadingColumns = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if ((data['data']['stations'] as List).isNotEmpty) {
          setState(() {
            _availableColumns = (data['data']['stations'].first as Map<String, dynamic>).keys.toList();
          });
        }
      }
    } finally {
      setState(() => _isLoadingColumns = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleController = TextEditingController(text: _tempConfig.properties['title']);
    return AlertDialog(
      title: const Text('Configure Widget'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _tempConfig.widgetType,
              decoration: const InputDecoration(labelText: 'Widget Type'),
              items: ['container', 'row', 'column', 'tableView', 'graphView', 'mapView']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (value) => setState(() => _tempConfig.widgetType = value!),
            ),
            const Divider(height: 20),
            if (['tableView', 'graphView', 'mapView'].contains(_tempConfig.widgetType)) ...[
              SwitchListTile(
                title: const Text('Enable Data'),
                value: _tempConfig.properties['isDataEnabled'] ?? true,
                onChanged: (val) => setState(() => _tempConfig.properties['isDataEnabled'] = val),
              ),
              DropdownButtonFormField<String>(
                value: _tempConfig.properties['dataSourceUrl'] ?? stationInfoUrl,
                decoration: const InputDecoration(labelText: 'Data Source'),
                items: [stationInfoUrl, stationStatusUrl]
                    .map((url) => DropdownMenuItem(value: url, child: Text(url.split('/').last))).toList(),
                onChanged: (url) {
                  if (url != null) {
                    setState(() {
                      _tempConfig.properties['dataSourceUrl'] = url;
                      _availableColumns = [];
                    });
                    _fetchColumnsForUrl(url);
                  }
                },
              ),
              if (_isLoadingColumns) const Center(child: CircularProgressIndicator()) else ..._buildSettingsWidgets(),
            ]
          ],
        ),
      ),
      actions: [
        if (widget.config.id != Provider.of<DashboardState>(context, listen: false).rootConfig.id)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () {
              Provider.of<DashboardState>(context, listen: false).removeWidget(widget.config.id);
              Navigator.of(context).pop();
            },
          ),
        const Spacer(),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            _tempConfig.properties['title'] = titleController.text;
            Navigator.of(context).pop(_tempConfig);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  List<Widget> _buildSettingsWidgets() {
    switch (_tempConfig.widgetType) {
      case 'graphView':
        return [
          _buildColumnSelector('Category Column (X-Axis)', 'categoryCol'),
          _buildColumnSelector('Value Column (Y-Axis)', 'valueCol'),
        ];
      case 'mapView':
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
      value: _tempConfig.properties[settingKey],
      decoration: InputDecoration(labelText: label),
      items: _availableColumns.map((col) => DropdownMenuItem(value: col, child: Text(col))).toList(),
      onChanged: (value) => setState(() => _tempConfig.properties[settingKey] = value),
    );
  }
}

// --- DYNAMIC VIEW WIDGETS (Table, Graph, Map) ---
// These are largely unchanged but now receive data from DataView
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
  final DynamicWidgetConfig config;
  const DynamicGraphView({super.key, required this.data, required this.config});

  @override
  Widget build(BuildContext context) {
    final categoryCol = config.properties['categoryCol'] as String?;
    final valueCol = config.properties['valueCol'] as String?;

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
  final DynamicWidgetConfig config;
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
    final latCol = widget.config.properties['latCol'] as String?;
    final lonCol = widget.config.properties['lonCol'] as String?;
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
    if (widget.config.properties['latCol'] == null || widget.config.properties['lonCol'] == null) {
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
