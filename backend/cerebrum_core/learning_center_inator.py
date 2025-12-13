from agents.rose import RosePrompts
from cerebrum_core.model_inator import NoteStorage
from cerebrum_core.retriever_inator import RetrieverInator
from cerebrum_core.user_inator import (
    DEFAULT_CHAT_MODEL,
    DEFAULT_EMBED_MODEL,
    ConfigManager,
)
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
    PURPOSE
    -------
    Analyse a note while minimizing recomputation by using:
    - Vectorstore cache (primary: deterministic + semantic)
    - SQL backup cache (secondary: persistence + safety)

    semantic_version:
        Incremented only when semantic meaning changes
        (not cosmetic edits)
    """

    # ============================================================
    # PRE-CONDITIONS / REQUIRED SYSTEMS
    # ============================================================

    # - ConfigManager must expose:
    #   - embedding_model
    #   - chat_model
    #
    # - analyser must already be initialized with:
    #   - embedding_model
    #   - vectorstore (bubble or domain scoped)
    #
    # - The following caches must exist:
    #   - vector_cache  -> Chroma-based (semantic + deterministic)
    #   - backup_cache  -> SQLite-based (persistent backup)
    #
    # - Cache resolution order MUST be:
    #   1. Vector deterministic
    #   2. SQL backup
    #   3. Vector semantic
    #   4. Fresh computation

    # ============================================================
    # LOAD PROMPTS
    # ============================================================

    # - Load analysis_query:
    #     Used to translate the note into retrieval queries
    #
    # - Load analysis_prompt:
    #     Used to perform deep note analysis
    #
    # - If either prompt is missing:
    #     Abort early (this is a configuration error)

    # ============================================================
    # STEP 1: NOTE → QUERY TRANSLATION (EXPENSIVE, CACHEABLE)
    # ============================================================

    # GOAL:
    # - Convert the raw note into a structured query representation
    #
    # CACHE STRATEGY:
    # - Deterministic cache key:
    #     (note_id, semantic_version, "translation", prompt_hash)
    #
    # - First try vector deterministic cache
    # - Then try SQL backup cache
    #
    # IF CACHE MISS:
    # - Run analyser.translator_inator(...)
    # - Store result in:
    #     - Vector cache (with embedding)
    #     - SQL backup cache (raw JSON/text)

    # ============================================================
    # STEP 2: KNOWLEDGE RETRIEVAL (CONTEXTUAL, BUBBLE-SCOPED)
    # ============================================================

    # GOAL:
    # - Retrieve relevant documents from the knowledge base
    #
    # CACHE STRATEGY:
    # - Deterministic cache using translated query
    #
    # IF DETERMINISTIC MISS:
    # - Perform semantic search in vector cache
    #
    # IF SEMANTIC HIT:
    # - Adapt previous retrieval results to current note
    #
    # ELSE:
    # - Run full retrieval pipeline:
    #     - constructor_inator(...)
    #     - retrieve_inator(...)
    #
    # STORE RESULT:
    # - Vector cache (semantic + deterministic)
    # - SQL backup cache
    #
    # SIDE EFFECT:
    # - If cached retrieval exists, inject it back into analyser
    #   so downstream steps remain unchanged

    # ============================================================
    # STEP 3: DEEP NOTE ANALYSIS (MOST EXPENSIVE)
    # ============================================================

    # GOAL:
    # - Produce structured analysis:
    #     - Weak areas
    #     - Key concepts
    #     - Learning recommendations
    #
    # CACHE STRATEGY:
    # - Deterministic cache keyed by:
    #     (note_id, semantic_version, "analysis", prompt_hash)
    #
    # IF DETERMINISTIC MISS:
    # - Check SQL backup cache
    #
    # IF STILL MISS:
    # - Perform semantic fallback:
    #     - Embed note content
    #     - Search for similar analyses
    #
    # IF SEMANTIC HIT:
    # - Adapt previous analysis to current note
    #
    # ELSE:
    # - Run analyser.analyser_inator(...)
    #
    # STORE RESULT:
    # - Vector cache (embedding + metadata)
    # - SQL backup cache (raw output)

    # ============================================================
    # RETURN VALUE
    # ============================================================

    # - Return analysed_info
    # - Caller may:
    #     - Persist it
    #     - Display it
    #     - Feed it into quiz / engram generation
