"""
A small in-memory stand-in for the supabase-py query builder.

The MagicMock chains in conftest.py check which calls were made. For the
money paths that is too weak: a compare-and-set that filters on the wrong
column passes just as green as a correct one. This fake applies filters and
updates to real rows, so tests assert on the resulting state.

It covers only the builder calls the backend uses: select / insert / update /
upsert / delete, eq / neq / in_ / is_ / lt / lte / gt / gte, order, limit,
maybe_single, execute. Embedded selects ("*, refunds(*)") are not resolved,
and constraints and triggers don't run here. The integration suite
(tests/integration) covers those against real Postgres.
"""
from __future__ import annotations

import copy
import uuid
from types import SimpleNamespace
from typing import Any, Callable, Optional


class FakeSupabase:
    def __init__(self, tables: Optional[dict[str, list[dict]]] = None,
                 defaults: Optional[dict[str, dict]] = None,
                 unique: Optional[dict[str, list[tuple[str, ...]]]] = None):
        self.tables: dict[str, list[dict]] = {k: [dict(r) for r in v] for k, v in (tables or {}).items()}
        self.defaults = defaults or {}
        # {table: [(col, ...), ...]}: an insert that repeats one raises the
        # same APIError (23505) PostgREST would.
        self.unique = unique or {}
        self.rpc_calls: list[tuple[str, dict]] = []
        self.rpc_handlers: dict[str, Callable[[dict], Any]] = {}

    def table(self, name: str) -> "_Query":
        self.tables.setdefault(name, [])
        return _Query(self, name)

    def rpc(self, name: str, params: dict):
        self.rpc_calls.append((name, params))
        handler = self.rpc_handlers.get(name)
        data = handler(params) if handler else None
        return SimpleNamespace(execute=lambda: SimpleNamespace(data=data))

    def rows(self, name: str) -> list[dict]:
        return self.tables.get(name, [])

    def one(self, name: str, **match) -> Optional[dict]:
        for row in self.rows(name):
            if all(row.get(k) == v for k, v in match.items()):
                return row
        return None


class _Query:
    def __init__(self, db: FakeSupabase, name: str):
        self.db, self.name = db, name
        self.op = "select"
        self.payload: Any = None
        self.filters: list[Callable[[dict], bool]] = []
        self._order: Optional[tuple[str, bool]] = None
        self._limit: Optional[int] = None
        self._single = False
        self._ignore_duplicates = False
        self._on_conflict: Optional[str] = None

    # ── operations ──
    def select(self, *_a, **_k):
        if self.op == "select":
            self.op = "select"
        return self

    def insert(self, payload):
        self.op, self.payload = "insert", payload
        return self

    def upsert(self, payload, on_conflict=None, ignore_duplicates=False, **_k):
        self.op, self.payload = "upsert", payload
        self._on_conflict, self._ignore_duplicates = on_conflict, ignore_duplicates
        return self

    def update(self, payload):
        self.op, self.payload = "update", payload
        return self

    def delete(self):
        self.op = "delete"
        return self

    # ── filters ──
    def eq(self, col, val):
        self.filters.append(lambda r: r.get(col) == val)
        return self

    def neq(self, col, val):
        self.filters.append(lambda r: r.get(col) != val)
        return self

    def in_(self, col, vals):
        vals = list(vals)
        self.filters.append(lambda r: r.get(col) in vals)
        return self

    def is_(self, col, val):
        want_null = str(val).lower() == "null"
        self.filters.append(lambda r: (r.get(col) is None) == want_null)
        return self

    def lt(self, col, val):
        self.filters.append(lambda r: r.get(col) is not None and r.get(col) < val)
        return self

    def lte(self, col, val):
        self.filters.append(lambda r: r.get(col) is not None and r.get(col) <= val)
        return self

    def gt(self, col, val):
        self.filters.append(lambda r: r.get(col) is not None and r.get(col) > val)
        return self

    def gte(self, col, val):
        self.filters.append(lambda r: r.get(col) is not None and r.get(col) >= val)
        return self

    def order(self, col, desc=False, **_k):
        self._order = (col, desc)
        return self

    def limit(self, n):
        self._limit = n
        return self

    def maybe_single(self):
        self._single = True
        return self

    # ── execute ──
    def _matching(self) -> list[dict]:
        return [r for r in self.db.tables[self.name] if all(f(r) for f in self.filters)]

    def execute(self):
        table = self.db.tables[self.name]
        if self.op == "select":
            rows = self._matching()
            if self._order:
                col, desc = self._order
                rows = sorted(rows, key=lambda r: (r.get(col) is None, r.get(col)), reverse=desc)
            if self._limit is not None:
                rows = rows[: self._limit]
            rows = copy.deepcopy(rows)
            if self._single:
                return SimpleNamespace(data=rows[0]) if rows else None
            return SimpleNamespace(data=rows)

        if self.op in ("insert", "upsert"):
            payload = self.payload if isinstance(self.payload, list) else [self.payload]
            out = []
            for item in payload:
                if self.op == "upsert" and self._on_conflict:
                    keys = self._on_conflict.split(",")
                    clash = next((r for r in table
                                  if all(r.get(k) == item.get(k) for k in keys)), None)
                    if clash is not None:
                        if not self._ignore_duplicates:
                            clash.update(item)
                            out.append(copy.deepcopy(clash))
                        continue
                row = {"id": str(uuid.uuid4()), **self.db.defaults.get(self.name, {}), **item}
                for cols in self.db.unique.get(self.name, []):
                    if any(all(r.get(c) == row.get(c) for c in cols) for r in table):
                        from postgrest.exceptions import APIError
                        raise APIError({"code": "23505", "message": f"duplicate key {cols}"})
                table.append(row)
                out.append(copy.deepcopy(row))
            return SimpleNamespace(data=out)

        if self.op == "update":
            out = []
            for row in self._matching():
                row.update(self.payload)
                out.append(copy.deepcopy(row))
            return SimpleNamespace(data=out)

        if self.op == "delete":
            gone = self._matching()
            self.db.tables[self.name] = [r for r in table if r not in gone]
            return SimpleNamespace(data=copy.deepcopy(gone))

        raise AssertionError(f"unsupported op {self.op}")
