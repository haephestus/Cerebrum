from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from cerebrum_core.user_inator import ConfigManager
from cerebrum_core.utils.file_manager_inator import CerebrumPaths, FileRegisterInator
from local_server import routes_process_files  # routes_projects,
from local_server import routes_bubble, routes_user

config_manager = ConfigManager()


@asynccontextmanager
async def lifespan(app: FastAPI):
    config_manager.generate_default_config()
    cerebrum_paths = CerebrumPaths()
    cerebrum_paths.init_cerebrum_dirs()

    registry = FileRegisterInator()
    app.state.registry = registry

    app.include_router(routes_process_files.router)
    # app.include_router(routes_projects.project_router)
    app.include_router(routes_bubble.bubble_router)
    app.include_router(routes_user.configs_router)
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
