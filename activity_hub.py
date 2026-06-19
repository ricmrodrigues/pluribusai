"""In-process activity notifications for efficient long-poll (single replica)."""
import threading
import time


class ActivityHub:
    """Wake long-poll waiters when the store writes messages or replies."""

    def __init__(self):
        self._cond = threading.Condition()
        self._generation = 0

    @property
    def generation(self):
        with self._cond:
            return self._generation

    def notify(self):
        with self._cond:
            self._generation += 1
            self._cond.notify_all()

    def wait_for_activity(self, fetch_fn, timeout=30):
        deadline = time.time() + max(0, float(timeout))
        seen_gen = self.generation
        while True:
            result = fetch_fn()
            if result.get("count", 0) > 0:
                return result
            remaining = deadline - time.time()
            if remaining <= 0:
                return result
            with self._cond:
                if self._generation != seen_gen:
                    seen_gen = self._generation
                    continue
                self._cond.wait(timeout=min(remaining, 5.0))
                seen_gen = self._generation