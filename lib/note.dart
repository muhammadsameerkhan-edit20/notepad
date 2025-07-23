import 'package:floor/floor.dart';

@Entity(tableName: 'notes')
class Note {
  @PrimaryKey(autoGenerate: true)
  final int? id;
  final String title;
  final String contentJson;
  final int timestamp;
  final bool isNew;
  final bool isPinned;
  final int? deletedAt; // null if not in recycle bin

  Note({this.id, required this.title, required this.contentJson, required this.timestamp, this.isNew = true, this.isPinned = false, this.deletedAt});
} 