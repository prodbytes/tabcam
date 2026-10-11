"""Auto-correct's logic with a fake Claude. The riff is made up."""
import json
from types import SimpleNamespace as NS

import pytest

from locr import autocorrect, handler
from locr.autocorrect import Corrector, check, describe, parse

from test_handler import ID, FakeAccounts, FakeRbacr, http, svc  # noqa: F401

RIFF = "\n".join([
    "Am        G",
    "e|-----0-----|",
    "B|---1---1---|",
    "G|-2-------8-|",
    "D|-----------|",
    "A|-0---------|",
    "E|-----------|",
    "",
    "la la la",
])


def test_parse_numbers_the_notes_of_string_lines_only():
    r = parse(RIFF)
    assert r.tab_lines == {1, 2, 3, 4, 5, 6}
    assert [(n.id, n.line, n.column, n.text) for n in r.notes.values()] == [
        ("n1", 1, 7, "0"), ("n2", 2, 5, "1"), ("n3", 2, 9, "1"),
        ("n4", 3, 3, "2"), ("n5", 3, 11, "8"), ("n6", 5, 3, "0")]
    text = describe(r)
    assert 'line 0 (text): Am        G' in text
    assert 'n5@11 "8"' in text and "line 8 (text): la la la" in text


def test_check_keeps_corrections_that_fit_the_reading():
    r = parse(RIFF)
    out = check(r, [
        {"kind": "replace", "note": "n5", "text": "3", "reason": "8 is a misread 3"},
        {"kind": "replace", "note": "n2", "text": "1", "reason": "unchanged"},
        {"kind": "replace", "note": "n99", "text": "3", "reason": "no such note"},
        {"kind": "replace", "note": "n4", "text": "hello", "reason": "not a note"},
        {"kind": "delete", "note": "n3", "text": "", "reason": "stray mark"},
        {"kind": "insert", "line": 4, "column": 7, "text": "12", "reason": "dropped"},
        {"kind": "insert", "line": 0, "column": 3, "text": "2", "reason": "chord line"},
        {"kind": "insert", "line": 3, "column": 2, "text": "5", "reason": "overlaps n4"},
        {"kind": "insert", "line": 4, "column": 12, "text": "5", "reason": "on the bar"},
    ])
    assert [(c["line"], c["column"], c["old"], c["new"]) for c in out] == [
        (2, 9, "1", ""), (3, 11, "8", "3"), (4, 7, "", "12")]
    assert [c["id"] for c in out] == ["c2", "c1", "c3"]


class FakeStream:
    def __init__(self, message):
        self.message = message

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def get_final_message(self):
        return self.message


class FakeClaude:
    def __init__(self, *messages):
        self.messages_left = list(messages)
        self.calls = []
        self.beta = NS(messages=NS(stream=self.stream))

    def stream(self, **kw):
        self.calls.append(kw)
        return FakeStream(self.messages_left.pop(0))


def message(stop, *content):
    return NS(stop_reason=stop, content=list(content),
              usage=NS(input_tokens=100, output_tokens=10,
                       server_tool_use=NS(web_search_requests=1)))


def submit(**answer):
    base = {"found": True, "title": "Made-up Riff", "artist": "Nobody",
            "sources": ["https://tabs.example/riff", "javascript:alert(1)"],
            "summary": "One note misread.", "corrections": []}
    return NS(type="tool_use", name="submit_corrections", input={**base, **answer})


def test_correct_asks_claude_with_web_tools_and_checks_its_answer():
    claude = FakeClaude(
        message("pause_turn", NS(type="text", text="searching")),
        message("tool_use", submit(corrections=[
            {"kind": "replace", "note": "n5", "line": 3, "column": 11, "text": "3",
             "reason": "8 is a misread 3"}])))
    r = Corrector(client=claude).correct(RIFF, "Made-up Riff")
    assert r["found"] and r["title"] == "Made-up Riff"
    assert r["sources"] == ["https://tabs.example/riff"]
    assert [(c["old"], c["new"]) for c in r["corrections"]] == [("8", "3")]
    assert r["usage"]["turns"] == 2 and r["usage"]["searches"] == 2
    call = claude.calls[0]
    assert call["model"] == "claude-opus-5-5"
    assert {t["name"] for t in call["tools"]} == {"web_search", "web_fetch", "submit_corrections"}
    assert call["fallbacks"] == "default"
    assert "Made-up Riff" in call["messages"][0]["content"]
    # The paused turn is sent back to continue.
    assert claude.calls[1]["messages"][1]["role"] == "assistant"


def test_correct_nudges_once_then_gives_up():
    claude = FakeClaude(message("end_turn", NS(type="text", text="hm")),
                        message("end_turn", NS(type="text", text="still hm")))
    r = Corrector(client=claude).correct(RIFF)
    assert not r["found"] and r["corrections"] == []
    assert claude.calls[1]["messages"][-1]["content"].startswith("Answer with")


def test_correct_without_tab_lines_does_not_ask():
    claude = FakeClaude()
    assert Corrector(client=claude).correct("just lyrics\nla la")["notes"] == 0
    assert claude.calls == []


def test_autocorrect_route(svc):  # noqa: F811
    claude = FakeClaude(message("tool_use", submit()))
    svc._made["corrector"] = Corrector(client=claude)
    body = {"eventId": "ev1", "song": "Made-up Riff", "text": RIFF}
    assert handler.api(http("/autocorrect", body=body))["statusCode"] == 402
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    reply = handler.api(http("/autocorrect", body=body))
    assert reply["statusCode"] == 200
    assert json.loads(reply["body"])["summary"] == "One note misread."
    assert "usage" not in json.loads(reply["body"])
    bad = handler.api(http("/autocorrect", body={"eventId": "ev1", "text": ""}))
    assert bad["statusCode"] == 400


def test_autocorrect_not_set_up(svc, monkeypatch):  # noqa: F811
    monkeypatch.delenv("ANTHROPIC_KEY_SECRET", raising=False)
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    reply = handler.api(http("/autocorrect", body={"eventId": "ev1", "text": RIFF}))
    assert reply["statusCode"] == 503


def test_autocorrect_failure_is_a_502(svc):  # noqa: F811
    class Broken:
        def correct(self, text, song):
            raise RuntimeError("overloaded")
    svc._made["corrector"] = Broken()
    svc._made["rbacr"] = FakeRbacr({"ana@example.com"})
    reply = handler.api(http("/autocorrect", body={"eventId": "ev1", "text": RIFF}))
    assert reply["statusCode"] == 502


@pytest.fixture(autouse=True)
def _accounts(svc):  # noqa: F811
    svc._made["accounts"] = FakeAccounts()
