"""The vision model's reading (vision.py) with a fake Bedrock client, and
when the pipeline asks for it. The riffs are made up."""
import numpy as np
import pytest

from locr import pipeline, selftest, vision
from locr.pipeline import Result

ANSWER = """\
Riff
e|--------|
B|---8-8--|
G|-5-7/9--
D|--------|
A|--------|
E|--------|

e|--|
B|--|
G|--|
D|--|
A|--|
E|--|

2x
e|-----|-------|
B|-----|-------|
G|-7\\5-|-5-7(9)|
D|-----|-------|
A|-----|-------|
E|-----|-------|
"""


class FakeBedrock:
    def __init__(self, answer, stop="end_turn"):
        self.answer, self.stop, self.calls = answer, stop, []

    def converse(self, **kw):
        self.calls.append(kw)
        return {"stopReason": self.stop, "usage": {"inputTokens": 5200, "outputTokens": 12400},
                "output": {"message": {"content": [
                    {"reasoningContent": {"reasoningText": {"text": "the staircase..."}}},
                    {"text": self.answer}]}}}


def page():
    return np.full((2400, 1700, 3), 255, np.uint8)


def test_the_model_reads_the_page_image_into_a_tab(monkeypatch):
    monkeypatch.setattr(vision, "MODEL", "us.moonshotai.kimi-k3.1")
    fake = FakeBedrock(ANSWER)
    text, usage = vision.read_tab(page(), fake)
    assert text == (
        "Riff\n"
        "e|--------|\nB|---8-8--|\nG|-5-7/9--|\nD|--------|\nA|--------|\nE|--------|\n"
        "\n2x\n"
        "e|-----|-------|\nB|-----|-------|\nG|-7\\5-|-5-7(9)|\n"
        "D|-----|-------|\nA|-----|-------|\nE|-----|-------|\n")
    assert usage["outputTokens"] == 12400
    call = fake.calls[0]
    assert call["modelId"] == "us.moonshotai.kimi-k3.1"
    assert call["inferenceConfig"]["maxTokens"] == vision.MAX_TOKENS
    image, prompt = call["messages"][0]["content"]
    assert image["image"]["format"] == "jpeg" and "staircase" in prompt["text"]


def test_the_page_is_sent_at_most_1600_wide():
    import cv2
    data = vision._jpeg(np.full((3000, 2000, 3), 255, np.uint8))
    h, w = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_GRAYSCALE).shape
    assert (w, h) == (1600, 2400)


def test_a_bar_on_some_strings_is_one_across_the_staff():
    text = vision.clean("e|-----|\nB|--8--|\nG|-5-7-|-9-\nD|-----\nA|-----|\nE|-----|")
    assert text.splitlines() == ["e|-----|---|", "B|--8--|---|", "G|-5-7-|-9-|",
                                 "D|-----|---|", "A|-----|---|", "E|-----|---|"]


@pytest.mark.parametrize("answer, stop", [
    (vision.NO_TAB, "end_turn"),           # no tablature
    ("e|----|\nB|----|\nG|----|\nD|----|\nA|----|\nE|----|", "end_turn"),  # no frets
    (ANSWER, "max_tokens"),                # cut short
    ("I can't read this page.", "end_turn"),
])
def test_no_tab_or_an_unfinished_answer_is_none(monkeypatch, answer, stop):
    monkeypatch.setattr(vision, "MODEL", "us.moonshotai.kimi-k3.1")
    assert vision.read_tab(page(), FakeBedrock(answer, stop))[0] == ""


class Throttled(Exception):
    def __init__(self, code="ThrottlingException"):
        self.response = {"Error": {"Code": code}}


class Busy(FakeBedrock):
    def __init__(self, fails, code="ThrottlingException"):
        super().__init__(ANSWER)
        self.fails, self.code = fails, code

    def converse(self, **kw):
        if self.fails:
            self.fails -= 1
            raise Throttled(self.code)
        return super().converse(**kw)


def test_a_throttle_is_waited_out(monkeypatch):
    monkeypatch.setattr(vision, "MODEL", "us.moonshotai.kimi-k3.1")
    slept = []
    text, _ = vision.read_tab(page(), Busy(2), sleep=slept.append)
    assert text and len(slept) == 2 and 20 <= slept[0] <= 30 and 40 <= slept[1] <= 50


def test_a_lasting_throttle_or_another_error_gives_up(monkeypatch):
    monkeypatch.setattr(vision, "MODEL", "us.moonshotai.kimi-k3.1")
    slept = []
    with pytest.raises(Throttled):
        vision.read_tab(page(), Busy(9), sleep=slept.append)
    assert len(slept) == len(vision.WAITS)
    with pytest.raises(Throttled):
        vision.read_tab(page(), Busy(1, "AccessDeniedException"), sleep=slept.append)
    assert len(slept) == len(vision.WAITS)  # not waited for


