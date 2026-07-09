from __future__ import annotations


class TaskRepository:
    def __init__(self, store):
        self.store = store

    def create(self, **kwargs):
        return self.store.create_task(**kwargs)

    def get(self, task_id: str):
        return self.store.get_task(task_id)

    def update(self, task_id: str, **kwargs):
        return self.store.update_task(task_id, **kwargs)


class EventRepository:
    def __init__(self, store):
        self.store = store

    def add(self, task_id: str, event_type, payload: dict):
        return self.store.add_event(task_id, event_type, payload)

    def list_for_task(self, task_id: str):
        return self.store.list_events(task_id)


class JournalRepository:
    def __init__(self, store):
        self.store = store

    def create(self, **kwargs):
        return self.store.create_journal_entry(**kwargs)

    def get(self, journal_id: str):
        return self.store.get_journal_entry(journal_id)

    def list_recent(self, limit: int = 20):
        return self.store.list_journal_entries(limit=limit)
