import logging

from fastapi import APIRouter

# ------------------------- logging & config --------------------------- #
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# --------------------------- router & paths --------------------------- #
project_router = APIRouter(prefix="/home", tags=["Home API"])
