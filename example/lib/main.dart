import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:isa_kit/isa_kit.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

const String stationInfoUrl = 'https://gbfs.lyft.com/gbfs/1.1/bos/en/station_information.json';
const String stationStatusUrl = 'https://gbfs.lyft.com/gbfs/1.1/bos/en/station_status.json';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DashboardState>(
      create: (_) => DashboardState(),
      child: MaterialApp(
        title: 'isa-kit Example',
        theme: ThemeData(
          primarySwatch: Colors.indigo,
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        home: const DashboardScreen(),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<DynamicWidgetConfig?> _showConfigurationDialog(BuildContext context, DynamicWidgetConfig config) {
    return showDialog<DynamicWidgetConfig>(
      context: context,
      builder: (_) => ConfigurationDialog(config: config),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('isa-kit Dashboard'),
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
      endDrawer: SettingsDrawer(onEditConfig: _showConfigurationDialog),
      body: DynamicDashboard(
        widgetBuilder: (context, config) {
          switch (config.widgetType) {
            case 'tableView':
              return DataViewWrapper(
                config: config,
                builder: (data) => ExampleTableView(data: data, config: config),
              );
            case 'graphView':
              return DataViewWrapper(
                config: config,
                builder: (data) => ExampleGraphView(data: data, config: config),
              );
            case 'mapView':
              return DataViewWrapper(
                config: config,
                builder: (data) => ExampleMapView(data: data, config: config),
              );
            default:
              return Center(child: Text('Unknown widget type: ${config.widgetType}'));
          }
        },
      ),
    );
  }
}

class DataViewWrapper extends StatefulWidget {
  final DynamicWidgetConfig config;
  final Widget Function(List<Map<String, dynamic>> data) builder;

  const DataViewWrapper({
    super.key,
    required this.config,
    required this.builder,
  });

  @override
  DataViewWrapperState createState() => DataViewWrapperState();
}

class DataViewWrapperState extends State<DataViewWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (widget.config.properties['isDataEnabled'] ?? true)) {
        final url = widget.config.properties['dataSourceUrl'];
        if (url != null) {
          Provider.of<DashboardState>(context, listen: false).fetchDataForUrl(url);
        }
      }
    });
  }

  @override
  void didUpdateWidget(DataViewWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.config.properties['isDataEnabled'] ?? true) &&
        (widget.config.properties['dataSourceUrl'] != oldWidget.config.properties['dataSourceUrl'])) {
      final url = widget.config.properties['dataSourceUrl'];
      if (url != null) {
        Provider.of<DashboardState>(context, listen: false).fetchDataForUrl(url);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!(widget.config.properties['isDataEnabled'] ?? true)) {
      return const Center(child: Icon(Icons.power_off, color: Colors.grey, size: 40));
    }

    final state = Provider.of<DashboardState>(context);
    final url = widget.config.properties['dataSourceUrl'];
    if (url == null) return const Center(child: Text("Data source not configured."));

    final data = state.dataCache[url];
    if (data == null) return const Center(child: CircularProgressIndicator());

    final filteredData = data;

    if (filteredData.isEmpty) return const Center(child: Text("No data to display."));

    return widget.builder(filteredData);
  }
}

class ConfigurationDialog extends StatefulWidget {
  final DynamicWidgetConfig config;
  const ConfigurationDialog({super.key, required this.config});
  @override
  ConfigurationDialogState createState() => ConfigurationDialogState();
}

class ConfigurationDialogState extends State<ConfigurationDialog> {
  late DynamicWidgetConfig _tempConfig;
  List<String> _availableColumns = [];
  bool _isLoadingColumns = false;
  final Map<String, List<String>> _columnCache = {};
  late final TextEditingController _titleController;
  final Map<String, TextEditingController> _settingControllers = {};

