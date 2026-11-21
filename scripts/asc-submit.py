#!/usr/bin/env python3
"""Submits an uploaded build for App Store review through the App Store Connect API.

    scripts/asc-submit.py 1.4.1 11            # version, build number
    scripts/asc-submit.py 1.4.1 11 --dry-run  # read-only: shows what it would do

Steps: find the app, wait until the build has finished processing, create the
App Store version if it doesn't exist yet, attach the build, fill in
"What's New" from store/whats-new/<locale>.txt, and submit for review.

Needs an App Store Connect API key (App Manager role) in the environment:
ASC_KEY_PATH (the AuthKey_XXXX.p8 file), ASC_KEY_ID and ASC_ISSUER_ID.
Uses only the Python standard library and the `openssl` command.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.heeyeonlee.token-jandi"
PLATFORM = "MAC_OS"
WHATS_NEW_DIR = Path(__file__).resolve().parent.parent / "store" / "whats-new"
FALLBACK_LOCALE = "en-US"
PROCESSING_TIMEOUT = 30 * 60


def die(message):
    sys.exit(f"error: {message}")


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_to_raw_signature(der):
    """ECDSA signatures come out of openssl as DER; JWT wants r || s, 32 bytes each."""

    def read_int(offset):
        if der[offset] != 0x02:
            die("unexpected signature format from openssl")
        length = der[offset + 1]
        start = offset + 2
        value = der[start:start + length].lstrip(b"\x00")
        return value.rjust(32, b"\x00"), start + length

    offset = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    r, offset = read_int(offset)
    s, _ = read_int(offset)
    return r + s


class Client:
    def __init__(self, key_path, key_id, issuer_id, dry_run):
        self.key_path, self.key_id, self.issuer_id = key_path, key_id, issuer_id
        self.dry_run = dry_run
        self._token, self._expires = None, 0

    def token(self):
        now = int(time.time())
        if self._token and now < self._expires - 60:
            return self._token
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {"iss": self.issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
        signing_input = b".".join(b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, payload))
        signed = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", self.key_path],
            input=signing_input, capture_output=True,
        )
        if signed.returncode != 0:
            die(f"could not sign with {self.key_path}: {signed.stderr.decode().strip()}")
        self._token = (signing_input + b"." + b64url(der_to_raw_signature(signed.stdout))).decode()
        self._expires = now + 15 * 60
        return self._token

    def request(self, method, path, params=None, body=None):
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", "Bearer " + self.token())
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            try:
                lines = []
                for item in json.loads(detail)["errors"]:
                    lines.append(f"{item.get('title')}: {item.get('detail')}")
                    # The real reason is usually nested here, e.g. an unanswered
                    # age rating question that blocks the submission.
                    associated = (item.get("meta") or {}).get("associatedErrors") or {}
                    for resource, causes in associated.items():
                        for cause in causes:
                            lines.append(f"  - {resource}: {cause.get('detail')}")
                detail = "\n".join(lines)
            except (ValueError, KeyError):
                pass
            die(f"{method} {path} failed ({error.code}): {detail}")
        return json.loads(raw) if raw else {}

    def get(self, path, **params):
        return self.request("GET", path, params)

    def write(self, method, path, body, what):
        """Every change goes through here so --dry-run can't change anything."""
        if self.dry_run:
            print(f"   (dry run) would {what}")
            return None
        print(f"   {what}")
        return self.request(method, path, body=body)


def find_app(client):
    apps = client.get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        die(f"no app with bundle ID {BUNDLE_ID} is visible to this API key")
    return apps[0]["id"]


def wait_for_build(client, app_id, version, build_number):
    deadline = time.time() + PROCESSING_TIMEOUT
    while True:
        builds = client.get(
            "/v1/builds",
            **{
                "filter[app]": app_id,
                "filter[version]": build_number,
                "filter[preReleaseVersion.version]": version,
                "filter[preReleaseVersion.platform]": PLATFORM,
            },
        )["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT_VISIBLE_YET"
        if state == "VALID":
            return builds[0]
        if state in ("FAILED", "INVALID"):
            die(f"App Store Connect rejected build {version} ({build_number}): {state}")
        if client.dry_run or time.time() > deadline:
            die(f"build {version} ({build_number}) is not ready: {state}")
        print(f"   build is {state}; checking again in 30s")
        time.sleep(30)


def ensure_export_compliance(client, app_id, build):
    """The encryption question has to be answered before review. It is a legal
    declaration, so this only repeats the answer already given for the most
    recent earlier build and never invents one."""
    if build["attributes"].get("usesNonExemptEncryption") is not None:
        return
    earlier = client.get(
        "/v1/builds",
        **{"filter[app]": app_id, "filter[preReleaseVersion.platform]": PLATFORM, "sort": "-uploadedDate", "limit": 20},
    )["data"]
    answers = [
        item["attributes"]["usesNonExemptEncryption"]
        for item in earlier
        if item["id"] != build["id"] and item["attributes"].get("usesNonExemptEncryption") is not None
    ]
    if not answers:
        die(
            "this build has no export compliance answer and no earlier build has one to repeat. "
            "Answer the encryption question for the build in App Store Connect once, or add "
            "ITSAppUsesNonExemptEncryption to Info.plist, then run this again"
        )
    client.write(
        "PATCH", f"/v1/builds/{build['id']}",
        {"data": {"type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": answers[0]}}},
        f"repeat the previous export compliance answer (usesNonExemptEncryption = {answers[0]})",
    )


