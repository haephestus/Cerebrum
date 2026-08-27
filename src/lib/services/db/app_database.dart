import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'package:cerebrum/services/storage_paths.dart';

part 'app_database.g.dart';

/// Reactive local record-keeping (Drift/SQLite) for the learning center.
///
/// Records & queues live here — not documents. Notes stay JSON files mirroring
/// the daemon note-folder shape; this DB is for things we query and aggregate:
/// engram answer attempts (offline outbox + history) and per-engram mastery/SRS
/// state (Anki-style, computed offline). See docs/drift-migration.md.

@DataClassName('EngramAttemptRow')
class EngramAttempts extends Table {
  TextColumn get attemptId => text()();
  TextColumn get engramId => text()();
  TextColumn get type => text()(); // mcq | flashcard | short_question | long_question
  TextColumn get userId => text()();
  TextColumn get payloadJson => text()();
  IntColumn get targetCognitiveLevel =>
      integer().withDefault(const Constant(1))();
  TextColumn get status =>
      text().withDefault(const Constant('queued'))(); // queued|submitted|graded|failed
  TextColumn get jobId => text().nullable()();
  TextColumn get resultJson => text().nullable()();
  TextColumn get error => text().nullable()();
  BoolColumn get seen => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {attemptId};
}

class EngramMasteryRows extends Table {
  TextColumn get engramId => text()();
  RealColumn get easeFactor => real().withDefault(const Constant(2.5))();
  IntColumn get intervalDays => integer().withDefault(const Constant(0))();
  IntColumn get repetitions => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  TextColumn get lastGrade => text().nullable()();
  TextColumn get masteryState =>
      text().withDefault(const Constant('learning'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {engramId};
}

/// Cached engram content (question + answers) so a quiz can be started with no
/// connection (cold-start offline). Populated from `listEngrams` (fetched with
/// answers); read back when the daemon is unreachable.
class CachedEngrams extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get bubbleId => text().nullable()();
  TextColumn get noteId => text().nullable()();
  TextColumn get type => text()();
  IntColumn get targetCognitiveLevel =>
      integer().withDefault(const Constant(1))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get contentJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [EngramAttempts, EngramMasteryRows, CachedEngrams])
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_open());

  /// App-wide singleton (one SQLite connection).
  static final AppDatabase instance = AppDatabase._();

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(cachedEngrams);
    },
  );

  // -- engram attempts ---------------------------------------------------

  Future<void> upsertAttempt(EngramAttemptsCompanion row) =>
      into(engramAttempts).insertOnConflictUpdate(row);

  Future<EngramAttemptRow?> attempt(String attemptId) =>
      (select(engramAttempts)..where((t) => t.attemptId.equals(attemptId)))
          .getSingleOrNull();

  /// Pending (queued/submitted) attempts, oldest first.
  Future<List<EngramAttemptRow>> pendingAttempts() =>
      (select(engramAttempts)
            ..where((t) => t.status.isIn(const ['queued', 'submitted']))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  Future<EngramAttemptRow?> latestAttemptForEngram(String engramId) =>
      (select(engramAttempts)
            ..where((t) => t.engramId.equals(engramId))
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.createdAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<int> unseenGradedCount() async {
    final count = engramAttempts.attemptId.count();
    final q = selectOnly(engramAttempts)
      ..addColumns([count])
      ..where(
        engramAttempts.status.equals('graded') &
            engramAttempts.seen.equals(false),
      );
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }

  // -- mastery -----------------------------------------------------------

  Future<EngramMasteryRow?> mastery(String engramId) =>
      (select(engramMasteryRows)..where((t) => t.engramId.equals(engramId)))
          .getSingleOrNull();

  Future<void> upsertMastery(EngramMasteryRowsCompanion row) =>
      into(engramMasteryRows).insertOnConflictUpdate(row);

  // -- cached engrams ----------------------------------------------------

  Future<void> upsertCachedEngram(CachedEngramsCompanion row) =>
      into(cachedEngrams).insertOnConflictUpdate(row);

  /// Cached engrams for a scope (mirrors the daemon's list scoping): user, and
  /// optionally a bubble and/or note.
  Future<List<CachedEngram>> cachedEngramsFor({
    required String userId,
    String? bubbleId,
    String? noteId,
  }) {
    return (select(cachedEngrams)
          ..where((t) {
            var cond = t.userId.equals(userId);
            if (bubbleId != null) cond = cond & t.bubbleId.equals(bubbleId);
            if (noteId != null) cond = cond & t.noteId.equals(noteId);
            return cond;
          })
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  static LazyDatabase _open() {
    return LazyDatabase(() async {
      final root = await StoragePaths.cerebrumRoot();
      final file = File('${root.path}/cerebrum.db');
      await file.parent.create(recursive: true);
      return NativeDatabase(file);
    });
  }
}
