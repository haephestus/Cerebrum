// ══ CROSS-REPO CONTRACT: engram models ⇄ daemon engram content dataclasses ══
// These mirror the daemon's Engram/*.content shapes (see daemon
// cerebrum_core/engrams/core/types.py). Field JSON keys must match.
//
//  • Answer-bearing fields (McqContent.correctOption, ShortQuestionItem
//    .expectedAnswer, LongQuestionContent.answer, LongQuestionPart.markScheme)
//    are STRIPPED by the daemon's `_sanitize_for_presentation` in the default
//    student view — they arrive only when fetched with include_answers=true.
//    Nullable on purpose; the client reveals them only after an answer.
//  • ShortQuestionItem.questionNumber is the identity the daemon matches
//    submitted `question_index` against (ai_grading.questions_by_index =
//    {q.question_number: q}). Submit MUST send question_index == questionNumber
//    or the answer is dropped/scored 0. See learning_center_api.submitShortQuestion.
//  • Schedule is daemon-owned: `scheduled_at` (ISO-8601 UTC due time) and
//    `state` (daemon vocabulary) are OPTIONAL on every engram. The dashboard
//    renders due dates/times ONLY from `scheduled_at`; absent → the item is
//    listed with no due time, never a synthesized one (homepage-dashboard
//    Phase 2 honesty rule). NOTE: EngramStore.cacheRaw stores the engram row
//    WITHOUT these fields (Drift column subset), so offline listings rebuild
//    with a null schedule — by design, until a Drift migration adds the column.
// ════════════════════════════════════════════════════════════════════════════
enum EngramType { mcq, flashcard, shortQuestion, longQuestion, unknown }

EngramType _parseEngramType(String raw) {
  switch (raw) {
    case 'mcq':
      return EngramType.mcq;
    case 'flashcard':
      return EngramType.flashcard;
    case 'short_question':
      return EngramType.shortQuestion;
    case 'long_question':
      return EngramType.longQuestion;
    default:
      return EngramType.unknown;
  }
}

abstract class EngramContent {}

class McqContent extends EngramContent {
  final int findingIndex;
  final int questionNumber;
  final String stem;
  final Map<String, String> options; // {"A": "...", "B": "...", ...}
  final String severity;

  /// The correct option key (e.g. "B"). Normally **absent**: the daemon
  /// deliberately strips `correct_option` from student-facing payloads
  /// (`_sanitize_for_presentation`) so answers can't be scraped — it's only
  /// present in the review/admin view (`list?include_answers=true`). So offline
  /// MCQ grading generally can't happen by design; MCQ scoring defers to the
  /// server (queue offline → score on reconnect). This field only enables local
  /// grading in the answers-included case. Nullable → absence degrades to the
  /// server path.
  final String? correctOption;

  McqContent({
    required this.findingIndex,
    required this.questionNumber,
    required this.stem,
    required this.options,
    required this.severity,
    this.correctOption,
  });

  factory McqContent.fromJson(Map<String, dynamic> json) => McqContent(
    findingIndex: json['finding_index'] as int,
    questionNumber: json['question_number'] as int,
    stem: json['stem'] as String,
    options: Map<String, String>.from(json['options'] as Map),
    severity: json['severity'] as String,
    correctOption:
        json['correct_option'] as String? ??
        json['answer'] as String? ??
        json['correct'] as String?,
  );
}

class FlashcardContent extends EngramContent {
  final int findingIndex;
  final int cardNumber;
  final String front;
  final String back;
  final String? bridgeConcept;
  final String severity;
  final String? diagnosticNote;

  FlashcardContent({
    required this.findingIndex,
    required this.cardNumber,
    required this.front,
    required this.back,
    this.bridgeConcept,
    required this.severity,
    this.diagnosticNote,
  });

  factory FlashcardContent.fromJson(Map<String, dynamic> json) =>
      FlashcardContent(
        findingIndex: json['finding_index'] as int,
        cardNumber: json['card_number'] as int,
        front: json['front'] as String,
        back: json['back'] as String,
        bridgeConcept: json['bridge_concept'] as String?,
        severity: json['severity'] as String,
        diagnosticNote: json['diagnostic_note'] as String?,
      );
}

class ShortQuestionItem {
  final int findingIndex;
  final int questionNumber;
  final String level;
  final String stem;
  final String? hint;
  final bool contextAnchored;
  final String severity;

  /// Model answer for side-by-side comparison. Present only when engrams are
  /// fetched with answers (offline study pack); the daemon strips it from the
  /// default student view. Revealed by the client only AFTER the student submits.
  final String? expectedAnswer;

  ShortQuestionItem({
    required this.findingIndex,
    required this.questionNumber,
    required this.level,
    required this.stem,
    this.hint,
    required this.contextAnchored,
    required this.severity,
    this.expectedAnswer,
  });

