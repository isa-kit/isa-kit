import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

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

  DynamicWidgetConfig copy() {
    return DynamicWidgetConfig.fromJson(toJson());
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'widgetType': widgetType,
        'properties': properties,
        'children': children.map((child) => child.toJson()).toList(),
      };

  factory DynamicWidgetConfig.fromJson(Map<String, dynamic> json) {
    return DynamicWidgetConfig(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      widgetType: json['widgetType'],
      properties: Map<String, dynamic>.from(json['properties']),
      children: (json['children'] as List)
          .map((childJson) => DynamicWidgetConfig.fromJson(childJson))
          .toList(),
    );
  }

  static DynamicWidgetConfig empty() {
    return DynamicWidgetConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      widgetType: 'container',
      properties: {
        'title': 'New Container',
      },
      children: [],
    );
  }
}

// --- HISTORY & STATE MANAGEMENT ---

class HistoryNode {
  final String stateJson;
  final DateTime timestamp;
  final HistoryNode? parent;
  final List<HistoryNode> children = [];
  final String id;

  HistoryNode({required this.stateJson, this.parent, required this.timestamp}) : id = UniqueKey().toString();

  void addChild(HistoryNode node) {
    children.add(node);
  }
}

enum DashboardMode { edit, view }

class DashboardState with ChangeNotifier {
  DynamicWidgetConfig _rootConfig = DynamicWidgetConfig.empty();
  final Map<String, List<Map<String, dynamic>>> _dataCache = {};
  final Map<String, bool> _loadingStatus = {};

  late HistoryNode _rootHistoryNode;
  late HistoryNode _currentHistoryNode;
  DashboardMode _mode = DashboardMode.edit;

  DashboardState() {
    _rootHistoryNode = HistoryNode(stateJson: _configToJson(_rootConfig), timestamp: DateTime.now());
    _currentHistoryNode = _rootHistoryNode;
  }

  DynamicWidgetConfig get rootConfig => _rootConfig;
  Map<String, List<Map<String, dynamic>>> get dataCache => _dataCache;
  DashboardMode get mode => _mode;
  HistoryNode get historyRoot => _rootHistoryNode;
  HistoryNode get currentHistory => _currentHistoryNode;

  bool get canUndo => _currentHistoryNode.parent != null;
  bool get canRedo => _currentHistoryNode.children.isNotEmpty;

  void setMode(DashboardMode newMode) {
    _mode = newMode;
    notifyListeners();
  }

  void undo() {
    if (canUndo) {
      _currentHistoryNode = _currentHistoryNode.parent!;
      _loadStateFromHistory();
    }
  }

  void redo() {
    if (canRedo) {
      _currentHistoryNode = _currentHistoryNode.children.last;
      _loadStateFromHistory();
    }
  }

  void jumpToState(HistoryNode node) {
    _currentHistoryNode = node;
    _loadStateFromHistory();
  }

  void _loadStateFromHistory() {
    _rootConfig = DynamicWidgetConfig.fromJson(json.decode(_currentHistoryNode.stateJson));
    notifyListeners();
  }

  void _recordChange() {
    final newStateJson = _configToJson(_rootConfig);
    if (newStateJson == _currentHistoryNode.stateJson) return;

    final newNode = HistoryNode(stateJson: newStateJson, parent: _currentHistoryNode, timestamp: DateTime.now());
    _currentHistoryNode.addChild(newNode);
    _currentHistoryNode = newNode;
  }

  String _configToJson(DynamicWidgetConfig config) {
    return const JsonEncoder.withIndent('  ').convert(config.toJson());
  }

  String exportConfigToJson() => _configToJson(_rootConfig);

  void loadConfigFromJson(String jsonString) {
    try {
      _rootConfig = DynamicWidgetConfig.fromJson(json.decode(jsonString));
      _recordChange();
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading config from JSON: $e");
    }
  }

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
    _rootConfig = _rootConfig.copy();
    final parent = findWidget(parentId);
    if (parent != null) {
      parent.children.add(DynamicWidgetConfig.empty());
      _recordChange();
      notifyListeners();
    }
  }

  void removeWidget(String id) {
    _rootConfig = _rootConfig.copy();
    _removeWidgetRecursive(id, searchNode: _rootConfig);
  }

  void _removeWidgetRecursive(String id, {required DynamicWidgetConfig searchNode}) {
    final initialCount = searchNode.children.length;
    searchNode.children.removeWhere((child) => child.id == id);
    if (searchNode.children.length < initialCount) {
      _recordChange();
      notifyListeners();
      return;
    }
    for (final child in searchNode.children) {
      _removeWidgetRecursive(id, searchNode: child);
    }
  }

  void updateWidget(String id, DynamicWidgetConfig newConfig) {
    _rootConfig = _rootConfig.copy();
    final parent = _findParent(id);
    if (parent != null) {
      final index = parent.children.indexWhere((w) => w.id == id);
      if (index != -1) {
        parent.children[index] = newConfig;
        _recordChange();
        notifyListeners();
      }
    } else if (_rootConfig.id == id) {
      _rootConfig = newConfig;
      _recordChange();
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
    Future.microtask(notifyListeners);
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
      Future.microtask(notifyListeners);
    }
  }
}

