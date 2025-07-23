import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:floor/floor.dart';
import 'dart:async';
import 'note.dart';
import 'note_dao.dart';
import 'app_database.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'draw_screen.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Set up Crashlytics error handling
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;

  // Log app open event
  await FirebaseAnalytics.instance.logAppOpen();

  // Fetch remote config
  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(RemoteConfigSettings(
    fetchTimeout: const Duration(seconds: 10),
    minimumFetchInterval: const Duration(hours: 1),
  ));
  await remoteConfig.fetchAndActivate();
  // Example: print a remote config value
  print('Welcome message: ' + remoteConfig.getString('welcome_message'));

  final directory = await getApplicationDocumentsDirectory();
  final database = await $FloorAppDatabase
      .databaseBuilder('${directory.path}/app_database.db')
      .addMigrations([migration1to2, migration2to3])
      .build();

  // Automatic cleanup: delete notes in recycle bin older than 30 days
  final cutoff = DateTime.now().millisecondsSinceEpoch - 30 * 24 * 60 * 60 * 1000;
  await database.noteDao.permanentlyDeleteOldNotes(cutoff);

  runApp(NotepadApp(database: database, remoteConfig: remoteConfig));
}

class NotepadApp extends StatefulWidget {
  final AppDatabase database;
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  final FirebaseRemoteConfig remoteConfig;
  NotepadApp({super.key, required this.database, required this.remoteConfig});

  @override
  State<NotepadApp> createState() => _NotepadAppState();
}

enum AppTheme { dark, light, blue, green }

final appThemes = {
  AppTheme.dark: ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    scaffoldBackgroundColor: Colors.black,
    cardColor: Colors.grey[900],
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.blue,
    ),
  ),
  AppTheme.light: ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    scaffoldBackgroundColor: Colors.white,
    cardColor: Colors.grey[100],
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.blue,
    ),
  ),
  AppTheme.blue: ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    scaffoldBackgroundColor: Colors.blue[900],
    cardColor: Colors.blue[800],
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.blue,
    ),
  ),
  AppTheme.green: ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.green,
    scaffoldBackgroundColor: Colors.green[900],
    cardColor: Colors.green[800],
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.green,
    ),
  ),
};

class _NotepadAppState extends State<NotepadApp> {
  AppTheme _appTheme = AppTheme.dark;
  bool _isGrid = true;

  void _toggleTheme(AppTheme theme) {
    setState(() {
      _appTheme = theme;
    });
  }

