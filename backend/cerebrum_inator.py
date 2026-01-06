import subprocess
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api import routes_bubble, routes_knowledgebase, routes_learning_center, routes_user
from cerebrum_core.user_inator import ConfigManager
from cerebrum_core.utils.file_util_inator import CerebrumPaths
from cerebrum_core.utils.registry_inator import ChunkRegisterInator, FileRegisterInator

config_manager = ConfigManager()


@asynccontextmanager
async def lifespan(app: FastAPI):
    cerebrum_paths = CerebrumPaths()
    cerebrum_paths.init_cerebrum_dirs()
    # SQL DBs necessary for file processing
    app.state.file_registry = FileRegisterInator()
    app.state.chunk_registry = ChunkRegisterInator()

    # ROUTES for api level control
    app.include_router(routes_user.configs_router)
    app.include_router(routes_knowledgebase.router)
    app.include_router(routes_bubble.bubble_router)
    # app.include_router(routes_projects.project_router)
    app.include_router(routes_learning_center.router_learn)
    yield


def create_api_server():
    """
    Initializes server config and middleware.
    """

    # %%
    app = FastAPI(lifespan=lifespan)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/")
    def root():
        return {"message": "Cerebrum API is running"}

    # include routers
    # app.include_router(chat.router)
    return app


app = create_api_server()

if __name__ == "__main__":
    # Important so uvicorn doesn't run on import
    uvicorn.run(app, host="0.0.0.0", port=8000)
