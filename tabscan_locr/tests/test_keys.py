from locr import keys

ID = "us-east-1:0f8b5b1e-1c2d-4e5f-8a9b-0c1d2e3f4a5b"


def test_a_scanned_page_is_parsed():
    page = keys.parse_page(f"{ID}/events/abc123/p1.img")
    assert page.identity == ID and page.event_id == "abc123" and page.page_id == "p1"
    assert page.result_key == f"{ID}/ocr/abc123/p1.json"


def test_everything_else_is_not_a_page():
    for key in [f"{ID}/events/abc123/event.json", f"{ID}/events/abc123/v1.mp4",
                f"{ID}/ocr/abc123/p1.json", f"{ID}/events/abc123/sub/p1.img",
                "nobody/events/abc123/p1.img", f"{ID}/events/ABC/p1.img",
                f"{ID}/events/abc123/p1", f"{ID}/events/../p1.img"]:
        assert keys.parse_page(key) is None, key
