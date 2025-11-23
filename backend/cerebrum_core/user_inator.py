#############################################################################
#                                                                           #
#                        USER CONFIG CLASSES                                #
#                                                                           #
#############################################################################

import re
import json
import requests
import subprocess

from cerebrum_core.file_manager_inator import CerebrumPaths
from cerebrum_core.model_inator import ModelConfig, OllamaConfig, User, UserConfig

#############################################################################
#                           CONSTANTS & PATTERNS
#############################################################################

CEREBRUM_PATHS = CerebrumPaths()
OLLAMA_LOCAL_URL = "http://127.0.0.1:11434"

CONFIG_DIR = CEREBRUM_PATHS.get_config_dir()
CONFIG_FILE = CONFIG_DIR / "user_config.json"

EMBEDDING_PATTERN = re.compile(r"(embed|embedding)", re.IGNORECASE)


#############################################################################
#                           CONFIG WRITER / FETCHER
#############################################################################

class ConfigWriterInator:
    """
    Handles:
    - fetching Ollama models
    - running ollama commands
    - creating default config
    """
    def __init__(self):
        pass

    def fetch_models(self):
        chat_models = []
        embedding_models = []

        response = requests.get(f"{OLLAMA_LOCAL_URL}/api/tags")
        response.raise_for_status()
        models_dict = response.json()

        for model in models_dict.get("models", []):
            name = model.get("name", "")

            if EMBEDDING_PATTERN.search(name):
                embedding_models.append(name)
            else:
                chat_models.append(name)

        return chat_models, embedding_models

    def run_ollama(self, chat_model: str):
        return subprocess.run(
            ["ollama", "run", chat_model],
            check=False
        )

    def generate_default_config(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)

        chat_models, embedding_models = self.fetch_models()

        config = UserConfig(
            models=ModelConfig(
                chat_model=chat_models[0] if chat_models else None,
                embedding_model=embedding_models[0] if embedding_models else None,
            )
        )

        ConfigReaderInator().save_config(config)
        return config


#############################################################################
#                           CONFIG READER / MANAGER
#############################################################################

class ConfigReaderInator:
    """
    Handles:
    - loading config
    - saving config
    - updating config
    """
    def __init__(self):
        pass

    def load_config(self) -> UserConfig:

        if not CONFIG_FILE.exists():
            print("[UserInator] Config file missing — generating defaults...")
            return ConfigWriterInator().generate_default_config()

        with open(CONFIG_FILE, "r") as file:
            data = json.load(file)

        return UserConfig(**data)

    def save_config(self, config: UserConfig):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)

        with open(CONFIG_FILE, "w") as file:
            json.dump(config.model_dump(), file, indent=4)

    def update_model_settings(self, chat=None, embedding=None):
        config = self.load_config()

        if chat is not None:
            config.models.chat_model = chat

        if embedding is not None:
            config.models.embedding_model = embedding

        self.save_config(config)
        return config

