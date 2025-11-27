import json
import re
import subprocess

import requests
from bs4 import BeautifulSoup

from cerebrum_core.file_manager_inator import CerebrumPaths
from cerebrum_core.model_inator import ModelConfig, UserConfig

# ─────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────
CEREBRUM_PATHS = CerebrumPaths()

OLLAMA_URL = "http://127.0.0.1:11434"
LIBRARY_URL = "https://ollama.com/library"

CONFIG_DIR = CEREBRUM_PATHS.get_config_dir()
CONFIG_FILE = CONFIG_DIR / "user_config.json"

EMBED_PATTERN = re.compile(r"(embed|embedding)", re.IGNORECASE)

DEFAULT_CHAT_MODEL = "llama3.1"
DEFAULT_EMBED_MODEL = "mxbai-embed-large"


# ─────────────────────────────────────────────────────────────
# Unified Config Manager
# ─────────────────────────────────────────────────────────────
class ConfigManager:
    """
    Handles:
    - loading/saving user config
    - generating default config
    - detecting Ollama
    - fetching installed & online models
    - pulling models programmatically
    """

    # ─────────────────────────────────────────────────────────
    #  BASIC FILE OPERATIONS
    # ─────────────────────────────────────────────────────────
    def load_config(self) -> UserConfig:
        """Load config or generate defaults if missing."""
        if not CONFIG_FILE.exists():
            return self.generate_default_config()

        with open(CONFIG_FILE, "r") as f:
            return UserConfig(**json.load(f))

    def save_config(self, config: UserConfig):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(config.model_dump(), f, indent=4)

    # ─────────────────────────────────────────────────────────
    #  DEFAULT CONFIG
    # ─────────────────────────────────────────────────────────
    def generate_default_config(self):
        chat, emb = self.get_installed_models()

        # fallback if no models installed yet
        chat = chat or [DEFAULT_CHAT_MODEL]
        emb = emb or [DEFAULT_EMBED_MODEL]

        config = UserConfig(
            models=ModelConfig(
                chat_model=chat[0],
                embedding_model=emb[0],
            )
        )

        self.save_config(config)
        return config

    # ─────────────────────────────────────────────────────────
    #  OLLAMA SYSTEM CHECKS
    # ─────────────────────────────────────────────────────────
    def is_ollama_installed(self):
        try:
            subprocess.run(["ollama", "--version"], stdout=subprocess.PIPE, check=True)
            return True
        except FileNotFoundError:
            return False

    def is_ollama_running(self):
        try:
            r = requests.get(f"{OLLAMA_URL}/api/version", timeout=1)
            return r.status_code == 200
        except Exception:
            return False

    def get_ollama_status(self):
        installed = self.is_ollama_installed()
        running = self.is_ollama_running()

        return {
            "installed": installed,
            "running": running,
            "message": (
                "Ollama is ready"
                if installed and running
                else "Ollama is not installed or not running"
            ),
            "install_url": "https://ollama.com/download",
        }

    # ─────────────────────────────────────────────────────────
    #  MODEL OPERATIONS
    # ─────────────────────────────────────────────────────────
    def get_installed_models(self):
        """Return installed models split into chat + embedding."""
        try:
            response = requests.get(f"{OLLAMA_URL}/api/tags")
            response.raise_for_status()
        except Exception:
            return [], []  # if service unavailable

        chat_models = []
        emb_models = []

        for m in response.json().get("models", []):
            name = m.get("name", "")
            (emb_models if EMBED_PATTERN.search(name) else chat_models).append(name)

        return chat_models, emb_models

    # TODO: EXPAND ON THIS, AND RETURN A MORE DETAILED LIST OF MODELS AND TAGS
    def get_available_online_models(self):
        """Fetch full model list available on Ollama.com"""
        response = requests.get(LIBRARY_URL)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "html.parser")

        models = set()
        for _ in soup.find_all("_", href=True):
            href = _["href"]
            if href.startswith("/library"):
                model = href.split("/library/")[-1]
                models.add(model)

        online_chat = []
        online_embed = []

        for m in models:
            (online_embed if EMBED_PATTERN.search(m) else online_chat).append(m)

        return {
            "online_chat_models": online_chat,
            "online_embedding_models": online_embed,
        }

    def download_model(self, model_name: str):
        return subprocess.run(["ollama", "pull", model_name], check=False)

    # ─────────────────────────────────────────────────────────
    #  UPDATE USER SETTINGS
    # ─────────────────────────────────────────────────────────
    def update_model_settings(self, chat=None, embedding=None):
        config = self.load_config()

        if chat is not None:
            config.models.chat_model = chat

        if embedding is not None:
            config.models.embedding_model = embedding

        self.save_config(config)
        return config