// --- UI COMPONENTS ---

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

class SettingsDrawer extends StatefulWidget {
  final Future<DynamicWidgetConfig?> Function(BuildContext, DynamicWidgetConfig) onEditConfig;
  const SettingsDrawer({super.key, required this.onEditConfig});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  late final TextEditingController _jsonController;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _jsonController = TextEditingController();
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<DashboardState>(context);
    final newJson = state.exportConfigToJson();
    if (_jsonController.text != newJson) {
      _jsonController.text = newJson;
    }

    final isEditMode = state.mode == DashboardMode.edit;

    return Drawer(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 4, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('UI Layout', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.history),
                      tooltip: 'Show Edit History',
                      onPressed: () => setState(() => _showHistory = !_showHistory),
                    ),
                    IconButton(
                      icon: Icon(isEditMode ? Icons.lock_open : Icons.lock),
                      tooltip: isEditMode ? 'View Mode' : 'Edit Mode',
                      onPressed: () => state.setMode(isEditMode ? DashboardMode.view : DashboardMode.edit),
                    ),
                    IconButton(
                      icon: const Icon(Icons.undo),
                      tooltip: 'Undo',
                      onPressed: state.canUndo && isEditMode ? state.undo : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.redo),
                      tooltip: 'Redo',
                      onPressed: state.canRedo && isEditMode ? state.redo : null,
                    ),
                  ],
                )
              ],
            ),
          ),
          const Divider(height: 1),
          if (_showHistory && isEditMode)
            HistoryTreeView(
              historyRoot: state.historyRoot,
              currentHistory: state.currentHistory,
              onNodeSelected: (node) {
                state.jumpToState(node);
              },
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                children: [
                  WidgetTreeEditor(
                    config: state.rootConfig,
                    onEditConfig: widget.onEditConfig,
                    isEditMode: isEditMode,
                  ),
                  if (isEditMode) ...[
                    const Divider(height: 24),
                    ExpansionTile(
                      title: const Text('Raw JSON Config'),
                      leading: const Icon(Icons.code),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextField(
                            controller: _jsonController,
                            maxLines: 10,
                            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Widget Tree JSON'),
                          ),
                        ),
                        ButtonBar(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.save_alt),
                              label: const Text('Load JSON'),
                              onPressed: () {
                                state.loadConfigFromJson(_jsonController.text);
                                Navigator.of(context).pop();
                              },
                            ),
                          ],
                        )
                      ],
                    ),
                  ]
                ],
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

  const DynamicWidgetBuilder({super.key, required this.config, required this.widgetBuilder});

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (config.widgetType) {
      case 'container':
        if (config.children.isEmpty) {
          content = Center(child: Text(config.properties['title'] ?? 'Untitled'));
        } else if (config.children.length == 1) {
          content = DynamicWidgetBuilder(config: config.children.first, widgetBuilder: widgetBuilder);
        } else {
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
        }
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
  final bool isEditMode;

  const WidgetTreeEditor({super.key, required this.config, required this.onEditConfig, required this.isEditMode});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<DashboardState>(context, listen: false);
    return ExpansionTile(
      leading: Icon(Icons.account_tree_outlined, color: Theme.of(context).primaryColor),
      initiallyExpanded: true,
      title: Text(config.properties['title'] ?? config.widgetType),
      subtitle: Text(config.widgetType),
      trailing: isEditMode
          ? Row(
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
            )
          : null,
      children: config.children
          .map((child) => Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Container(
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300, width: 2))),
                  child: WidgetTreeEditor(config: child, onEditConfig: onEditConfig, isEditMode: isEditMode),
                ),
              ))
          .toList(),
    );
  }
}

class HistoryTreeView extends StatefulWidget {
  final HistoryNode historyRoot;
  final HistoryNode currentHistory;
  final ValueChanged<HistoryNode> onNodeSelected;

