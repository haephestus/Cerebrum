import hashlib

from langchain.schema import Document


def build_doc_fingerprint(domain: str, doc: Document) -> tuple[str, str]:
    canonical = f"{domain}\n{doc.page_content.strip()}"
    fingerprint = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return canonical, fingerprint


def fingerprint_documents(domain: str, docs: list[Document]) -> list[Document]:
    for i, doc in enumerate(docs):
        canonical, fp = build_doc_fingerprint(domain, doc)

        doc.metadata = doc.metadata or {}
        doc.metadata["semantic_fingerprint"] = fp

        print(f"\n--- Document {i} ---")
        print("Canonical form:")
        print("---------------")
        print(canonical)
        print("---------------")
        print(f"Fingerprint: {fp}")

    return docs


if __name__ == "__main__":
    domain = "neuroscience"

    docs = [
        Document(
            page_content="The hippocampus is involved in memory consolidation.",
            metadata={"source": "textbook_A"},
        ),
        Document(
            page_content="The hippocampus is involved in memory consolidation.",
            metadata={"source": "paper_B"},
        ),
        Document(
            page_content="The amygdala plays a key role in emotional processing.",
            metadata={"source": "textbook_A"},
        ),
    ]

    fingerprint_documents(domain, docs)
