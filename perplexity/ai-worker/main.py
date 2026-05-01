"""ai-worker: Perplexity 風 RAG の計算層 (mock).

エンドポイント (Phase 3 時点):
- GET  /health             : 疎通確認
- POST /corpus/embed       : テキストを擬似 encoder で 256-d float32 に変換 (ADR 0002)
- POST /retrieve           : BM25 + cosine の hybrid retrieval (ADR 0002)
- POST /extract            : chunk_ids → passages に整形 (ADR 0001)
- POST /synthesize/stream  : mock LLM の SSE 応答 (ADR 0001 / 0003 / 0004)
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from services import encoder
from services.embedding_store import EmbeddingStore, _build_default_engine
from services.extractor import Extractor, Passage
from services.retriever import DEFAULT_ALPHA, DEFAULT_TOP_K, Retriever
from services.synthesizer import synthesize_stream as run_synthesize

logger = logging.getLogger(__name__)


# ---- Lifespan: cold start で embedding 全件を numpy にロード (ADR 0002) ---


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    engine = _build_default_engine()
    store = EmbeddingStore(engine=engine)
    try:
        n = store.load()
        logger.info("ai-worker started: loaded %d chunks", n)
    except Exception as e:  # noqa: BLE001 - DB 未準備時でも起動は通したい
        logger.warning("EmbeddingStore.load() failed at startup: %s. Will retry on first /retrieve.", e)
    app.state.engine = engine
    app.state.embedding_store = store
    app.state.retriever = Retriever(engine=engine, store=store)
    app.state.extractor = Extractor(store=store)
    yield
    engine.dispose()


app = FastAPI(title="perplexity-ai-worker", version="0.1.0", lifespan=lifespan)


# ---- Models ---------------------------------------------------------------


class EmbedRequest(BaseModel):
    texts: list[str] = Field(..., min_length=1, max_length=1000)


class EmbedResponse(BaseModel):
    embeddings: list[list[float]]
    embedding_version: str


class RetrieveRequest(BaseModel):
    query_text: str = Field(..., min_length=1, max_length=2000)
    top_k: int = Field(DEFAULT_TOP_K, ge=1, le=100)
    alpha: float = Field(DEFAULT_ALPHA, ge=0.0, le=1.0)


class RetrieveHit(BaseModel):
    chunk_id: int
    source_id: int
    bm25_score: float
    cosine_score: float
    fused_score: float


class RetrieveResponse(BaseModel):
    hits: list[RetrieveHit]
    embedding_version: str
    loaded_chunks: int


class ExtractRequest(BaseModel):
    chunk_ids: list[int] = Field(..., min_length=1, max_length=100)


class ExtractPassage(BaseModel):
    chunk_id: int
    source_id: int
    snippet: str
    ord: int


class ExtractResponse(BaseModel):
    passages: list[ExtractPassage]


class SynthesizePassage(BaseModel):
    chunk_id: int
    source_id: int
    snippet: str
    ord: int


class SynthesizeRequest(BaseModel):
    query_text: str = Field(..., min_length=1, max_length=2000)
    passages: list[SynthesizePassage] = Field(..., min_length=0, max_length=20)
    allowed_source_ids: list[int] = Field(..., min_length=0, max_length=100)


# ---- Endpoints ------------------------------------------------------------


@app.get("/health")
def health() -> dict:
    store: EmbeddingStore | None = getattr(app.state, "embedding_store", None)
    return {
        "status": "ok",
        "service": "perplexity-ai-worker",
        "embedding_store_loaded": bool(store and store.loaded),
        "loaded_chunks": store.size if store else 0,
    }


@app.post("/corpus/embed", response_model=EmbedResponse)
def corpus_embed(req: EmbedRequest) -> EmbedResponse:
    """ADR 0002: deterministic 擬似 encoder で 256-d float32 ベクトルを生成.

    Rails 側 (CorpusIngestor) が呼び、戻り値を `chunks.embedding` BLOB に詰める.
    ai-worker から DB への書き戻しはしない (ADR 0001).
    """
    matrix = encoder.encode_many(req.texts)
    embeddings = [vec.tolist() for vec in matrix]
    return EmbedResponse(embeddings=embeddings, embedding_version=encoder.version())


@app.post("/retrieve", response_model=RetrieveResponse)
def retrieve(req: RetrieveRequest) -> RetrieveResponse:
    """ADR 0002: hybrid retrieval. BM25 (FULLTEXT) + cosine (numpy) の重み付き和."""
    retriever: Retriever | None = getattr(app.state, "retriever", None)
    store: EmbeddingStore | None = getattr(app.state, "embedding_store", None)
    if retriever is None or store is None:
        raise HTTPException(status_code=503, detail="retriever not initialized")

    if not store.loaded:
        # 初回 retrieve で再試行 (lifespan で失敗しても運転再開できるように)
        try:
            store.load()
        except Exception as e:  # noqa: BLE001
            raise HTTPException(status_code=503, detail=f"embedding_store load failed: {e}") from e

    hits = retriever.retrieve(req.query_text, top_k=req.top_k, alpha=req.alpha)
    return RetrieveResponse(
        hits=[
            RetrieveHit(
                chunk_id=h.chunk_id,
                source_id=h.source_id,
                bm25_score=h.bm25_score,
                cosine_score=h.cosine_score,
                fused_score=h.fused_score,
            )
            for h in hits
        ],
        embedding_version=encoder.version(),
        loaded_chunks=store.size,
    )


@app.post("/extract", response_model=ExtractResponse)
def extract(req: ExtractRequest) -> ExtractResponse:
    """ADR 0001: chunk_ids → passages. Phase 3 では snippet = chunk.body そのまま."""
    extractor: Extractor | None = getattr(app.state, "extractor", None)
    if extractor is None:
        raise HTTPException(status_code=503, detail="extractor not initialized")

    passages = extractor.extract(req.chunk_ids)
    return ExtractResponse(
        passages=[
            ExtractPassage(chunk_id=p.chunk_id, source_id=p.source_id, snippet=p.snippet, ord=p.ord)
            for p in passages
        ]
    )


@app.post("/synthesize/stream")
async def synthesize_stream_endpoint(req: SynthesizeRequest):
    """ADR 0001 / 0003 / 0004: mock LLM が answer を SSE で逐次生成する.

    Rails 側 (RagOrchestrator / Phase 3 同期 or SSE proxy / Phase 4) が consume.
    """
    passages = [
        Passage(chunk_id=p.chunk_id, source_id=p.source_id, snippet=p.snippet, ord=p.ord)
        for p in req.passages
    ]
    return StreamingResponse(
        run_synthesize(req.query_text, passages, req.allowed_source_ids),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",  # ADR 0003: nginx バッファ抑制
        },
    )