  void _toggleGridTile() {
    setState(() {
      _isGrid = !_isGrid;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notepad',
      theme: appThemes[_appTheme],
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        quill.FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
      ],
      home: NotesPage(
        database: widget.database,
        analytics: widget.analytics,
        remoteConfig: widget.remoteConfig,
        onThemeChanged: _toggleTheme,
        currentTheme: _appTheme,
        isGrid: _isGrid,
        onToggleGridTile: _toggleGridTile,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum NotesViewMode { gridSmall, gridMedium, gridLarge, list, simpleList }

class NotesPage extends StatefulWidget {
  final AppDatabase database;
  final FirebaseAnalytics analytics;
  final FirebaseRemoteConfig remoteConfig;
  final void Function(AppTheme) onThemeChanged;
  final AppTheme currentTheme;
  final bool isGrid;
  final VoidCallback onToggleGridTile;
  const NotesPage({super.key, required this.database, required this.analytics, required this.remoteConfig, required this.onThemeChanged, required this.currentTheme, required this.isGrid, required this.onToggleGridTile});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  bool _sortDesc = true;
  String _searchQuery = '';
  String _sortType = 'modified'; // 'modified' or 'created'
  List<String> _recentSearches = [];
  NotesViewMode _viewMode = NotesViewMode.gridLarge;
  bool _selectMode = false;
  Set<int> _selectedNoteIds = {};
  bool _fetchingRemoteConfig = false;
  String? _welcomeMessage;

  @override
  void initState() {
    super.initState();
    _welcomeMessage = widget.remoteConfig.getString('welcome_message');
  }

  Future<void> _forceFetchRemoteConfig() async {
    setState(() => _fetchingRemoteConfig = true);
    try {
      await widget.remoteConfig.fetchAndActivate();
      final msg = widget.remoteConfig.getString('welcome_message');
      setState(() {
        _welcomeMessage = msg;
        _fetchingRemoteConfig = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Remote Config updated!')),
        );
      }
    } catch (e) {
      setState(() => _fetchingRemoteConfig = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch Remote Config: $e')),
        );
      }
    }
  }

  void _toggleSort() {
    setState(() {
      _sortDesc = !_sortDesc;
    });
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  void _startSearch() async {
    print('Opening search delegate');
    final result = await showSearch<_SearchResult?>(
      context: context,
      delegate: _NotesSearchDelegate(
        database: widget.database,
        initialQuery: _searchQuery,
        recentSearches: _recentSearches,
        onQueryChanged: (query, mode) {
          setState(() {
            _searchQuery = query;
          });
        },
      ),
    );
    if (result != null && result.query.isNotEmpty) {
      setState(() {
        _searchQuery = result.query;
        if (!_recentSearches.contains(result.query)) {
          _recentSearches.insert(0, result.query);
          if (_recentSearches.length > 5) _recentSearches = _recentSearches.sublist(0, 5);
        }
      });
    }
  }

  Future<void> _exportToPdf(List<Note> notes) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('My Notes')),
          ...notes.map((note) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(note.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                pw.SizedBox(height: 4),
                pw.Text(note.contentJson),
                pw.SizedBox(height: 4),
                pw.Text('Date: ${DateTime.fromMillisecondsSinceEpoch(note.timestamp)}', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                pw.Divider(),
              ],
            ),
          )),
        ],
      ),
    );
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'notes_export.pdf'));
    await file.writeAsBytes(await pdf.save());
    // Offer to share
    await Share.shareXFiles([XFile(file.path)], text: 'My exported notes PDF');
  }

  List<Note> _filterNotes(List<Note> notes) {
    // Only show notes not in recycle bin
    final activeNotes = notes.where((note) => note.deletedAt == null).toList();
    if (_searchQuery.isEmpty) return _sortNotes(activeNotes);
    final query = _searchQuery.toLowerCase();
    final filtered = activeNotes.where((note) =>
      note.title.toLowerCase().contains(query) ||
      note.contentJson.toLowerCase().contains(query)
    ).toList();
    return _sortNotes(filtered);
  }

  List<Note> _sortNotes(List<Note> notes) {
    notes.sort((a, b) {
      int cmp;
      if (_sortType == 'created') {
        cmp = a.id!.compareTo(b.id!); // Assuming id is auto-incremented
      } else {
        cmp = a.timestamp.compareTo(b.timestamp);
      }
      return _sortDesc ? -cmp : cmp;
    });
    return notes;
  }

  void _toggleSortOrder() {
    setState(() {
      _sortDesc = !_sortDesc;
    });
  }

  void _selectSortType(String? type) {
    if (type != null && type != _sortType) {
      setState(() {
        _sortType = type;
      });
    }
  }

  void _showViewModeDialog() async {
    final selected = await showDialog<NotesViewMode>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Select View', style: TextStyle(color: Colors.white)),
        children: [
          _viewModeOption(NotesViewMode.gridSmall, 'Grid (small)'),
          _viewModeOption(NotesViewMode.gridMedium, 'Grid (medium)'),
          _viewModeOption(NotesViewMode.gridLarge, 'Grid (large)'),
          _viewModeOption(NotesViewMode.list, 'List'),
          _viewModeOption(NotesViewMode.simpleList, 'Simple list'),
        ],
      ),
    );
    if (selected != null && selected != _viewMode) {
      setState(() => _viewMode = selected);
    }
  }

  Widget _viewModeOption(NotesViewMode mode, String label) {
    final isSelected = _viewMode == mode;
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, mode),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.deepOrange : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedNoteIds.clear();
    });
  }

  void _toggleNoteSelected(int noteId) {
    setState(() {
      if (_selectedNoteIds.contains(noteId)) {
        _selectedNoteIds.remove(noteId);
      } else {
        _selectedNoteIds.add(noteId);
      }
    });
  }

  void _selectAllNotes(List<Note> notes) {
    setState(() {
      if (_selectedNoteIds.length == notes.length) {
        _selectedNoteIds.clear();
      } else {
        _selectedNoteIds = notes.map((n) => n.id!).toSet();
      }
    });
  }

  Future<void> _deleteSelectedNotes(List<Note> notes) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final note in notes) {
      if (_selectedNoteIds.contains(note.id)) {
        await widget.database.noteDao.moveToRecycleBin(note.id!, now);
        await widget.analytics.logEvent(name: 'delete_note', parameters: {'note_id': note.id});
      }
    }
    setState(() {
      _selectMode = false;
      _selectedNoteIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortLabel = _sortType == 'created' ? 'Date created' : 'Date modified';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Open navigation menu',
          ),
        ),
      ),
      drawer: _NotesDrawer(
        database: widget.database,
        onThemeChanged: widget.onThemeChanged,
        currentTheme: widget.currentTheme,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: StreamBuilder<List<Note>>(
            stream: Rx.combineLatest2<List<Note>, List<Note>, List<Note>>(
              widget.database.noteDao.watchNewNotes(),
              widget.database.noteDao.watchRegularNotes(),
              (newNotes, regularNotes) => [...newNotes, ...regularNotes],
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.red)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final allNotes = _filterNotes(snapshot.data!);
              if (allNotes.isEmpty) {
                return const Center(child: Text('No notes yet.', style: TextStyle(color: Colors.white70)));
              }
              // Header widgets
              final header = <Widget>[
                const SizedBox(height: 16),
                if ((_welcomeMessage ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _welcomeMessage!,
                            style: TextStyle(
                              color: isDark ? Colors.orangeAccent : Colors.deepOrange,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _fetchingRemoteConfig
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.blue),
                                tooltip: 'Fetch Remote Config',
                                onPressed: _forceFetchRemoteConfig,
                              ),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
                Text(
                  'All notes',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${allNotes.length} notes',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!_selectMode) ...[
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.white70),
                        onPressed: _toggleSelectMode,
                      ),
                    ] else ...[
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        onPressed: () => _deleteSelectedNotes(allNotes),
                      ),
                      Checkbox(
                        value: _selectedNoteIds.length == allNotes.length && allNotes.isNotEmpty,
                        onChanged: (_) => _selectAllNotes(allNotes),
                        checkColor: Colors.black,
                        activeColor: Colors.white,
                      ),
                      const Text('Select All', style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 12),
                      Text('${_selectedNoteIds.length} selected', style: const TextStyle(color: Colors.white70)),
                    ],
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white70),
                      onSelected: (value) {
                        if (value == 'view') {
                          _showViewModeDialog();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'view', child: Text('View')),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    PopupMenuButton<String>(
                      onSelected: _selectSortType,
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'modified', child: Text('Date modified')),
                        const PopupMenuItem(value: 'created', child: Text('Date created')),
                      ],
                      child: Row(
                        children: [
                          Icon(Icons.sort, color: Colors.white70, size: 18),
                          const SizedBox(width: 4),
                          Text(sortLabel, style: TextStyle(color: Colors.white70)),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: _toggleSortOrder,
                            child: Icon(_sortDesc ? Icons.arrow_downward : Icons.arrow_upward, color: Colors.white70, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: TextField(
                    style: TextStyle(color: isDark ? Colors.white : Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Search notes...',
                      hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                      prefixIcon: Icon(Icons.search, color: isDark ? Colors.white54 : Colors.black54),
                      filled: true,
                      fillColor: isDark ? Colors.grey[900] : Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
              ];
              // Main notes display
              switch (_viewMode) {
                case NotesViewMode.gridSmall:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...header,
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.8,
                          ),
                          itemCount: allNotes.length,
                          itemBuilder: (context, index) {
                            final note = allNotes[index];
                            return _NoteCard(
                              note: note,
                              database: widget.database,
                              isDark: isDark,
                              analytics: widget.analytics,
                              onViewModeSelect: _showViewModeDialog,
                              selectMode: _selectMode,
                              selected: _selectedNoteIds.contains(note.id),
                              onSelect: () => _toggleNoteSelected(note.id!),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                case NotesViewMode.gridMedium:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...header,
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: allNotes.length,
                          itemBuilder: (context, index) {
                            final note = allNotes[index];
                            return _NoteCard(
                              note: note,
                              database: widget.database,
                              isDark: isDark,
                              analytics: widget.analytics,
                              onViewModeSelect: _showViewModeDialog,
                              selectMode: _selectMode,
                              selected: _selectedNoteIds.contains(note.id),
                              onSelect: () => _toggleNoteSelected(note.id!),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                case NotesViewMode.gridLarge:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...header,
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 2.2,
                          ),
                          itemCount: allNotes.length,
                          itemBuilder: (context, index) {
                            final note = allNotes[index];
                            return _NoteCard(
                              note: note,
                              database: widget.database,
                              isDark: isDark,
                              analytics: widget.analytics,
                              onViewModeSelect: _showViewModeDialog,
                              selectMode: _selectMode,
                              selected: _selectedNoteIds.contains(note.id),
                              onSelect: () => _toggleNoteSelected(note.id!),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                case NotesViewMode.list:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...header,
                      Expanded(
                        child: ListView.builder(
                          itemCount: allNotes.length,
                          itemBuilder: (context, index) {
                            final note = allNotes[index];
                            return _NoteTile(
                              note: note,
                              database: widget.database,
                              isDark: isDark,
                              analytics: widget.analytics,
                              selectMode: _selectMode,
                              selected: _selectedNoteIds.contains(note.id),
                              onSelect: () => _toggleNoteSelected(note.id!),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                case NotesViewMode.simpleList:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...header,
                      Expanded(
                        child: ListView.builder(
                          itemCount: allNotes.length,
                          itemBuilder: (context, index) {
                            final note = allNotes[index];
                            return ListTile(
                              title: Text(note.title, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                            );
                          },
                        ),
                      ),
                    ],
                  );
              }
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteEditPage(database: widget.database, analytics: widget.analytics),
          ),
        ),
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }
    return '${date.day} ${_monthName(date.month)}';
  }

  String _monthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }
}

class _SearchResult {
  final String query;
  final String mode;
  _SearchResult(this.query, this.mode);
}

class _NotesSearchDelegate extends SearchDelegate<_SearchResult?> {
  final AppDatabase database;
  final String initialQuery;
  final String initialMode;
  final List<String> recentSearches;
  final void Function(String, String) onQueryChanged;
  String _mode;
  _NotesSearchDelegate({
    required this.database,
    required this.initialQuery,
    this.initialMode = 'both',
    required this.recentSearches,
    required this.onQueryChanged,
  }) : _mode = initialMode {
    query = initialQuery;
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    DropdownButton<String>(
      value: _mode,
      dropdownColor: Colors.grey[900],
      style: const TextStyle(color: Colors.white),
      underline: Container(),
      items: const [
        DropdownMenuItem(value: 'both', child: Text('All')),
        DropdownMenuItem(value: 'title', child: Text('Title')),
        DropdownMenuItem(value: 'content', child: Text('Content')),
      ],
      onChanged: (value) {
        if (value != null) {
          _mode = value;
          onQueryChanged(query, _mode);
          showSuggestions(context);
        }
      },
    ),
    IconButton(
      icon: const Icon(Icons.clear),
      onPressed: () {
        query = '';
        onQueryChanged(query, _mode);
        showSuggestions(context);
      },
    ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      onQueryChanged('', _mode);
      close(context, null);
    },
  );

  @override
  Widget buildResults(BuildContext context) {
    print('buildResults called');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onQueryChanged(query, _mode);
    });
    return _buildLiveResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    print('buildSuggestions called');
    return buildResults(context);
  }

  Widget _buildLiveResults(BuildContext context) {
    print('_buildLiveResults called');
    return StreamBuilder<List<Note>>(
      stream: _allNotesStream(database),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allNotes = snapshot.data!;
        final q = query.toLowerCase();
        final filtered = allNotes.where((note) {
          if (_mode == 'title') return note.title.toLowerCase().contains(q);
          if (_mode == 'content') return note.contentJson.toLowerCase().contains(q);
          return note.title.toLowerCase().contains(q) || note.contentJson.toLowerCase().contains(q);
        }).toList();
        if (filtered.isEmpty) {
          return const Center(child: Text('No results found', style: TextStyle(color: Colors.white70, fontSize: 18)));
        }
        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final note = filtered[index];
            return ListTile(
              title: _highlightMatch(note.title, query),
              subtitle: _highlightMatch(note.contentJson, query),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditPage(database: database, analytics: database is AppDatabase ? (context.findAncestorWidgetOfExactType<NotesPage>()?.analytics ?? FirebaseAnalytics.instance) : FirebaseAnalytics.instance, note: note),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Stream<List<Note>> _allNotesStream(AppDatabase db) {
    return Rx.combineLatest2<List<Note>, List<Note>, List<Note>>(
      db.noteDao.watchNewNotes(),
      db.noteDao.watchRegularNotes(),
      (newNotes, regularNotes) => [...newNotes, ...regularNotes],
    );
  }

  Widget _highlightMatch(String text, String query) {
    if (query.isEmpty) return Text(text, style: const TextStyle(color: Colors.white));
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int index;
    while ((index = lower.indexOf(q, start)) != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: const TextStyle(color: Colors.white)));
      }
      spans.add(TextSpan(text: text.substring(index, index + q.length), style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black)));
      start = index + q.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: const TextStyle(color: Colors.white)));
    }
    return RichText(text: TextSpan(children: spans));
  }
}

