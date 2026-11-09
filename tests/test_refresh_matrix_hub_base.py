"""refresh_matrix.py with images built on zippy1981/nanoserver-base (issue #71). The registries are faked."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import refresh_matrix as rm

HUB_TOKEN = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:zippy1981/nanoserver-base:pull"
HUB_MANIFEST = "https://registry-1.docker.io/v2/zippy1981/nanoserver-base/manifests/ltsc2022-pwsh"
HUB_BASE = "zippy1981/nanoserver-base:ltsc2022-pwsh"


def fake_fetch(
    responses: dict[str, tuple[int, dict[str, str], object]], requests: list[tuple[str, dict[str, str]]] | None = None
) -> rm.Fetch:
    def fetch(url: str, headers: dict[str, str]) -> tuple[int, dict[str, str], bytes]:
        if requests is not None:
            requests.append((url, headers))
        status, response_headers, body = responses[url]
        return status, response_headers, json.dumps(body).encode()

    return fetch


def write_image(root: Path, base_argument: str) -> None:
    (root / ".github" / "workflows").mkdir(parents=True)
    (root / ".github" / "workflows" / "x.yml").write_text(
        "jobs:\n"
        "  build:\n"
        "    uses: ./.github/workflows/build-windows-image.yml\n"
        "    with:\n"
        "      context: nano-server/nano-server-x\n"
        "      image: windows-nano-x\n",
        encoding="utf-8",
    )
    (root / "nano-server" / "nano-server-x").mkdir(parents=True)
    (root / "nano-server" / "nano-server-x" / "Dockerfile").write_text(
        f"ARG WINDOWS_VERSION=2025\nARG BASE_IMAGE={base_argument}\nFROM ${{BASE_IMAGE}}\n", encoding="utf-8"
    )


class TestHubBase:
    def test_reads_digest_and_os_version_with_a_pull_token(self) -> None:
        requests: list[tuple[str, dict[str, str]]] = []
        registries = rm.Registries(
            fake_fetch(
                {
                    HUB_TOKEN: (200, {}, {"token": "t"}),
                    HUB_MANIFEST: (
                        200,
                        {"docker-content-digest": "sha256:hub"},
                        {"mediaType": "application/vnd.oci.image.manifest.v1+json", "config": {"digest": "sha256:cfg"}},
                    ),
                    "https://registry-1.docker.io/v2/zippy1981/nanoserver-base/blobs/sha256:cfg": (
                        200,
                        {},
                        {"os.version": "10.0.20348.3"},
                    ),
                },
                requests,
            )
        )
        assert registries.base(HUB_BASE) == rm.BaseImage(HUB_BASE, "sha256:hub", "10.0.20348.3")
        assert all(headers.get("Authorization") == "Bearer t" for url, headers in requests if "registry-1" in url)

    def test_is_cached(self) -> None:
        requests: list[tuple[str, dict[str, str]]] = []
        registries = rm.Registries(
            fake_fetch(
                {
                    HUB_TOKEN: (200, {}, {"token": "t"}),
                    HUB_MANIFEST: (
                        200,
                        {"docker-content-digest": "sha256:hub"},
                        {"mediaType": "application/vnd.oci.image.manifest.v1+json", "config": {"digest": "sha256:c"}},
                    ),
                    "https://registry-1.docker.io/v2/zippy1981/nanoserver-base/blobs/sha256:c": (200, {}, {}),
                },
                requests,
            )
        )
        registries.base(HUB_BASE)
        count = len(requests)
        registries.base(HUB_BASE)
        assert len(requests) == count

    def test_unpublished_is_an_error(self) -> None:
        registries = rm.Registries(
            fake_fetch(
                {
                    HUB_TOKEN: (200, {}, {"token": "t"}),
                    HUB_MANIFEST: (401, {}, {"errors": [{"code": "UNAUTHORIZED"}]}),
                }
            )
        )
        with pytest.raises(rm.RegistryError, match="not found on Docker Hub"):
            registries.base(HUB_BASE)

    def test_no_token_is_an_error(self) -> None:
        with pytest.raises(rm.RegistryError, match="not found on Docker Hub"):
            rm.Registries(fake_fetch({HUB_TOKEN: (404, {}, {})})).base(HUB_BASE)

    def test_no_digest_is_an_error(self) -> None:
        registries = rm.Registries(
            fake_fetch(
                {
                    HUB_TOKEN: (200, {}, {"token": "t"}),
                    HUB_MANIFEST: (
                        200,
                        {},
                        {"mediaType": "application/vnd.oci.image.manifest.v1+json", "config": {"digest": "sha256:c"}},
                    ),
                    "https://registry-1.docker.io/v2/zippy1981/nanoserver-base/blobs/sha256:c": (200, {}, {}),
                }
            )
        )
        with pytest.raises(rm.RegistryError, match="Docker Hub returned no digest"):
            registries.base(HUB_BASE)

    @pytest.mark.parametrize(
        "reference", ["docker.io/library/ubuntu:24.04", "someone/nanoserver-base:ltsc2022", "zippy1981/nanoserver-base"]
    )
    def test_other_bases_are_rejected(self, reference: str) -> None:
        with pytest.raises(rm.RegistryError, match="only tagged MCR or zippy1981/"):
            rm.Registries(fake_fetch({})).base(reference)


@pytest.mark.parametrize(
    ("argument", "expected"),
    [
        (
            "mcr.microsoft.com/windows/nanoserver:ltsc${WINDOWS_VERSION}-amd64",
            "mcr.microsoft.com/windows/nanoserver:ltsc2022-amd64",
        ),
        (
            "mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64",
            "mcr.microsoft.com/windows/servercore:ltsc2022-amd64",
        ),
        ("zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}", "zippy1981/nanoserver-base:ltsc2022"),
        ("zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}-pwsh", "zippy1981/nanoserver-base:ltsc2022-pwsh"),
    ],
)
def test_discovery_reads_the_base_image_argument(tmp_path: Path, argument: str, expected: str) -> None:
    write_image(tmp_path, argument)
    (spec,) = rm.discover_images(tmp_path)
    assert spec.bases["2022"] == expected


@pytest.mark.parametrize(
    "argument",
    ["someone/nanoserver-base:ltsc${WINDOWS_VERSION}", "zippy1981/nanoserver-base:ltsc2022", "zippy1981/other:latest"],
)
def test_discovery_rejects_other_base_arguments(tmp_path: Path, argument: str) -> None:
    write_image(tmp_path, argument)
    with pytest.raises(ValueError, match="BASE_IMAGE"):
        rm.discover_images(tmp_path)
