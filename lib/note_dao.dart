import 'package:floor/floor.dart';
import 'note.dart';

@dao
abstract class NoteDao {
  @Query('SELECT * FROM notes WHERE isNew = 1 ORDER BY timestamp DESC')
  Stream<List<Note>> watchNewNotes();

  @Query('SELECT * FROM notes WHERE isNew = 0 AND deletedAt IS NULL ORDER BY isPinned DESC, timestamp DESC')
  Stream<List<Note>> watchRegularNotes();

  @Query('SELECT * FROM notes WHERE deletedAt IS NOT NULL ORDER BY deletedAt DESC')
  Stream<List<Note>> watchRecycleBinNotes();

  @Query('SELECT * FROM notes ORDER BY isPinned DESC, timestamp DESC')
  Stream<List<Note>> watchAllNotes();

  @Query('SELECT * FROM notes WHERE id = :id')
  Future<Note?> findNoteById(int id);

  @insert
  Future<int> insertNote(Note note);

  @update
  Future<int> updateNote(Note note);

  // Move to recycle bin instead of deleting
  @Query('UPDATE notes SET deletedAt = :deletedAt WHERE id = :id')
  Future<void> moveToRecycleBin(int id, int deletedAt);

  // Restore from recycle bin
  @Query('UPDATE notes SET deletedAt = NULL WHERE id = :id')
  Future<void> restoreNoteFromRecycleBin(int id);

  // Permanently delete notes older than cutoff
  @Query('DELETE FROM notes WHERE deletedAt IS NOT NULL AND deletedAt < :cutoffTimestamp')
  Future<void> permanentlyDeleteOldNotes(int cutoffTimestamp);

  @Query('UPDATE notes SET isNew = 0 WHERE id = :id')
  Future<void> markNoteAsOld(int id);

  @Query('UPDATE notes SET isPinned = 1 WHERE id = :id')
  Future<void> pinNote(int id);

  @Query('UPDATE notes SET isPinned = 0 WHERE id = :id')
  Future<void> unpinNote(int id);
} 