  @override
  void initState() {
    super.initState();
    _tempConfig = DynamicWidgetConfig(
      id: widget.config.id,
      widgetType: widget.config.widgetType,
      properties: Map.from(widget.config.properties),
      children: List.from(widget.config.children),
    );

    _titleController = TextEditingController(text: _tempConfig.properties['title']);

    if (_tempConfig.properties['dataSourceUrl'] != null) {
      _fetchColumnsForUrl(_tempConfig.properties['dataSourceUrl']);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final controller in _settingControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchColumnsForUrl(String url) async {
    if (_columnCache.containsKey(url)) {
      if (mounted) {
        setState(() => _availableColumns = _columnCache[url]!);
      }
      return;
    }
    if (mounted) {
      setState(() => _isLoadingColumns = true);
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if ((data['data']['stations'] as List).isNotEmpty) {
          final columns = (data['data']['stations'].first as Map<String, dynamic>).keys.toList();
          if (mounted) {
            setState(() {
              _availableColumns = columns;
              _columnCache[url] = columns;
            });
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingColumns = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure Widget'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _tempConfig.widgetType,
              decoration: const InputDecoration(labelText: 'Widget Type'),
              items: ['container', 'row', 'column', 'tableView', 'graphView', 'mapView']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _tempConfig.widgetType = value);
                    }
                  });
                }
              },
            ),
            const Divider(height: 20),
            if (['tableView', 'graphView', 'mapView'].contains(_tempConfig.widgetType)) ...[
              SwitchListTile(
                title: const Text('Enable Data'),
                value: _tempConfig.properties['isDataEnabled'] ?? true,
                onChanged: (val) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _tempConfig.properties['isDataEnabled'] = val);
                    }
                  });
                },
              ),
              DropdownButtonFormField<String>(
                value: _tempConfig.properties['dataSourceUrl'],
                decoration: const InputDecoration(labelText: 'Data Source'),
                items: [stationInfoUrl, stationStatusUrl]
                    .map((url) => DropdownMenuItem(value: url, child: Text(url.split('/').last)))
                    .toList(),
                onChanged: (url) {
                  if (url != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _tempConfig.properties['dataSourceUrl'] = url;
                          _availableColumns = [];
                        });
                        _fetchColumnsForUrl(url);
                      }
                    });
                  }
                },
              ),
              if (_isLoadingColumns) const Center(child: CircularProgressIndicator()) else ..._buildSettingsWidgets(),
            ]
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (widget.config.id != Provider.of<DashboardState>(context, listen: false).rootConfig.id)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete Widget',
            onPressed: () {
              Provider.of<DashboardState>(context, listen: false).removeWidget(widget.config.id);
              Navigator.of(context).pop();
            },
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                _tempConfig.properties['title'] = _titleController.text;
                _settingControllers.forEach((key, controller) {
                  if (key == 'columnWidth') {
                    _tempConfig.properties[key] = double.tryParse(controller.text) ?? 120.0;
                  } else {
                    _tempConfig.properties[key] = controller.text;
                  }
                });
                Navigator.of(context).pop(_tempConfig);
              },
              child: const Text('Save'),
            ),
          ],
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
          _buildColorSelector('Bar Color', 'barColor'),
        ];
      case 'mapView':
        return [
          _buildColumnSelector('Latitude Column', 'latCol'),
          _buildColumnSelector('Longitude Column', 'lonCol'),
          _buildSlider('Icon Size', 'iconSize', min: 0.1, max: 2.0, divisions: 19),
          _buildTextField('Icon Asset Path', 'iconAssetPath'),
        ];
      case 'tableView':
        return [
          _buildTextField('Column Width', 'columnWidth', isNumeric: true),
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
      onChanged: (value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _tempConfig.properties[settingKey] = value);
          }
        });
      },
    );
  }

  Widget _buildColorSelector(String label, String settingKey) {
    final currentColor = Color(_tempConfig.properties[settingKey] ?? Colors.indigoAccent.value);
    return ListTile(
      title: Text(label),
      trailing: CircleAvatar(backgroundColor: currentColor),
      onTap: () {
        const colors = [Colors.indigoAccent, Colors.redAccent, Colors.greenAccent, Colors.amberAccent];
        final currentIndex = colors.indexWhere((c) => c.value == currentColor.value);
        final nextColor = colors[(currentIndex + 1) % colors.length];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _tempConfig.properties[settingKey] = nextColor.value;
            });
          }
        });
      },
    );
  }

  Widget _buildSlider(String label, String settingKey, {required double min, required double max, required int divisions}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: (_tempConfig.properties[settingKey] as num? ?? min).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: (_tempConfig.properties[settingKey] as num? ?? min).toStringAsFixed(1),
          onChanged: (value) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _tempConfig.properties[settingKey] = value);
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildTextField(String label, String settingKey, {bool isNumeric = false}) {
    final controller = _settingControllers.putIfAbsent(
      settingKey,
      () => TextEditingController(text: _tempConfig.properties[settingKey]?.toString() ?? ''),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      ),
    );
  }
}