def test_no_reading_starts_too_late_for_the_worker(monkeypatch):
    import time
    monkeypatch.setattr(vision, "MODEL", "us.moonshotai.kimi-k3.1")
    fake = FakeBedrock(ANSWER)
    with pytest.raises(vision.TooLate):
        vision.read_tab(page(), fake, deadline=time.monotonic() + 60)
    assert fake.calls == []
    slept = []
    # Time for one reading, not for a wait and another.
    with pytest.raises(vision.TooLate):
        vision.read_tab(page(), Busy(1), sleep=slept.append,
                        deadline=time.monotonic() + vision.CALL_SECONDS + 5)
    assert slept == []
    assert vision.read_tab(page(), fake, deadline=time.monotonic() + 900)[0]


def test_without_a_model_it_is_off(monkeypatch):
    monkeypatch.setattr(vision, "MODEL", "")
    with pytest.raises(vision.NotSetUp):
        vision.read_tab(page(), FakeBedrock(ANSWER))


# The pipeline: when it asks.

def drawn(doubtful):
    """The made-up riff on drawn lines, its numbers read by a fake, the
    first [doubtful] of them unsure."""
    from test_staves import expected_numbers
    said = iter(expected_numbers())
    n = [0]

    def read_crop(crop):
        n[0] += 1
        return next(said, "5"), n[0] > doubtful
    return read_crop


def test_a_sure_reading_on_drawn_staves_is_kept():
    asked = []
    r = pipeline.transcribe(selftest.drawn_page(), {"a": lambda s, l: ""},
                            read_crop=drawn(0), vision=lambda img: asked.append(img) or ANSWER)
    assert not asked and r.reader == "engines" and r.text


def test_an_unsure_reading_on_drawn_staves_is_the_models():
    asked = []
    seen = vision.clean("Made-up riff\n" + selftest.DRAWN_RIFF)
    r = pipeline.transcribe(selftest.drawn_page(), {"a": lambda s, l: ""},
                            read_crop=drawn(5), vision=lambda img: asked.append(img) or seen)
    assert len(asked) == pipeline.VISION_READS and asked[0].ndim == 3  # the page as it came
    assert r.reader == "vision" and r.text == seen and r.doubts == [] and r.staves == 2
    assert r.agreement > 0.9  # the fake engines read the riff right too
    assert "vision" in r.timings and "drawn" in r.timings


def test_the_engines_reading_stands_when_the_model_reads_too_little():
    for said in ("", "e|-3-|\nB|---|\nG|---|\nD|---|\nA|---|\nE|---|\n"):
        r = pipeline.transcribe(selftest.drawn_page(), {"a": lambda s, l: ""},
                                read_crop=drawn(5), vision=lambda img: said)
        assert r.reader == "engines" and r.doubts and "vision" in r.timings


def test_a_page_without_tab_is_the_models_only_when_asked():
    asked = []

    def fake(img):
        asked.append(img)
        return vision.clean(ANSWER)
    blank = pipeline.transcribe_image(page(), {"a": lambda s, l: ""}, vision=fake,
                                      vision_blank=False)
    assert blank.text == "" and not asked
    r = pipeline.transcribe_image(page(), {"a": lambda s, l: ""}, vision=fake)
    assert r.reader == "vision" and r.staves == 2 and len(asked) == pipeline.VISION_READS
    assert pipeline.transcribe_image(page(), {"a": lambda s, l: ""}).text == ""


def test_agreement_counts_frets_on_their_strings_in_order():
    engines = "e|-3---|\nB|---5-|\nG|-----|\nD|-----|\n"
    assert pipeline.agreement(engines, engines) == 1.0
    one_off = "e|-3---|\nB|---6-|\nG|-----|\nD|-----|\n"
    assert pipeline.agreement(one_off, engines) == 0.5
    down = "e|-----|\nB|-3---|\nG|---5-|\nD|-----|\n"  # a string down
    assert pipeline.agreement(down, engines) == 0.0


def test_of_two_readings_the_one_closer_to_the_engines_is_kept(monkeypatch):
    monkeypatch.setattr(pipeline, "VISION_READS", 2)
    right = vision.clean(selftest.DRAWN_RIFF)
    staves = [b.splitlines() for b in selftest.DRAWN_RIFF.strip().split("\n\n")]
    # The same notes a string down: a bad reading.
    down = vision.clean("\n\n".join(
        "\n".join([s[0][:2] + "-" * (len(s[0]) - 2)] + [s[i][:2] + s[i - 1][2:] for i in range(1, 6)])
        for s in staves))
    answers = iter([down, right])
    r = pipeline.transcribe(selftest.drawn_page(), {"a": lambda s, l: ""},
                            read_crop=drawn(5), vision=lambda img: next(answers))
    assert r.reader == "vision" and r.text == right
