from agents.rose import RosePrompts
from cerebrum_core.retriever_inator import RetrieverInator
from cerebrum_core.user_inator import (
    DEFAULT_CHAT_MODEL,
    DEFAULT_EMBED_MODEL,
    ConfigManager,
)

# TODO: progress tracking (based of learning goals)


class AssesorInator(RetrieverInator):
    """
    Extends RetrieverInator, to allow for assement specific generation
    """

    def generate_inator(
        self,
        user_query: str,
        top_k_chunks: int = 5,
        prompt_name: str = "rose_note_analyser",
        comparison_context: str | None = None,
    ) -> str:
        """
        Extends base generate_inator to allow dynamic prompts for
        note analysis, quiz and mock exam generation
        """

        # Flatten and deduplicate retrieved docs
        flat_docs = [doc for docs in self.all_results for doc in docs]
        seen = set()
        dedup_docs = []
        for doc in flat_docs:
            if doc.page_content not in seen:
                seen.add(doc.page_content)
                dedup_docs.append(doc)

        selected_docs = dedup_docs[:top_k_chunks]

        # Summarize chunks
        chunk_summaries = []
        for doc in selected_docs:
            summary_prompt = f"""
            Summarize the following text in 1–2 sentences, keeping only the key factual information:
            {doc.page_content}
            """
            summary = self.llm_model.invoke(summary_prompt)
            chunk_summaries.append(summary.strip())

        context_text = "\n\n".join(chunk_summaries)

        # Include user notes for comparison if provided
        if comparison_context:
            context_text = (
                f"User Notes:\n{comparison_context}\n\nRetrieved Info:\n{context_text}"
            )

        # Get prompt dynamically
        base_prompt = RosePrompts.get_prompt(prompt_name)
        if not base_prompt:
            raise ValueError(f"Prompt '{prompt_name}' not found in RosePrompts")

        # Add tiered instructions
        final_prompt = (
            base_prompt
            + "\n\nAdditional Instructions:\n- Use only the provided context.\n- Compare retrieved info with user notes if provided."
        )
        final_prompt = final_prompt.format(question=user_query, context=context_text)

        # Invoke LLM
        response = self.llm_model.invoke(final_prompt)
        return response


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


def data_retriever_inator(bubble_id: str, filename: str):
    """
    Retrieve note data from archives
    """
    pass


# TODO: generate engram(readings, quizzes, mock exams, flash cards)
#       run adapative spaced repetition
#       place quizzes in bubble specific folders
#       store historic engrams in bubble specific folders


# note analysis:
# TODO: implement note caching(intemediary md) to allow chunking
# TODO: add supporting caching dir in platform dirs
def note_analyser_inator(note: str):
    models = ConfigManager().load_config().models
    analyser = AssesorInator(
        vectorstores_root="placeholder",
        embedding_model=models.embedding_model or DEFAULT_EMBED_MODEL,
        llm_model=models.chat_model or DEFAULT_CHAT_MODEL,
    )

    analysis_query = RosePrompts.get_prompt("rose_note_analyser")
    if not analysis_query:
        raise ValueError("Analysis query is needed")

    # translate analysis query to llm compatible format
    translated_analysis = analyser.translator_inator(
        user_query=analysis_query.format(information="", context=note)
    )

    # construct vector store query
    analyser.constructor_inator(translated_analysis)
    analyser.retrieve_inator()

    # produce targeted reading suggestions
    # generate response: highlight weak areas
    # TODO: pass analysis_query to generate_inator?
    # analysed_info = analyser.anslyser_inator(note)
    analysed_info = analyser.generate_inator(note)
    return analysed_info


def historical_note_analyser_inator():
    # load note into memory from ./embeds/vectorstore
    # fetch the note, analyse the note
    # add note to registry(sqlbd) of analysed notes
    pass