class _NotesDrawer extends StatelessWidget {
  final AppDatabase database;
  final void Function(AppTheme) onThemeChanged;
  final AppTheme currentTheme;
  const _NotesDrawer({required this.database, required this.onThemeChanged, required this.currentTheme});

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 1),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white70),
                    onPressed: () => _openSettings(context),
                    tooltip: 'Settings',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<Note>>(
                stream: database.noteDao.watchAllNotes(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.red)));
                  }
                  final notesCount = snapshot.data?.length ?? 0;
                  return _DrawerItem(
                    icon: Icons.notes,
                    label: 'All notes',
                    selected: true,
                    trailing: Text('$notesCount', style: const TextStyle(color: Colors.white)),
                  );
                },
              ),
              const SizedBox(height: 16),
              _DrawerItem(
                icon: Icons.delete,
                label: 'Recycle bin',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecycleBinPage(database: database),
                    ),
                  );
                },
              ),
              const Divider(height: 32, color: Colors.white24),
              const SizedBox(height: 24),
              Text('Themes', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _ThemeSelector(currentTheme: currentTheme, onThemeChanged: onThemeChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final AppTheme currentTheme;
  final void Function(AppTheme) onThemeChanged;
  const _ThemeSelector({required this.currentTheme, required this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: AppTheme.values.map((theme) {
        final isSelected = theme == currentTheme;
        return GestureDetector(
          onTap: () => onThemeChanged(theme),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white24 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Text(
              theme.name[0].toUpperCase() + theme.name.substring(1),
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final AppDatabase database;
  final bool isDark;
  final FirebaseAnalytics analytics;
  final VoidCallback? onTap;
  final VoidCallback? onViewModeSelect;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onSelect;
  const _NoteCard({required this.note, required this.database, required this.isDark, required this.analytics, this.onTap, this.onViewModeSelect, this.selectMode = false, this.selected = false, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selectMode ? onSelect : (onTap ?? () {
        analytics.logEvent(
          name: 'open_note',
          parameters: {'note_id': note.id, 'title_length': note.title.length},
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteEditPage(
              database: database,
              analytics: analytics,
              note: note,
            ),
          ),
        );
      }),
      borderRadius: BorderRadius.circular(18),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        color: Theme.of(context).cardColor,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (selectMode) ...[
                    Checkbox(
                      value: selected,
                      onChanged: (_) => onSelect?.call(),
                      checkColor: Colors.black,
                      activeColor: Colors.white,
                    ),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 48, // Limit preview height
                      child: quill.QuillEditor.basic(
                        controller: quill.QuillController(
                          document: quill.Document.fromJson(jsonDecode(note.contentJson)),
                          selection: const TextSelection.collapsed(offset: 0),
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: (value) async {
                      if (value == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NoteEditPage(database: database, analytics: analytics, note: note),
                          ),
                        );
                      } else if (value == 'view') {
                        if (onViewModeSelect != null) {
                          onViewModeSelect!();
                        }
                      } else if (value == 'pin') {
                        await database.noteDao.pinNote(note.id!);
                        (context as Element).markNeedsBuild();
                      } else if (value == 'unpin') {
                        await database.noteDao.unpinNote(note.id!);
                        (context as Element).markNeedsBuild();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'view', child: Text('View')),
                      if (!note.isPinned)
                        const PopupMenuItem(value: 'pin', child: Text('Pin favourites to top')),
                      if (note.isPinned)
                        const PopupMenuItem(value: 'unpin', child: Text('Unpin from top')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                note.title,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(note.timestamp),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.orangeAccent),
                  onPressed: onTap ?? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NoteEditPage(
                        database: database,
                        analytics: analytics,
                        note: note,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }
    return '${date.day} ${_monthName(date.month)}';
  }

  String _monthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final AppDatabase database;
  final bool isDark;
  final FirebaseAnalytics analytics;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onSelect;
  const _NoteTile({required this.note, required this.database, required this.isDark, required this.analytics, this.selectMode = false, this.selected = false, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selectMode
          ? onSelect
          : () {
             analytics.logEvent(
               name: 'open_note',
               parameters: {'note_id': note.id, 'title_length': note.title.length},
             );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NoteEditPage(
                      database: database,
                      analytics: analytics,
                      note: note,
                    ),
                  ),
                );
              },
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        tileColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(note.title, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
        subtitle: SizedBox(
          height: 32, // Limit preview height
          child: quill.QuillEditor.basic(
            controller: quill.QuillController(
              document: quill.Document.fromJson(jsonDecode(note.contentJson)),
              selection: const TextSelection.collapsed(offset: 0),
            ),
          ),
        ),
        trailing: selectMode
            ? Checkbox(
                value: selected,
                onChanged: (_) => onSelect?.call(),
                checkColor: Colors.black,
                activeColor: Colors.white,
              )
            : IconButton(
                icon: const Icon(Icons.edit, color: Colors.orangeAccent),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NoteEditPage(
                      database: database,
                      analytics: analytics,
                      note: note,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class NoteEditPage extends StatefulWidget {
  final AppDatabase database;
  final Note? note;
  final FirebaseAnalytics analytics;
  const NoteEditPage({super.key, required this.database, required this.analytics, this.note});

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late quill.QuillController _quillController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    if (widget.note?.contentJson != null && widget.note!.contentJson.isNotEmpty) {
      final doc = quill.Document.fromJson(jsonDecode(widget.note!.contentJson));
      _quillController = quill.QuillController(document: doc, selection: const TextSelection.collapsed(offset: 0));
    } else {
      _quillController = quill.QuillController.basic();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (_formKey.currentState!.validate()) {
      final title = _titleController.text.trim();
      final contentJson = jsonEncode(_quillController.document.toDelta().toJson());
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      if (widget.note == null) {
        await widget.database.noteDao.insertNote(
          Note(title: title, contentJson: contentJson, timestamp: timestamp),
        );
        await widget.analytics.logEvent(name: 'create_note', parameters: {'title_length': title.length});
      } else {
        await widget.database.noteDao.updateNote(
          Note(
            id: widget.note!.id,
            title: title,
            contentJson: contentJson,
            timestamp: timestamp,
            isNew: widget.note!.isNew,
            isPinned: widget.note!.isPinned,
          ),
        );
        await widget.analytics.logEvent(name: 'update_note', parameters: {'note_id': widget.note!.id, 'title_length': title.length});
      }
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Title', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        // No actions
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: TextFormField(
              controller: _titleController,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Title',
                hintStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white54),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                fillColor: Colors.black,
                filled: true,
              ),
              textInputAction: TextInputAction.done,
              validator: (value) => value == null || value.isEmpty ? 'Enter a title' : null,
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: quill.QuillEditor.basic(
                  controller: _quillController,
                ),
              ),
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: quill.QuillSimpleToolbar(
              controller: _quillController,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveNote,
        child: const Icon(Icons.save),
        backgroundColor: Colors.blue,
      ),
    );
  }
}

class _NoteEditorToolbar extends StatelessWidget {
  final double fontSize;
  final ValueChanged<double> onFontSizeChange;
  final VoidCallback onFontSizeInc;
  final VoidCallback onFontSizeDec;
  final VoidCallback onDraw;
  final VoidCallback onShare;
  final VoidCallback onAlign;
  final VoidCallback onStyle;
  final VoidCallback onCursorLeft;
  final VoidCallback onCursorRight;
  const _NoteEditorToolbar({
    required this.fontSize,
    required this.onFontSizeChange,
    required this.onFontSizeInc,
    required this.onFontSizeDec,
    required this.onDraw,
    required this.onShare,
    required this.onAlign,
    required this.onStyle,
    required this.onCursorLeft,
    required this.onCursorRight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.gesture, color: Colors.white, size: 28),
            onPressed: onDraw,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.email, color: Colors.white, size: 24),
            onPressed: onShare,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.format_align_left, color: Colors.white, size: 24),
            onPressed: onAlign,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.text_fields, color: Colors.white, size: 24),
            onPressed: onStyle,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.format_size, color: Colors.white, size: 24),
            onPressed: onFontSizeInc,
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              final newSize = await showDialog<double>(
                context: context,
                builder: (context) {
                  double tempSize = fontSize;
                  return AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: const Text('Font Size', style: TextStyle(color: Colors.white)),
                    content: StatefulBuilder(
                      builder: (context, setState) {
                        return Slider(
                          value: tempSize,
                          min: 10,
                          max: 40,
                          divisions: 30,
                          label: tempSize.round().toString(),
                          onChanged: (value) => setState(() => tempSize = value),
                        );
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, tempSize),
                        child: const Text('OK', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  );
                },
              );
              if (newSize != null) onFontSizeChange(newSize);
            },
            child: Text(fontSize.round().toString(), style: const TextStyle(color: Colors.white, fontSize: 18)),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
            onPressed: onCursorLeft,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
            onPressed: onCursorRight,
          ),
          const Spacer(),
          const Text('1/1', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _DrawerItem({required this.icon, required this.label, this.selected = false, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: selected
          ? BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: trailing,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        dense: true,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[900],
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text('About Us', style: TextStyle(color: Colors.white)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('About Us'),
                  content: const Text('''Welcome to NotePad — your simple, fast, and reliable place to write down everything that matters.

At NotePad, we believe that great ideas deserve a home. Whether it's a quick to-do list, a personal journal entry, class notes, or random thoughts — our app is designed to help you capture it all with ease.

Built with a focus on speed, simplicity, and privacy, NotePad offers a clutter-free writing experience so you can focus on your words, not distractions. No unnecessary features — just a smooth space for your thoughts.

Thank you for choosing NotePad. Your notes, your way. This app is created by Muhammad Sameer an intern developer at HBN Technologies'''),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Colors.white),
            title: const Text('Privacy Policy', style: TextStyle(color: Colors.white)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Privacy Policy'),
                  content: const SingleChildScrollView(
                    child: Text('''🔐 Privacy Policy
At NotePad, your privacy is our priority. We are committed to keeping your personal information safe and secure.

What We Collect:
We do NOT collect or store any personal data.

All your notes are saved locally on your device, unless you use cloud backup options (e.g., Google Drive), which are entirely controlled by you.

Permissions:
If the app asks for any permissions (like storage access), it is only to save your notes securely on your device. We don’t access, use, or share your personal files.

Third-Party Services:
If our app uses any third-party tools (e.g., analytics or ads), we ensure they follow strict privacy standards. We’ll clearly let you know if any such services are involved.

Your Control:
You are always in control of your data. You can delete or manage your notes at any time.

Changes to Policy:
If we ever make updates to this privacy policy, we’ll inform you inside the app so you’re always aware.

If you have any questions or concerns, feel free to contact us at [your email/contact here].

Thank you for trusting NotePad.'''),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class RecycleBinPage extends StatelessWidget {
  final AppDatabase database;
  const RecycleBinPage({super.key, required this.database});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[900],
      body: StreamBuilder<List<Note>>(
        stream: database.noteDao.watchRecycleBinNotes(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data!;
          if (notes.isEmpty) {
            return const Center(child: Text('Recycle bin is empty', style: TextStyle(color: Colors.white70)));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                color: Colors.grey[850],
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ListTile(
                  title: Text(note.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    DateTime.fromMillisecondsSinceEpoch(note.deletedAt ?? 0).toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.green),
                        tooltip: 'Restore',
                        onPressed: () async {
                          await database.noteDao.restoreNoteFromRecycleBin(note.id!);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note restored')));
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        tooltip: 'Delete forever',
                        onPressed: () async {
                          await database.noteDao.permanentlyDeleteOldNotes(DateTime.now().millisecondsSinceEpoch + 1);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note permanently deleted')));
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
