from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("prepare-assets.sh")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_lock(path: Path, runtime_url: str, source_url: str,
               runtime_digest: str, source_digest: str) -> None:
    """The lock shape prepare-assets.sh validates before anything else."""
    path.write_text(
        json.dumps(
            {
                "runtime": {
                    "url": runtime_url,
                    "filename": "runtime.zip",
                    "sha256": runtime_digest,
                },
                "source": {
                    "url": source_url,
                    "filename": "source.zip",
                    "sha256": source_digest,
                },
            }
        ),
        encoding="utf-8",
    )


class PrepareAssetsTests(unittest.TestCase):
    def test_builder_staged_runtime_is_asserted_and_source_is_staged(self) -> None:
        """One owner for runtime acquisition (FID-2026-0914-002): the
        BUILDER stages the runtime archive and its SHA256SUMS entry; this
        script must assert the pinned digest against the payload and stage
        ONLY the source archive. The runtime URL is deliberately
        unreachable — reaching exit 0 proves the script never fetches it."""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifacts = root / "artifacts"
            payloads = root / "payloads"
            artifacts.mkdir()
            payloads.mkdir()
            seed = b"guest metadata"
            runtime = b"runtime archive"
            (artifacts / "guest.json").write_bytes(seed)
            (artifacts / "runtime.zip").write_bytes(runtime)
            (artifacts / "SHA256SUMS").write_text(
                f"{sha256(seed)}  guest.json\n{sha256(runtime)}  runtime.zip\n",
                encoding="utf-8",
                newline="\n",
            )

            source = f"source archive".encode()
            source_path = payloads / "source.zip"
            source_path.write_bytes(source)
            lock = root / "runtime.lock.json"
            write_lock(
                lock,
                "https://example.invalid/runtime.zip",
                source_path.as_uri(),
                sha256(runtime),
                sha256(source),
            )
            env = os.environ.copy()
            env["SAVANTOS_RUNTIME_LOCK"] = str(lock)

            result = subprocess.run(
                ["bash", str(SCRIPT), str(artifacts)],
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            sums = (artifacts / "SHA256SUMS").read_text(encoding="utf-8")
            self.assertIn(f"{sha256(runtime)}  runtime.zip\n", sums)
            self.assertIn(f"{sha256(source)}  source.zip", sums)

    def test_missing_runtime_entry_fails_closed(self) -> None:
        """A payload whose SHA256SUMS lacks the builder's pinned runtime
        entry must be refused with the actionable message — not silently
        repaired by staging a second copy here."""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifacts = root / "artifacts"
            payloads = root / "payloads"
            artifacts.mkdir()
            payloads.mkdir()
            seed = b"guest metadata"
            runtime = b"runtime archive"
            (artifacts / "guest.json").write_bytes(seed)
            (artifacts / "SHA256SUMS").write_text(
                f"{sha256(seed)}  guest.json\n",
                encoding="utf-8",
                newline="\n",
            )

            source = f"source archive".encode()
            source_path = payloads / "source.zip"
            source_path.write_bytes(source)
            lock = root / "runtime.lock.json"
            write_lock(
                lock,
                "https://example.invalid/runtime.zip",
                source_path.as_uri(),
                sha256(runtime),
                sha256(source),
            )
            env = os.environ.copy()
            env["SAVANTOS_RUNTIME_LOCK"] = str(lock)

            result = subprocess.run(
                ["bash", str(SCRIPT), str(artifacts)],
                text=True,
                capture_output=True,
                check=False,
                env=env,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("lacks the pinned runtime archive entry", result.stderr)
            self.assertIn("rebuild with the current builder", result.stderr)


if __name__ == "__main__":
    unittest.main()
