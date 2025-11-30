import logging

from fastapi import APIRouter

router_learn = APIRouter(prefix="/learn", tags=["Learning Center API"])

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# TODO: access cache to view user progress
@router_learn.post("/cache")
def _(param):
    pass


# TODO: analyse current version of note
# store analysis in bubble vectorstore


# TODO: generate quiz
# quiz generation lifespan or on demand? -> lifespan
