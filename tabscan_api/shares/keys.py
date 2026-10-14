"""Profile keys: what keeps each profile's captures encrypted at rest.

Every profile has an RSA key pair (RSA_3072), made by KMS the first time
the profile needs it (GenerateDataKeyPairWithoutPlaintext): the public key
is kept as it is, the private key only wrapped by the one KMS key
(PROFILE_KEY_ID), with the profile's ID as its encryption context. Both are
in the profile keys table, written once (a conditional put), never
overwritten.

The app encrypts each capture with a random AES-256 key of its own (its
content key) and keeps it in the capture's event.json wrapped with the
owner profile's public key (RSA-OAEP with SHA-256, the capture's ID as the
label, so a wrapped key only opens the capture it came with). Whoever may
read a capture gets its content key from the API, which unwraps it here: the
private key never leaves the API.
"""

import base64
import os
import time

KEY_SPEC = "RSA_3072"
ALGORITHM = "RSA-OAEP-256"

# Unwrapped private keys, by profile, for a few minutes (KMS calls are
# billed, and each takes a moment).
_PRIVATE_TTL = 300
_PRIVATE_MAX = 64
_private = {}


class KeyError_(Exception):
    """A capture's key can't be unwrapped (no key, or not this profile's)."""


def label(capture_id):
    """The OAEP label that ties a wrapped key to its capture."""
    return f"tabscan:{capture_id}".encode()


def _context(profile_id):
    return {"profile": profile_id}


def keys_of(table, kms, profile_id):
    """The profile's keys (its item: publicKey, privateKeyWrapped,
    keySpec), made the first time. Two first requests racing: the first
    write wins, and both use it."""
    item = table.get_item(Key={"profileId": profile_id}, ConsistentRead=True).get("Item")
    if item is not None:
        return item
    made = kms.generate_data_key_pair_without_plaintext(
        KeyId=os.environ["PROFILE_KEY_ID"],
        KeyPairSpec=KEY_SPEC,
        EncryptionContext=_context(profile_id),
    )
    item = {
        "profileId": profile_id,
        "publicKey": base64.b64encode(made["PublicKey"]).decode(),
        "privateKeyWrapped": base64.b64encode(made["PrivateKeyCiphertextBlob"]).decode(),
        "keySpec": KEY_SPEC,
        "createdAt": int(time.time()),
    }
    try:
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(profileId)")
    except Exception as e:
        if type(e).__name__ == "ConditionalCheckFailedException" or "ConditionalCheckFailed" in str(e):
            return table.get_item(Key={"profileId": profile_id}, ConsistentRead=True)["Item"]
        raise
    return item


def _private_key(table, kms, profile_id):
    from cryptography.hazmat.primitives.serialization import load_der_private_key

    cached = _private.get(profile_id)
    if cached and cached[0] > time.time():
        return cached[1]
    item = table.get_item(Key={"profileId": profile_id}, ConsistentRead=True).get("Item")
    if item is None:
        raise KeyError_("the profile has no keys")
    der = kms.decrypt(
        CiphertextBlob=base64.b64decode(item["privateKeyWrapped"]),
        KeyId=os.environ["PROFILE_KEY_ID"],
        EncryptionContext=_context(profile_id),
    )["Plaintext"]
    key = load_der_private_key(der, password=None)
    # A few at a time: a long-lived function never holds many.
    if len(_private) >= _PRIVATE_MAX:
        _private.clear()
    _private[profile_id] = (time.time() + _PRIVATE_TTL, key)
    return key


def unwrap(table, kms, profile_id, capture_id, wrapped_b64):
    """A capture's content key (32 bytes), from its wrapped key."""
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import padding

    try:
        wrapped = base64.b64decode(wrapped_b64, validate=True)
    except Exception as e:
        raise KeyError_("not a wrapped key") from e
    key = _private_key(table, kms, profile_id)
    try:
        content = key.decrypt(
            wrapped,
            padding.OAEP(
                mgf=padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=label(capture_id),
            ),
        )
    except ValueError as e:
        raise KeyError_("not this capture's key") from e
    if len(content) != 32:
        raise KeyError_("not a content key")
    return content


def forget(profile_id):
    """Drops a profile's cached private key (its keys were deleted)."""
    _private.pop(profile_id, None)
