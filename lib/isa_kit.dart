import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:math';

// --- MODELS (Exported for users) ---

class DynamicWidgetConfig {
  final String id;
  String widgetType;
  Map<String, dynamic> properties;
  List<DynamicWidgetConfig> children;

  DynamicWidgetConfig({
    required this.id,
    required this.widgetType,
    this.properties = const {},
    this.children = const [],
  });

  static DynamicWidgetConfig empty() {
    return DynamicWidgetConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      widgetType: 'container',
      properties: {
        'title': 'New Container',
        'isDataEnabled': true,
        // Default styles for example widgets
        'barColor': Colors.indigoAccent.value,
        'iconSize': 0.5,
        'columnWidth': 120.0,
        'iconAssetPath': 'assets/icons/icons8-map-pin-64.png',
      },
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

// --- STATE MANAGEMENT (Exported for users) ---

class DashboardState with ChangeNotifier {
  DynamicWidgetConfig _rootConfig = DynamicWidgetConfig.empty();
  final Map<String, List<Map<String, dynamic>>> _dataCache = {};
  final Map<String, bool> _loadingStatus = {};

  DynamicWidgetConfig get rootConfig => _rootConfig;
  Map<String, List<Map<String, dynamic>>> get dataCache => _dataCache;

  DynamicWidgetConfig? findWidget(String id, {DynamicWidgetConfig? searchNode}) {
    final node = searchNode ?? _rootConfig;
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = findWidget(id, searchNode: child);
      if (found != null) return found;
    }
    return null;
  }

  void addWidget(String parentId) {
    final parent = findWidget(parentId);
    if (parent != null) {
      parent.children.add(DynamicWidgetConfig.empty());
      notifyListeners();
    }
  }

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

  DynamicWidgetConfig? _findParent(String id, {DynamicWidgetConfig? searchNode}) {
    final node = searchNode ?? _rootConfig;
    for (final child in node.children) {
      if (child.id == id) return node;
      final parent = _findParent(id, searchNode: child);
      if (parent != null) return parent;
    }
    return null;
  }

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

// --- UI COMPONENTS (Exported for users) ---

class DynamicDashboard extends StatelessWidget {
  final Widget Function(BuildContext context, DynamicWidgetConfig config) widgetBuilder;

  const DynamicDashboard({super.key, required this.widgetBuilder});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardState>(
      builder: (context, state, child) {
        return DynamicWidgetBuilder(
          config: state.rootConfig,
          widgetBuilder: widgetBuilder,
        );
      },
    );
  }
}

class SettingsDrawer extends StatelessWidget {
  final Future<DynamicWidgetConfig?> Function(BuildContext, DynamicWidgetConfig) onEditConfig;

  const SettingsDrawer({super.key, required this.onEditConfig});

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
              child: WidgetTreeEditor(
                config: state.rootConfig,
                onEditConfig: onEditConfig,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- INTERNAL IMPLEMENTATION ---

class DynamicWidgetBuilder extends StatelessWidget {
  final DynamicWidgetConfig config;
  final Widget Function(BuildContext context, DynamicWidgetConfig config) widgetBuilder;

  const DynamicWidgetBuilder({
    super.key,
    required this.config,
    required this.widgetBuilder,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (config.widgetType) {
      case 'container':
        content = config.children.isEmpty
            ? Center(child: Text(config.properties['title'] ?? 'Untitled'))
            : DynamicWidgetBuilder(config: config.children.first, widgetBuilder: widgetBuilder);
        break;
      case 'row':
        content = Row(
          children: config.children
              .map((child) => Expanded(
                    child: DynamicWidgetBuilder(
                      key: ValueKey(child.id),
                      config: child,
                      widgetBuilder: widgetBuilder,
                    ),
                  ))
              .toList(),
        );
        break;
      case 'column':
        content = Column(
          children: config.children
              .map((child) => Expanded(
                    child: DynamicWidgetBuilder(
                      key: ValueKey(child.id),
                      config: child,
                      widgetBuilder: widgetBuilder,
                    ),
                  ))
              .toList(),
        );
        break;
      default:
        content = widgetBuilder(context, config);
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: content,
    );
  }
}

class WidgetTreeEditor extends StatelessWidget {
  final DynamicWidgetConfig config;
  final Future<DynamicWidgetConfig?> Function(BuildContext, DynamicWidgetConfig) onEditConfig;

  const WidgetTreeEditor({
    super.key,
    required this.config,
    required this.onEditConfig,
  });

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<DashboardState>(context, listen: false);
    return ExpansionTile(
      leading: Icon(
        Icons.account_tree_outlined,
        color: Theme.of(context).primaryColor,
      ),
      initiallyExpanded: true,
      title: Text(config.properties['title'] ?? config.widgetType),
      subtitle: Text(config.widgetType),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (['row', 'column', 'container'].contains(config.widgetType))
            IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: 'Add Child', onPressed: () => state.addWidget(config.id)),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () async {
              final newConfig = await onEditConfig(context, config);
              if (newConfig != null && context.mounted) {
                Provider.of<DashboardState>(context, listen: false).updateWidget(config.id, newConfig);
              }
            },
          ),
        ],
      ),
      children: config.children.map((child) => Padding(
        padding: const EdgeInsets.only(left: 16.0),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Colors.grey.shade300, width: 2)),
          ),
          child: WidgetTreeEditor(config: child, onEditConfig: onEditConfig),
        ),
      )).toList(),
    );
  }
}
