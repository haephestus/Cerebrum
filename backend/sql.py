from typing import List

import requests
from bs4 import BeautifulSoup

OLLAMA_LIBRARY_URL = "https://ollama.com/library"


def fetch_ollama_models() -> List[str]:
    """
    Fetch the list of model names from Ollama library page.
    """
    resp = requests.get(OLLAMA_LIBRARY_URL)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    # All links like /library/<model-name>
    models = set()
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if href.startswith("/library/"):
            model = href.split("/library/")[-1]
            models.add(model)

    return sorted(models)


def fetch_model_tags(model_name: str) -> List[str]:
    """
    Fetch tags for a given model from Ollama library page.
    Filters out unwanted tags like 'text', 'base', 'fp', or q4_0/q5_0.
    """
    url = f"{OLLAMA_LIBRARY_URL}/{model_name}/tags"
    resp = requests.get(url)
    if resp.status_code != 200:
        return []

    # Simple regex-like parsing, since the page returns plain text or HTML
    text = resp.text
    tags = set()
    for part in text.split():
        if part.startswith(f"{model_name}:") and not any(
            x in part for x in ["text", "base", "fp", "q4_0", "q5_0"]
        ):
            tags.add(part)

    return sorted(tags)


# Example usage
if __name__ == "__main__":
    models = fetch_ollama_models()
    print("Available models:", models)

    if models:
        tags = fetch_model_tags(models[0])
        print(f"Tags for {models[0]}:", tags)
