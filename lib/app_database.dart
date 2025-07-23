import 'dart:async';
import 'package:floor/floor.dart';
import 'note.dart';
import 'note_dao.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

part 'app_database.g.dart';

// Example migration for adding isNew and isPinned fields:
final migration1to2 = Migration(1, 2, (database) async {
  await database.execute('ALTER TABLE notes ADD COLUMN isNew INTEGER NOT NULL DEFAULT 1');
  await database.execute('ALTER TABLE notes ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0');
});
// Add migration for deletedAt field
final migration2to3 = Migration(2, 3, (database) async {
  await database.execute('ALTER TABLE notes ADD COLUMN deletedAt INTEGER');
});
// When building the database, add:
// final database = await $FloorAppDatabase
//     .databaseBuilder('app_database.db')
//     .addMigrations([migration1to2])
//     .build();

@Database(version: 3, entities: [Note])
abstract class AppDatabase extends FloorDatabase {
  NoteDao get noteDao;
} 