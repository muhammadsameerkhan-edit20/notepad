// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// **************************************************************************
// FloorGenerator
// **************************************************************************

abstract class $AppDatabaseBuilderContract {
  /// Adds migrations to the builder.
  $AppDatabaseBuilderContract addMigrations(List<Migration> migrations);

  /// Adds a database [Callback] to the builder.
  $AppDatabaseBuilderContract addCallback(Callback callback);

  /// Creates the database and initializes it.
  Future<AppDatabase> build();
}

// ignore: avoid_classes_with_only_static_members
class $FloorAppDatabase {
  /// Creates a database builder for a persistent database.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static $AppDatabaseBuilderContract databaseBuilder(String name) =>
      _$AppDatabaseBuilder(name);

  /// Creates a database builder for an in memory database.
  /// Information stored in an in memory database disappears when the process is killed.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static $AppDatabaseBuilderContract inMemoryDatabaseBuilder() =>
      _$AppDatabaseBuilder(null);
}

class _$AppDatabaseBuilder implements $AppDatabaseBuilderContract {
  _$AppDatabaseBuilder(this.name);

  final String? name;

  final List<Migration> _migrations = [];

  Callback? _callback;

  @override
  $AppDatabaseBuilderContract addMigrations(List<Migration> migrations) {
    _migrations.addAll(migrations);
    return this;
  }

  @override
  $AppDatabaseBuilderContract addCallback(Callback callback) {
    _callback = callback;
    return this;
  }

  @override
  Future<AppDatabase> build() async {
    final path = name != null
        ? await sqfliteDatabaseFactory.getDatabasePath(name!)
        : ':memory:';
    final database = _$AppDatabase();
    database.database = await database.open(
      path,
      _migrations,
      _callback,
    );
    return database;
  }
}

class _$AppDatabase extends AppDatabase {
  _$AppDatabase([StreamController<String>? listener]) {
    changeListener = listener ?? StreamController<String>.broadcast();
  }

  NoteDao? _noteDaoInstance;

  Future<sqflite.Database> open(
    String path,
    List<Migration> migrations, [
    Callback? callback,
  ]) async {
    final databaseOptions = sqflite.OpenDatabaseOptions(
      version: 3,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await callback?.onConfigure?.call(database);
      },
      onOpen: (database) async {
        await callback?.onOpen?.call(database);
      },
      onUpgrade: (database, startVersion, endVersion) async {
        await MigrationAdapter.runMigrations(
            database, startVersion, endVersion, migrations);

        await callback?.onUpgrade?.call(database, startVersion, endVersion);
      },
      onCreate: (database, version) async {
        await database.execute(
            'CREATE TABLE IF NOT EXISTS `notes` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `title` TEXT NOT NULL, `contentJson` TEXT NOT NULL, `timestamp` INTEGER NOT NULL, `isNew` INTEGER NOT NULL, `isPinned` INTEGER NOT NULL, `deletedAt` INTEGER)');

        await callback?.onCreate?.call(database, version);
      },
    );
    return sqfliteDatabaseFactory.openDatabase(path, options: databaseOptions);
  }

  @override
  NoteDao get noteDao {
    return _noteDaoInstance ??= _$NoteDao(database, changeListener);
  }
}

class _$NoteDao extends NoteDao {
  _$NoteDao(
    this.database,
    this.changeListener,
  )   : _queryAdapter = QueryAdapter(database, changeListener),
        _noteInsertionAdapter = InsertionAdapter(
            database,
            'notes',
            (Note item) => <String, Object?>{
                  'id': item.id,
                  'title': item.title,
                  'contentJson': item.contentJson,
                  'timestamp': item.timestamp,
                  'isNew': item.isNew ? 1 : 0,
                  'isPinned': item.isPinned ? 1 : 0,
                  'deletedAt': item.deletedAt
                },
            changeListener),
        _noteUpdateAdapter = UpdateAdapter(
            database,
            'notes',
            ['id'],
            (Note item) => <String, Object?>{
                  'id': item.id,
                  'title': item.title,
                  'contentJson': item.contentJson,
                  'timestamp': item.timestamp,
                  'isNew': item.isNew ? 1 : 0,
                  'isPinned': item.isPinned ? 1 : 0,
                  'deletedAt': item.deletedAt
                },
            changeListener);

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  final InsertionAdapter<Note> _noteInsertionAdapter;

  final UpdateAdapter<Note> _noteUpdateAdapter;

