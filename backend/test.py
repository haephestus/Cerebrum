import pathlib
import pymupdf
from pymupdf.mupdf import pdfmetadatadata
import tiktoken
import pymupdf4llm
from langchain_chroma import Chroma
from langchain_ollama import OllamaEmbeddings
from cerebrum_core.ingest_inator import IngestInator
from cerebrum_core.retriever_inator import RetrieverInator
doc = pathlib.Path("../data/storage/markdown/chemistry/biochemistry/lehninger-principles-of-biochemistry.md")
pdf_path = pathlib.Path("../data/knowledgebase/biology/physiology/Johnny Hall - Guyton Hall TextBook of medical Physiology 14th edition John E Hall (2021) - libgen.li.pdf")


# %% 
from pathlib import Path
from cerebrum_core.file_manager_inator import knowledgebase_index_inator

test, testfile = knowledgebase_index_inator(Path("../data/storage/archives"))
for test in test:
    print(test["domain"])
    print(test["subject"])
    print(testfile)


with pymupdf.open(pdf_path) as file:
    metadata = file.metadata
to_md = IngestInator(
    filepath=pdf_path
)
clean_md = to_md.sanitize_inator(
    filename=pdf_path.name,
    metadata=file.metadata,
    chat_model="granite4:micro"
)
print(file.metadata)
print(clean_md)
chunks = to_md.chunk_inator(markdown_filepath=doc)
for chunk in chunks:
    print(chunk.metadata)

#%%

# %%
query = "Describe DNA"
retrieve = RetrieverInator(
    archives_root = "../data/storage/archives",
    embedding_model="qwen3-embedding:4b-q4_K_M",
    chat_model = "granite4:micro"
)

translated_query = retrieve.translator_inator(user_query=query)
for sq in translated_query.subqueries:
    print(sq.subject)

constructor = retrieve.constructor_inator(
    translated_query=translated_query,
)
print(constructor)
for route in constructor["routes"]:
    print(route["subquery"].subject)

retrieve.retrieve_inator()
response = retrieve.generate_inator(user_query=query)
print(response)

#%%

#%%
from langchain_chroma import Chroma
from langchain_ollama import OllamaEmbeddings

query = "Describe DNA."
test_db = Chroma (
    embedding_function=OllamaEmbeddings(model="qwen3-embedding:4b-q4_K_M"),
    collection_name="david-s-latchman-gene-control",
    persist_directory="../data/storage/archives/biology/genetics"
)
retrieve = test_db.as_retriever(search_kwargs={"k": 3})
result = retrieve.invoke(query)

for doc in result:
    print(doc.page_content)
# %%
