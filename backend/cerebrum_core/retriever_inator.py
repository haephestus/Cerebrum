import json
import logging
import os
from pathlib import Path

from langchain_chroma import Chroma
from langchain_ollama import OllamaEmbeddings, OllamaLLM

from agents.rose import RosePrompts
from cerebrum_core.model_inator import NoteStorage, TranslatedQuery
from cerebrum_core.utils.file_manager_inator import (
    CerebrumPaths,
    knowledgebase_index_inator,
)
from cerebrum_core.utils.note_util_inator import ArchiveInator, NoteToMarkdownInator

os.makedirs("./logs", exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler("logs/cerebrum_debug.log"),
        logging.StreamHandler(),  # optional: still prints to console
    ],
)
logger = logging.getLogger("cerebrum")
archives_path = CerebrumPaths()


class RetrieverInator:
    """
    Loads chroma dbs into memory
    retrieves relevant info for rag query
    grades retrieved data on relevance to query
    """

    def __init__(
        self, archives_root: str, embedding_model: str, chat_model: str
    ) -> None:
        self.archives_root = archives_root
        self.embedding_model = OllamaEmbeddings(model=embedding_model)
        self.chat_model = OllamaLLM(model=chat_model)
        self.constructed_query = {}
        self.all_results = []

    def translator_inator(self, user_query: str, translation_prompt: str):
        """
        translates user input into archives queries
        """

        # WARN: look into question(query) specific translation
        #       match each subquery to its relevant domain/subject
        #       step back / rewrite / sub-question / HyDE

        translation_prompt = translation_prompt
        if not translation_prompt:
            raise ValueError("Prompt 'rose_query_translator' not found in RosePrompts")

        available_stores = knowledgebase_index_inator(Path(self.archives_root))

        filled_prompt = translation_prompt.format(
            user_query=user_query, available_stores=available_stores
        )
        translated_query = self.chat_model.invoke(filled_prompt)
        logging.info(f"Raw translated query: {translated_query!r}")

        try:
            parsed_query = json.loads(translated_query)
        except json.JSONDecodeError:
            raise ValueError(f"LLM did not return valid JSON: {translated_query}")

        return TranslatedQuery(**parsed_query)

    def constructor_inator(self, translated_query: TranslatedQuery):
        """
        constructs archives queries from user input
        """
        # WARN: archives matching has not been implemented
        # the constructor returns subqueries and routes to relevant archives

        available_stores, _ = knowledgebase_index_inator(Path(self.archives_root))
        valid_paths = set()
        for domain in available_stores["domains"]:
            for subject in available_stores["subjects"]:
                valid_paths.add((domain, subject))

        self.constructed_query = {"routes": []}

        for subquery in translated_query.subqueries:
            domain = subquery.domain
            subject = subquery.subject

            if not domain or not subject:
                logging.warning("skipping subquery with missing domain/subject")
                continue

            if (domain, subject) not in valid_paths:
                logging.warning(
                    f"Invalid domain/subject pair: ({domain}, {subject}) skippng subquery"
                )
                continue
            path = Path(self.archives_root) / domain / subject
            self.constructed_query["routes"].append(
                {"subquery": subquery, "path": str(path)}
            )

        return self.constructed_query

    def retrieve_inator(self, k: int = 3):
        """
        queries archives using constructed_query
        and passes results to generate_inator for final response
        """

        # TODO: similarity_search vs as_retriever
        for route in self.constructed_query["routes"]:
            store = Chroma(
                collection_name=route["subquery"].subject,
                persist_directory=route["path"],
                embedding_function=self.embedding_model,
            )
            retrieve = store.as_retriever(
                search_type="mmr", search_kwargs={"k": k, "fetch_k": 15}
            )
            result = retrieve.invoke(route["subquery"].text)
            self.all_results.append(result)

        return self.all_results

    def generate_inator(self, user_query: str, top_k_chunks: int = 5):
        """
        Generates a response to user_query using retrieved documents,
        summarizing and deduplicating chunks, and producing tiered output.
        """
        # Flatten retrieved documents
        flat_docs = [doc for docs in self.all_results for doc in docs]

        # Deduplicate chunks based on page_content
        seen = set()
        dedup_docs = []
        for doc in flat_docs:
            if doc.page_content not in seen:
                seen.add(doc.page_content)
                dedup_docs.append(doc)

        # Optionally limit to top_k_chunks
        selected_docs = dedup_docs[:top_k_chunks]

        # Step 1: Summarize each chunk individually to reduce noise
        chunk_summaries = []
        for doc in selected_docs:
            summary_prompt = f"""
            Summarize the following text in 1–2 sentences, keeping only the key factual information:
            {doc.page_content}
            """
            summary = self.chat_model.invoke(summary_prompt)
            chunk_summaries.append(summary.strip())

        # Step 2: Combine summaries as context
        context_text = "\n\n".join(chunk_summaries)

        # Step 3: Tiered answer prompt
        base_prompt = RosePrompts.get_prompt("rose_answer")
        if not base_prompt:
            raise ValueError("Prompt 'rose_answer' not found in RosePrompts")

        # Modify prompt to include tiered instructions
        final_prompt = (
            base_prompt + "\n\nAdditional Instructions:\n"
            "- First give a 1–2 sentence summary answer.\n"
            "- Then, if relevant, provide a more detailed explanation under 'Further Explanation:'.\n"
            "- Condense overlapping info and avoid repeating facts.\n"
            "- Only use the provided context; do not hallucinate."
        )

        final_prompt = final_prompt.format(question=user_query, context=context_text)

        # Step 4: Invoke LLM
        response = self.chat_model.invoke(final_prompt)
        return response

    # compare note to archived_note
    def analyser_inator(self, note: NoteStorage, prompt: str, top_k_chunks: int = 5):
        # archive here to provide historical note versions
        archive_path = CerebrumPaths().get_note_archives(bubble_id=note.bubble_id)
        archived_data = ArchiveInator(note, str(archive_path)).archive_browser_inator(
            note.bubble_id
        )
        # flatten results from retrieve_inator(translate notecontent)
        flat_docs = [doc for docs in self.all_results for doc in docs]
        seen = set()
        dedup_docs = []
        for doc in flat_docs:
            if doc.page_content not in seen:
                seen.add(doc.page_content)
                dedup_docs.append(doc)
        context = dedup_docs[:top_k_chunks]

        flattened_note = NoteToMarkdownInator().flatten(note.content)
        # Summarize chunks
        context_summaries = []
        for doc in context:
            summary_prompt = f"""
            Summarize the following text in 1–2 sentences, keeping only the key factual information:
            {doc.page_content}
            """
            summary = self.chat_model.invoke(summary_prompt)
            context_summaries.append(summary.strip())

        context_text = "\n\n".join(context_summaries)

        analysis_prompt = prompt
        assert analysis_prompt is not None
        final_prompt = analysis_prompt.format(
            archived_data=archived_data,
            current_note=flattened_note,
            context=context_text,
        )
        response = self.chat_model.invoke(final_prompt)
        return response