  factory ShortQuestionItem.fromJson(Map<String, dynamic> json) =>
      ShortQuestionItem(
        findingIndex: json['finding_index'] as int,
        questionNumber: json['question_number'] as int,
        level: json['level'] as String,
        stem: json['stem'] as String,
        hint: json['hint'] as String?,
        contextAnchored: json['context_anchored'] as bool,
        severity: json['severity'] as String,
        expectedAnswer: json['expected_answer'] as String?,
      );
}

class ShortQuestionContent extends EngramContent {
  final List<ShortQuestionItem> questions;

  ShortQuestionContent({required this.questions});

  factory ShortQuestionContent.fromJson(Map<String, dynamic> json) =>
      ShortQuestionContent(
        questions:
            (json['questions'] as List)
                .map(
                  (q) => ShortQuestionItem.fromJson(q as Map<String, dynamic>),
                )
                .toList(),
      );
}

class LongQuestionPart {
  final String part;
  final String level;
  final String question;
  final int marks;
  final String? note;

  /// Per-part mark scheme — present only in the answers-included fetch; revealed
  /// after submit for self-comparison. Stripped from the default student view.
  final String? markScheme;

  LongQuestionPart({
    required this.part,
    required this.level,
    required this.question,
    required this.marks,
    this.note,
    this.markScheme,
  });

  factory LongQuestionPart.fromJson(Map<String, dynamic> json) =>
      LongQuestionPart(
        part: json['part'] as String,
        level: json['level'] as String,
        question: json['question'] as String,
        marks: json['marks'] as int,
        note: json['note'] as String?,
        markScheme: json['mark_scheme'] as String?,
      );
}

class LongQuestionContent extends EngramContent {
  final String questionStem;
  final List<LongQuestionPart> parts;
  final String severity;
  final int totalMarks;

  /// Overall model answer — present only in the answers-included fetch; revealed
  /// after submit. Stripped from the default student view.
  final String? answer;

  LongQuestionContent({
    required this.questionStem,
    required this.parts,
    required this.severity,
    required this.totalMarks,
    this.answer,
  });

  factory LongQuestionContent.fromJson(Map<String, dynamic> json) =>
      LongQuestionContent(
        questionStem: json['question_stem'] as String,
        parts:
            (json['parts'] as List)
                .map(
                  (p) => LongQuestionPart.fromJson(p as Map<String, dynamic>),
                )
                .toList(),
        severity: json['severity'] as String,
        totalMarks: json['total_marks'] as int,
        answer: json['answer'] as String?,
      );
}

class Engram {
  final String id;
  final String noteId;
  final EngramType type;
  final int targetCognitiveLevel;
  final List<String> tags;
  final EngramContent content;

  /// Daemon-owned due time (ISO-8601 UTC). Null when the daemon has not
  /// scheduled the engram yet — render no time in that case, never a fake one.
  final DateTime? scheduledAt;

  /// Daemon state vocabulary (e.g. `scheduled` / `due` / `completed`) — for
  /// client display only; the daemon is authoritative on re-scheduling.
  final String? state;

  Engram({
    required this.id,
    required this.noteId,
    required this.type,
    required this.targetCognitiveLevel,
    required this.tags,
    required this.content,
    this.scheduledAt,
    this.state,
  });

  factory Engram.fromJson(Map<String, dynamic> json) {
    final type = _parseEngramType(json['type'] as String);
    final rawContent = json['content'] as Map<String, dynamic>;

    late final EngramContent content;
    switch (type) {
      case EngramType.mcq:
        content = McqContent.fromJson(rawContent);
        break;
      case EngramType.flashcard:
        content = FlashcardContent.fromJson(rawContent);
        break;
      case EngramType.shortQuestion:
        content = ShortQuestionContent.fromJson(rawContent);
        break;
      case EngramType.longQuestion:
        content = LongQuestionContent.fromJson(rawContent);
        break;
      case EngramType.unknown:
        throw FormatException('Unknown engram type: ${json['type']}');
    }

    final scheduledRaw = json['scheduled_at'] ?? json['due_at'];
    return Engram(
      id: json['id'] as String,
      noteId: json['note_id'] as String,
      type: type,
      targetCognitiveLevel: json['target_cognitive_level'] as int,
      tags: List<String>.from(json['tags'] as List),
      content: content,
      scheduledAt: scheduledRaw is String
          ? DateTime.tryParse(scheduledRaw)?.toLocal()
          : null,
      state: json['state'] as String?,
    );
  }
}

class EngramListResponse {
  final String? bubbleId;
  final String? noteId;
  final int count;
  final List<Engram> engrams;

  EngramListResponse({
    this.bubbleId,
    this.noteId,
    required this.count,
    required this.engrams,
  });

  factory EngramListResponse.fromJson(Map<String, dynamic> json) =>
      EngramListResponse(
        bubbleId: json['bubble_id'] as String?,
        noteId: json['note_id'] as String?,
        count: json['count'] as int,
        engrams:
            (json['engrams'] as List)
                .map((e) => Engram.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}
