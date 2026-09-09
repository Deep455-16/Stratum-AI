"""
pipeline/llm/base.py
--------------------
Abstract base class for LLM inference backends.

All concrete backends (LlamaBackend, SnapdragonBackend) must implement
this interface.  The RAG pipeline and server.py communicate exclusively
through this contract — they never import llama_cpp or onnxruntime directly.

Stream protocol (yielded tuples):
    ("ttft",  int)   — first-token latency in ms  (once, optional)
    ("token", str)   — one or more decoded tokens
    ("done",  None)  — generation complete
    ("error", str)   — unrecoverable error
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, Iterator, List, Optional, Tuple


# Type alias for stream events
StreamEvent = Tuple[str, Any]


class LLMBackend(ABC):
    """
    Common interface for all LLM inference backends.

    Implementations must be safe to call from a background thread
    (the existing _run_llm() pattern in server.py).
    """

    # ── Identity ─────────────────────────────────────────────────────────────

    @property
    @abstractmethod
    def backend_name(self) -> str:
        """Short identifier, e.g. 'llama' or 'snapdragon'."""

    @property
    @abstractmethod
    def model_name(self) -> str:
        """Model file or identifier being used."""

    @property
    @abstractmethod
    def runtime_name(self) -> str:
        """Runtime description, e.g. 'llama.cpp' or 'ONNX Runtime'."""

    @property
    @abstractmethod
    def device_name(self) -> str:
        """Execution device, e.g. 'CPU' or 'Snapdragon NPU'."""

    # ── Core API ──────────────────────────────────────────────────────────────

    @abstractmethod
    def stream(
        self,
        messages: List[Dict[str, str]],
        max_tokens: int = 512,
        temperature: float = 0.1,
        top_p: float = 0.8,
        repeat_penalty: float = 1.1,
    ) -> Iterator[StreamEvent]:
        """
        Yield stream events for a chat completion request.

        Parameters
        ----------
        messages:
            List of message dicts with "role" and "content" keys,
            exactly as produced by pipeline.prompt_builder.build_prompt().
        max_tokens, temperature, top_p, repeat_penalty:
            Generation hyper-parameters.

        Yields
        ------
        StreamEvent tuples following the stream protocol above.
        """

    @abstractmethod
    def health(self) -> Dict[str, Any]:
        """
        Return a JSON-serialisable health/status dict for GET /api/llm/health.

        Required keys:
            backend, model, runtime, device, status

        Optional keys (only include when actually measured/known):
            execution_provider, npu_available, qnn_available,
            load_time_ms, fallback_reason
        """

    # ── Optional lifecycle ────────────────────────────────────────────────────

    def load(self) -> None:  # noqa: B027
        """
        Called once at server startup to load/initialise the model.
        Implementations may raise RuntimeError if the backend cannot
        be initialised (missing model file, missing runtime, etc.).
        """

    def unload(self) -> None:  # noqa: B027
        """Optional teardown. Called on server shutdown."""