class ExampleTableView extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final DynamicWidgetConfig config;
  const ExampleTableView({super.key, required this.data, required this.config});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No data for table.'));
    final headers = data.first.keys.toList();
    final columnWidth = (config.properties['columnWidth'] as num? ?? 120.0).toDouble();

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          columns: headers.map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
          rows: data.map((row) => DataRow(
            cells: headers.map((h) => DataCell(
              SizedBox(
                width: columnWidth,
                child: Text(row[h]?.toString() ?? '', overflow: TextOverflow.ellipsis),
              )
            )).toList(),
          )).toList(),
        ),
      ),
    );
  }
}

class ExampleGraphView extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final DynamicWidgetConfig config;
  const ExampleGraphView({super.key, required this.data, required this.config});

  @override
  Widget build(BuildContext context) {
    final categoryCol = config.properties['categoryCol'] as String?;
    final valueCol = config.properties['valueCol'] as String?;
    final barColor = Color(config.properties['barColor'] ?? Colors.indigoAccent.value);

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
            barRods: [BarChartRodData(toY: value.toDouble(), color: barColor, width: 16)],
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

class ExampleMapView extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final DynamicWidgetConfig config;
  const ExampleMapView({super.key, required this.data, required this.config});

  @override
  ExampleMapViewState createState() => ExampleMapViewState();
}

class ExampleMapViewState extends State<ExampleMapView> {
  MapLibreMapController? _mapController;

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  void _onStyleLoaded() => _addSymbols();

  @override
  void didUpdateWidget(covariant ExampleMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data || widget.config != oldWidget.config) {
      _addSymbols();
    }
  }

  void _addSymbols() async {
    if (_mapController == null || widget.data.isEmpty) return;
    final latCol = widget.config.properties['latCol'] as String?;
    final lonCol = widget.config.properties['lonCol'] as String?;
    final iconSize = (widget.config.properties['iconSize'] as num? ?? 0.5).toDouble();
    final iconAssetPath = widget.config.properties['iconAssetPath'] as String?;

    if (latCol == null || lonCol == null || iconAssetPath == null) return;

    try {
      final ByteData bytes = await rootBundle.load(iconAssetPath);
      await _mapController!.addImage('bike-icon', bytes.buffer.asUint8List());
      _mapController!.clearSymbols();

      for (final item in widget.data) {
        final lat = num.tryParse(item[latCol]?.toString() ?? '0.0');
        final lon = num.tryParse(item[lonCol]?.toString() ?? '0.0');
        if (lat != null && lon != null) {
          _mapController!.addSymbol(SymbolOptions(
            geometry: LatLng(lat.toDouble(), lon.toDouble()),
            iconImage: 'bike-icon',
            iconSize: iconSize,
          ));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error loading asset: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.properties['latCol'] == null || widget.config.properties['lonCol'] == null) {
      return const Center(child: Text('Configure Lat/Lon columns in settings.'));
    }
    return MapLibreMap(
      key: ValueKey(widget.config.id),
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      styleString: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
      initialCameraPosition: const CameraPosition(target: LatLng(42.3601, -71.0589), zoom: 11.0),
    );
  }
}