def ensure_version(client, app_id, version):
    versions = client.get(
        f"/v1/apps/{app_id}/appStoreVersions",
        **{"filter[platform]": PLATFORM, "filter[versionString]": version},
    )["data"]
    if versions:
        state = versions[0]["attributes"].get("appVersionState") or versions[0]["attributes"].get("appStoreState")
        print(f"   App Store version {version} exists ({state})")
        return versions[0]["id"], state
    created = client.write(
        "POST", "/v1/appStoreVersions",
        {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": PLATFORM, "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }},
        f"create App Store version {version}",
    )
    return (created["data"]["id"] if created else None), "PREPARE_FOR_SUBMISSION"


def set_whats_new(client, version_id):
    localizations = client.get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    for localization in localizations:
        locale = localization["attributes"]["locale"]
        candidates = [locale, locale.split("-")[0], FALLBACK_LOCALE]
        source = next((WHATS_NEW_DIR / f"{name}.txt" for name in candidates if (WHATS_NEW_DIR / f"{name}.txt").exists()), None)
        if source is None:
            die(f"no What's New text for {locale}; add {WHATS_NEW_DIR / (locale + '.txt')}")
        text = source.read_text(encoding="utf-8").strip()
        if not text:
            die(f"{source} is empty")
        if len(text) > 4000:
            die(f"{source} is longer than the 4000 character limit")
        if (localization["attributes"].get("whatsNew") or "").strip() == text:
            continue
        client.write(
            "PATCH", f"/v1/appStoreVersionLocalizations/{localization['id']}",
            {"data": {"type": "appStoreVersionLocalizations", "id": localization["id"], "attributes": {"whatsNew": text}}},
            f"set What's New for {locale} from {source.name}",
        )


def submit(client, app_id, version_id):
    open_submissions = client.get(
        "/v1/reviewSubmissions",
        **{"filter[app]": app_id, "filter[platform]": PLATFORM, "filter[state]": "READY_FOR_REVIEW"},
    )["data"]
    if open_submissions:
        submission_id = open_submissions[0]["id"]
        items = client.get(f"/v1/reviewSubmissions/{submission_id}/items", include="appStoreVersion")["data"]
    else:
        created = client.write(
            "POST", "/v1/reviewSubmissions",
            {"data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": PLATFORM},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }},
            "open a review submission",
        )
        submission_id, items = (created["data"]["id"] if created else None), []

    already_added = any(
        ((item.get("relationships") or {}).get("appStoreVersion") or {}).get("data", {}).get("id") == version_id
        for item in items
    )
    if not already_added:
        client.write(
            "POST", "/v1/reviewSubmissionItems",
            {"data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }},
            "add the version to the submission",
        )
    client.write(
        "PATCH", f"/v1/reviewSubmissions/{submission_id}",
        {"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}},
        "submit for review",
    )


def main():
    args = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    dry_run = "--dry-run" in sys.argv
    if len(args) != 2:
        die("usage: scripts/asc-submit.py <version> <build number> [--dry-run]")
    version, build_number = args

    try:
        key_path, key_id, issuer_id = (os.environ[name] for name in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID"))
    except KeyError as missing:
        die(f"{missing.args[0]} is not set")
    key_path = os.path.expanduser(key_path)
    if not os.path.isfile(key_path):
        die(f"API key file not found: {key_path}")

    client = Client(key_path, key_id, issuer_id, dry_run)

    print("-> Finding the app")
    app_id = find_app(client)

    print(f"-> Waiting for build {version} ({build_number}) to finish processing")
    build = wait_for_build(client, app_id, version, build_number)
    ensure_export_compliance(client, app_id, build)

    print(f"-> Preparing App Store version {version}")
    version_id, state = ensure_version(client, app_id, version)
    if state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION"):
        print(f"   nothing to do: {version} is already {state}")
        return
    if version_id is None:
        print("   (dry run) stopping here: the version does not exist yet, so the remaining steps can't be previewed")
        return

    client.write(
        "PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
        f"attach build {build_number}",
    )
    set_whats_new(client, version_id)

    print("-> Submitting for review")
    submit(client, app_id, version_id)
    print("   (dry run) nothing was changed" if dry_run else f"   {version} ({build_number}) is waiting for review")


if __name__ == "__main__":
    main()
