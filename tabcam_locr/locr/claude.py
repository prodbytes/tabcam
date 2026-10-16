"""The Claude API client, with the key from Secrets Manager
(tabcam/anthropic-api-key, ANTHROPIC_KEY_SECRET): made on first use;
NotSetUp while the secret doesn't exist, so it works as soon as it does."""
import os


class NotSetUp(Exception):
    pass


_client = None


def client():
    global _client
    if _client is None:
        name = os.environ.get("ANTHROPIC_KEY_SECRET")
        if not name:
            raise NotSetUp("no Anthropic key configured")
        import anthropic
        import boto3
        sm = boto3.client("secretsmanager")
        try:
            key = sm.get_secret_value(SecretId=name)["SecretString"].strip()
        except sm.exceptions.ResourceNotFoundException as e:
            raise NotSetUp(f"no secret {name}") from e
        _client = anthropic.Anthropic(api_key=key, max_retries=1)
    return _client