  @override
  Stream<List<Note>> watchNewNotes() {
    return _queryAdapter.queryListStream(
        'SELECT * FROM notes WHERE isNew = 1 ORDER BY timestamp DESC',
        mapper: (Map<String, Object?> row) => Note(
            id: row['id'] as int?,
            title: row['title'] as String,
            contentJson: row['contentJson'] as String,
            timestamp: row['timestamp'] as int,
            isNew: (row['isNew'] as int) != 0,
            isPinned: (row['isPinned'] as int) != 0,
            deletedAt: row['deletedAt'] as int?),
        queryableName: 'notes',
        isView: false);
  }

  @override
  Stream<List<Note>> watchRegularNotes() {
    return _queryAdapter.queryListStream(
        'SELECT * FROM notes WHERE isNew = 0 AND deletedAt IS NULL ORDER BY isPinned DESC, timestamp DESC',
        mapper: (Map<String, Object?> row) => Note(
            id: row['id'] as int?,
            title: row['title'] as String,
            contentJson: row['contentJson'] as String,
            timestamp: row['timestamp'] as int,
            isNew: (row['isNew'] as int) != 0,
            isPinned: (row['isPinned'] as int) != 0,
            deletedAt: row['deletedAt'] as int?),
        queryableName: 'notes',
        isView: false);
  }

  @override
  Stream<List<Note>> watchRecycleBinNotes() {
    return _queryAdapter.queryListStream(
        'SELECT * FROM notes WHERE deletedAt IS NOT NULL ORDER BY deletedAt DESC',
        mapper: (Map<String, Object?> row) => Note(
            id: row['id'] as int?,
            title: row['title'] as String,
            contentJson: row['contentJson'] as String,
            timestamp: row['timestamp'] as int,
            isNew: (row['isNew'] as int) != 0,
            isPinned: (row['isPinned'] as int) != 0,
            deletedAt: row['deletedAt'] as int?),
        queryableName: 'notes',
        isView: false);
  }

  @override
  Stream<List<Note>> watchAllNotes() {
    return _queryAdapter.queryListStream(
        'SELECT * FROM notes ORDER BY isPinned DESC, timestamp DESC',
        mapper: (Map<String, Object?> row) => Note(
            id: row['id'] as int?,
            title: row['title'] as String,
            contentJson: row['contentJson'] as String,
            timestamp: row['timestamp'] as int,
            isNew: (row['isNew'] as int) != 0,
            isPinned: (row['isPinned'] as int) != 0,
            deletedAt: row['deletedAt'] as int?),
        queryableName: 'notes',
        isView: false);
  }

  @override
  Future<Note?> findNoteById(int id) async {
    return _queryAdapter.query('SELECT * FROM notes WHERE id = ?1',
        mapper: (Map<String, Object?> row) => Note(
            id: row['id'] as int?,
            title: row['title'] as String,
            contentJson: row['contentJson'] as String,
            timestamp: row['timestamp'] as int,
            isNew: (row['isNew'] as int) != 0,
            isPinned: (row['isPinned'] as int) != 0,
            deletedAt: row['deletedAt'] as int?),
        arguments: [id]);
  }

  @override
  Future<void> moveToRecycleBin(
    int id,
    int deletedAt,
  ) async {
    await _queryAdapter.queryNoReturn(
        'UPDATE notes SET deletedAt = ?2 WHERE id = ?1',
        arguments: [id, deletedAt]);
  }

  @override
  Future<void> restoreNoteFromRecycleBin(int id) async {
    await _queryAdapter.queryNoReturn(
        'UPDATE notes SET deletedAt = NULL WHERE id = ?1',
        arguments: [id]);
  }

  @override
  Future<void> permanentlyDeleteOldNotes(int cutoffTimestamp) async {
    await _queryAdapter.queryNoReturn(
        'DELETE FROM notes WHERE deletedAt IS NOT NULL AND deletedAt < ?1',
        arguments: [cutoffTimestamp]);
  }

  @override
  Future<void> markNoteAsOld(int id) async {
    await _queryAdapter.queryNoReturn(
        'UPDATE notes SET isNew = 0 WHERE id = ?1',
        arguments: [id]);
  }

  @override
  Future<void> pinNote(int id) async {
    await _queryAdapter.queryNoReturn(
        'UPDATE notes SET isPinned = 1 WHERE id = ?1',
        arguments: [id]);
  }

  @override
  Future<void> unpinNote(int id) async {
    await _queryAdapter.queryNoReturn(
        'UPDATE notes SET isPinned = 0 WHERE id = ?1',
        arguments: [id]);
  }

  @override
  Future<int> insertNote(Note note) {
    return _noteInsertionAdapter.insertAndReturnId(
        note, OnConflictStrategy.abort);
  }

  @override
  Future<int> updateNote(Note note) {
    return _noteUpdateAdapter.updateAndReturnChangedRows(
        note, OnConflictStrategy.abort);
  }
}