  const HistoryTreeView({
    super.key,
    required this.historyRoot,
    required this.currentHistory,
    required this.onNodeSelected,
  });

  @override
  State<HistoryTreeView> createState() => _HistoryTreeViewState();
}

class _HistoryTreeViewState extends State<HistoryTreeView> {
  Offset _panOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final painter = _HistoryTreePainter(
      root: widget.historyRoot,
      currentNode: widget.currentHistory,
      onNodeSelected: widget.onNodeSelected,
      context: context,
      panOffset: _panOffset,
    );

    final double requiredWidth = painter.calculateWidth() + 32.0;

    return Container(
      height: 120,
      color: Colors.grey.shade200,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _panOffset += details.delta;
            });
          },
          onTapUp: (details) {
            painter.handleTap(details.localPosition);
          },
          child: CustomPaint(
            size: Size(requiredWidth, 120),
            painter: painter,
          ),
        ),
      ),
    );
  }
}

class _HistoryTreePainter extends CustomPainter {
  final HistoryNode root;
  final HistoryNode currentNode;
  final ValueChanged<HistoryNode> onNodeSelected;
  final BuildContext context;
  final Offset panOffset;

  final Map<String, Rect> _nodeRects = {};
  final Paint _linePaint = Paint()..strokeWidth = 2;
  final Paint _nodePaint = Paint();

  _HistoryTreePainter({
    required this.root,
    required this.currentNode,
    required this.onNodeSelected,
    required this.context,
    required this.panOffset,
  });

  double calculateWidth() {
    return (_calculateMaxDepth(root, 1)) * 60.0;
  }

  int _calculateMaxDepth(HistoryNode node, int depth) {
    if (node.children.isEmpty) {
      return depth;
    }
    int maxDepth = depth;
    for (var child in node.children) {
      maxDepth = max(maxDepth, _calculateMaxDepth(child, depth + 1));
    }
    return maxDepth;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);

    _nodeRects.clear();
    _drawNodeRecursive(canvas, root, 0, size.height / 2);

    canvas.restore();
  }

  _NodeLayoutInfo _drawNodeRecursive(Canvas canvas, HistoryNode node, int depth, double y) {
    final double x = depth * 60.0 + 16;
    final List<_NodeLayoutInfo> childInfos = [];
    double childrenSpan = 0;

    for (final child in node.children) {
      final childInfo = _drawNodeRecursive(canvas, child, depth + 1, y + childrenSpan);
      childInfos.add(childInfo);
      childrenSpan += childInfo.span;
    }

    double currentY = y;
    if (childInfos.isNotEmpty) {
      currentY = (childInfos.first.center.dy + childInfos.last.center.dy) / 2;
    }

    final center = Offset(x, currentY);

    for (final childInfo in childInfos) {
      _linePaint.color = Colors.grey.shade500;
      canvas.drawLine(center, childInfo.center, _linePaint);
    }

    final isCurrent = node.id == currentNode.id;
    _nodePaint.color = isCurrent ? Theme.of(context).primaryColor : Colors.grey.shade600;

    final rect = Rect.fromCircle(center: center, radius: 12);
    _nodeRects[node.id] = rect;
    canvas.drawCircle(rect.center, 12, _nodePaint);

    if (isCurrent) {
      _nodePaint.style = PaintingStyle.stroke;
      _nodePaint.strokeWidth = 3;
      _nodePaint.color = Colors.blueAccent;
      canvas.drawCircle(rect.center, 16, _nodePaint);
      _nodePaint.style = PaintingStyle.fill;
    }

    return _NodeLayoutInfo(center: center, span: childrenSpan > 0 ? childrenSpan : 50.0);
  }

  void handleTap(Offset position) {
    final tappedPosition = position - panOffset;
    HistoryNode? tappedNode;
    for (final entry in _nodeRects.entries) {
      if (entry.value.contains(tappedPosition)) {
        tappedNode = _findNodeById(root, entry.key);
        break;
      }
    }
    if (tappedNode != null) {
      onNodeSelected(tappedNode);
    }
  }

  HistoryNode? _findNodeById(HistoryNode node, String id) {
    if (node.id == id) {
      return node;
    }
    for (final child in node.children) {
      final found = _findNodeById(child, id);
      if (found != null) return found;
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _NodeLayoutInfo {
  final Offset center;
  final double span;
  _NodeLayoutInfo({required this.center, required this.span});
}
