from fastapi import APIRouter, HTTPException
from cerebrum_core.user_inator import ConfigReaderInator, ConfigWriterInator
from cerebrum_core.model_inator import UserConfig

configs_router = APIRouter(prefix="/user", tags=["user-config"])

config_reader = ConfigReaderInator()
config_writer = ConfigWriterInator()

# ------------------------------
# GET full user config
# ------------------------------
@configs_router.get("/config", response_model=UserConfig)
def get_user_config():
    try:
        return config_reader.load_config()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ------------------------------
# GET available chat models
# ------------------------------
@configs_router.get("/models/chat")
def list_chat_models():
    try:
        chat_models, _ = config_writer.fetch_models()
        return {"chat_models": chat_models}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ------------------------------
# POST update chat model only
# ------------------------------
@configs_router.post("/config/models/chat", response_model=UserConfig)
def update_chat_model(chat_model: str):
    try:
        return config_reader.update_model_settings(chat=chat_model)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ------------------------------
# GET available embedding models
# ------------------------------
@configs_router.get("/models/embedding")
def list_embedding_models():
    try:
        _, embedding_models = config_writer.fetch_models()
        return {"embedding_models": embedding_models}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ------------------------------
# POST update embedding model only
# ------------------------------
@configs_router.post("/config/models/embedding", response_model=UserConfig)
def update_embedding_model(embedding_model: str):
    try:
        return config_reader.update_model_settings(embedding=embedding_model)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
