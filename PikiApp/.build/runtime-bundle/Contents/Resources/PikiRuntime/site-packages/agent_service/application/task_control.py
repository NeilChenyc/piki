from __future__ import annotations

import asyncio
import threading
from dataclasses import dataclass, field
from typing import Any


@dataclass
class TaskRunControl:
    cancel_event: threading.Event = field(default_factory=threading.Event)
    _loop: asyncio.AbstractEventLoop | None = None
    _task: asyncio.Task[Any] | None = None
    _lock: threading.Lock = field(default_factory=threading.Lock)

    @property
    def cancel_requested(self) -> bool:
        return self.cancel_event.is_set()

    def bind_async_task(self, loop: asyncio.AbstractEventLoop, task: asyncio.Task[Any]) -> None:
        with self._lock:
            self._loop = loop
            self._task = task
            cancel_requested = self.cancel_event.is_set()
        if cancel_requested:
            loop.call_soon_threadsafe(task.cancel)

    def request_cancel(self) -> None:
        self.cancel_event.set()
        with self._lock:
            loop = self._loop
            task = self._task
        if loop is not None and task is not None and not task.done():
            loop.call_soon_threadsafe(task.cancel)

