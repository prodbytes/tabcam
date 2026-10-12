"""Claude's reading of pages the engines find no tab on, with a fake
client. The riff is made up."""
import json
from types import SimpleNamespace as NS

import numpy as np

from locr import claude, pipeline, vision

TAB = "Verse\ne|-0---3-|\nB|-1---0-|\nG|-2---0-|\nD|-2---0-|\nA|-0---2-|\nE|-----3-|"


class FakeClaude:
    def __init__(self, answer, stop="end_turn"):
        self.answer, self.stop, self.calls = answer, stop, []
        self.messages = NS(create=self.create)

    def create(self, **kw):
        self.calls.append(kw)
        return NS(stop_reason=self.stop, content=[NS(type="text", text=json.dumps(self.answer))])


def blank_page():
    return np.full((1200, 900, 3), 255, np.uint8)


def test_claude_reads_the_page_image_into_a_tab():
    fake = FakeClaude({"found": True, "text": TAB})
    assert vision.read_tab(blank_page(), client=fake) == TAB + "\n"
    call = fake.calls[0]
    image, prompt = call["messages"][0]["content"]
    assert image["type"] == "image" and image["source"]["media_type"] == "image/jpeg"
    assert "plain-text tab" in prompt["text"]
    assert call["output_config"]["format"]["type"] == "json_schema"
    assert call["model"] == "claude-opus-5-5"


def test_no_tab_or_a_refusal_is_none():
    assert vision.read_tab(blank_page(), client=FakeClaude({"found": False, "text": ""})) == ""
    assert vision.read_tab(blank_page(), client=FakeClaude({"found": True, "text": TAB}, "refusal")) == ""


def test_the_pipeline_asks_claude_only_without_tab_lines():
    asked = []

    def fake_vision(img):
        asked.append(img.shape)
        return TAB + "\n"
    r = pipeline.transcribe_image(blank_page(), {"a": lambda s, l: ""}, vision=fake_vision)
    assert r.text == TAB + "\n" and r.staves == 1 and "claude" in r.timings
    assert len(asked) == 1
    assert pipeline.transcribe_image(blank_page(), {"a": lambda s, l: ""}).text == ""


def test_without_a_key_it_is_off(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_KEY_SECRET", raising=False)
    monkeypatch.setattr(claude, "_client", None)
    try:
        claude.client()
        raise AssertionError("expected NotSetUp")
    except claude.NotSetUp:
        pass
