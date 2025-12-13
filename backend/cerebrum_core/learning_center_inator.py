from agents.rose import RosePrompts
from cerebrum_core.model_inator import NoteStorage
from cerebrum_core.retriever_inator import RetrieverInator
from cerebrum_core.user_inator import (
    DEFAULT_CHAT_MODEL,
    DEFAULT_EMBED_MODEL,
    ConfigManager,
)
from cerebrum_core.utils.cache_inator import CacheInator, SQLiteBackupCache
from cerebrum_core.utils.note_util_inator import NoteToMarkdownInator

# TODO: progress tracking (based of learning goals)

# TODO: implement models
'''
# Use model matching to generate quizzes, or analysis or mockexams
def assesment_maker(raw: str, mode: str):
    """
    mode: quiz. analysis, mockexams
    """
    match mode:
        case "quiz":
            # parse string into a QuizModel
            return QuizModel.parse_from_string(raw)
        case "analysis":
            return AnalysisModel.parse_from_string(raw)
        case  "mock_exam":
            return MockExamModel.parse_from_string(raw)
        case _:
        # just return raw string
            return raw
'''

# TODO: generate engram(readings, quizzes, mock exams, flash cards)
#       run adapative spaced repetition
#       place quizzes in bubble specific folders
#       store historic engrams in bubble specific folders


# note analysis:
# TODO: implement note caching(intemediary md) to allow chunking
# TODO: add supporting caching dir in platform dirs


def note_analyser_inator(
    note: NoteStorage, semantic_version: float, analyser: RetrieverInator
):
    """
    note: the note object to analyze
    semantic_version: current semantic version of the note
    analyser: your RetrieverInator instance, should have .vectorstore attribute
    """

    # Load models
    models = ConfigManager().load_config().models

    # ----------------------------
    # Initialize caches
    # ----------------------------
    vector_cache = CacheInator(analyser.vectorstore)
    backup_cache = SQLiteBackupCache(in_memory=True)  # preloaded into memory

    # Load prompts
    analysis_query = RosePrompts.get_prompt("rose_note_to_query")
    analysis_prompt = RosePrompts.get_prompt("rose_note_analyser")
    if not analysis_query or not analysis_prompt:
        raise ValueError("Analysis query and prompt are required")

    # ----------------------------
    # 1️⃣ Translation Step
    # ----------------------------
    translated = vector_cache.get_deterministic(
        note_id=note.note_id,
        semantic_version=semantic_version,
        operation="translation",
        prompt=analysis_query,
    )

    if not translated:
        # Try backup cache
        translated = backup_cache.get(
            note_id=note.note_id,
            semantic_version=semantic_version,
            operation="translation",
            prompt=analysis_query,
        )

    if not translated:
        # Compute translation
        translated = analyser.translator_inator(
            user_query=analysis_query.format(information="", context=note),
            translation_prompt="hie",
        )

        # Store in caches
        vector_cache.set(
            note_id=note.note_id,
            semantic_version=semantic_version,
            operation="translation",
            prompt=analysis_query,
            embedding=analyser.embedding_model.encode(translated),
            response=translated,
        )
        backup_cache.set(
            note_id=note.note_id,
            semantic_version=semantic_version,
            operation="translation",
            prompt=analysis_query,
            response=translated,
        )

    # ----------------------------
    # 2️⃣ Retrieval Step
    # ----------------------------
    retrieved = vector_cache.get_deterministic(
        note_id=note.note_id,
        semantic_version=semantic_version,
        operation="retrieval",
        prompt=translated,
    )

    if not retrieved:
        # Semantic fallback via vectorstore
        embedding = analyser.embedding_model.encode(translated)
        similar_docs = vector_cache.get_semantic(embedding)
        if similar_docs:
            # LLM adapts previous analyses
            retrieved = analyser.adapt_from_similar(similar_docs, note)
        else:
            # Fresh retrieval
            analyser.constructor_inator(translated)
            retrieved = analyser.retrieve_inator()

        # Store result
        vector_cache.set(
            note_id=note.note_id,
            semantic_version=semantic_version,
            operation="retrieval",
            prompt=translated,
            embedding=embedding,
            response=retrieved,
        )
        backup_cache.set(
            note_id=note.note_id,
            semantic_version=semantic_version,
            operation="retrieval",
            prompt=translated,
            response=retrieved,
        )
    else:
        analyser.cached_retrieval_result = retrieved

    # ----------------------------
    # 3️⃣ Deep Analysis Step
    # ----------------------------
    analysed_info = vector_cache.get_deterministic(
        note_id=note.note_id,
        semantic_version=semantic_version,
        operation="analysis",
        prompt=analysis_prompt,
    )

    if not analysed_info:
        # Try backup cache
        analysed_info = backup_cache.get(
            note_id=note.note_id,
            semantic_version=semantic_version,
            operation="analysis",
            prompt=analysis_prompt,
        )

    if not analysed_info:
        # Semantic fallback
        embedding = analyser.embedding_model.encode(str(note.content))
        similar_analyses = vector_cache.get_semantic(embedding)
        if similar_analyses:
            analysed_info = analyser.adapt_from_similar(similar_analyses, note)
        else:
            analysed_info = analyser.analyser_inator(note, analysis_prompt)

        # Store result
        vector_cache.set(
            note_id=note.note_id,
            semantic_version=semantic_version,
            operation="analysis",
            prompt=analysis_prompt,
            embedding=embedding,
            response=analysed_info,
        )
        backup_cache.set(
            note_id=note.note_id,
            semantic_version=semantic_version,
            operation="analysis",
            prompt=analysis_prompt,
            response=analysed_info,
        )

    return analysed_info
