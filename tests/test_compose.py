"""The runner fleet's Compose files keep the fleet safe and the CI test isolated (ADR 0015, plans/runner-fleet-compose.md)."""

from __future__ import annotations

import ipaddress
import re
from pathlib import Path
from typing import Any

import pytest
import yaml
from repo_conventions import COMPOSE_TEST, DIRECT_DOCKER_WORKFLOWS, FLEET_DIR, WORKFLOWS_DIR, load_workflow

PIPE = r"\\.\pipe\docker_engine"
RUNNERS = [f"runner{i}" for i in range(1, 6)]


class _ComposeLoader(yaml.SafeLoader):
    """SafeLoader that also reads Compose's !override and !reset merge tags as plain values."""


def _plain(loader: yaml.SafeLoader, _suffix: str, node: yaml.Node) -> Any:
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    return loader.construct_scalar(node)


_ComposeLoader.add_multi_constructor("!", _plain)


def load_compose(name: str) -> dict[str, Any]:
    return yaml.load((FLEET_DIR / name).read_text(encoding="utf-8"), Loader=_ComposeLoader)


def default(value: str) -> str:
    """The value Compose uses when the variable is unset: ${VAR:-default} -> default."""
    return re.sub(r"\$\{\w+:-([^}]*)\}", r"\1", value)


FLEET = load_compose("compose.yaml")
CI = load_compose("compose.ci.yaml")
SERVICES = FLEET["services"]
CACHE = SERVICES["artifact-cache"]
NETWORK = FLEET["networks"]["fleet"]
CACHE_IP = ipaddress.ip_address(default(CACHE["networks"]["fleet"]["ipv4_address"]))
SUBNET = ipaddress.ip_network(default(NETWORK["ipam"]["config"][0]["subnet"]))


def test_fleet_has_the_cache_and_five_runners() -> None:
    assert sorted(SERVICES) == sorted(["artifact-cache", *RUNNERS])


@pytest.mark.parametrize("runner", RUNNERS)
class TestRunner:
    def test_uses_process_isolation_and_the_docker_pipe(self, runner: str) -> None:
        service = SERVICES[runner]
        assert service["isolation"] == "process", "the docker pipe can only be mounted with process isolation"
        assert {"type": "npipe", "source": PIPE, "target": PIPE} in service["volumes"]

    def test_has_no_bind_mounts(self, runner: str) -> None:
        binds = [v for v in SERVICES[runner]["volumes"] if v.get("type") != "npipe"]
        assert not binds, f"{runner} must not bind-mount host folders (CLAUDE.md): {binds}"

    def test_restarts_and_waits_for_a_healthy_cache(self, runner: str) -> None:
        service = SERVICES[runner]
        assert service["restart"] == "unless-stopped"
        assert service["depends_on"] == {"artifact-cache": {"condition": "service_healthy"}}
        assert service["networks"] == ["fleet"]

    def test_token_comes_from_the_environment(self, runner: str) -> None:
        token = SERVICES[runner]["environment"]["RUNNER_TOKEN"]
        assert re.fullmatch(r"\$\{RUNNER_TOKEN(:-)?\}", token), f"{runner} has a literal registration token"

    def test_gets_the_cache_address(self, runner: str) -> None:
        env = SERVICES[runner]["environment"]
        assert ipaddress.ip_address(default(env["ARTIFACT_CACHE_IP"])) == CACHE_IP
        assert default(env["ARTIFACT_CACHE_NETWORK"]) == default(NETWORK["name"])


def test_runner_names_match_the_runners_they_replace() -> None:
    names = [SERVICES[r]["environment"]["RUNNER_NAME"] for r in RUNNERS]
    suffixes = [n.rsplit("}", 1)[-1] for n in names]
    assert suffixes == ["-nano", "-nano2", "-nano3", "-nano4", "-nano5"], "same names as run-runner.ps1 used"
    assert all(n.startswith("${RUNNER_NAME_PREFIX:-${COMPUTERNAME}}") for n in names)


def test_cache_has_a_fixed_address_inside_the_fleet_subnet() -> None:
    assert NETWORK["driver"] == "nat"
    assert CACHE_IP in SUBNET
    assert ipaddress.ip_address(default(NETWORK["ipam"]["config"][0]["gateway"])) in SUBNET
    assert "artifact-cache" in CACHE["networks"]["fleet"]["aliases"]


def test_cache_has_a_healthcheck_on_healthz() -> None:
    assert "http://localhost:8080/healthz" in CACHE["healthcheck"]["test"]


@pytest.mark.parametrize("target", [r"C:\cache", r"C:\caddy-data"])
def test_cache_keeps_its_folders_on_the_host(target: str) -> None:
    (mount,) = [v for v in CACHE["volumes"] if v["target"] == target]
    assert mount["type"] == "bind"
    assert default(mount["source"]).startswith("C:\\ProgramData\\windows-nano-demos\\artifact-cache\\")


@pytest.mark.parametrize("service", sorted(CI["services"]))
def test_ci_overrides_never_restart(service: str) -> None:
    assert CI["services"][service]["restart"] == "no"


def test_ci_cache_uses_throwaway_volumes_not_host_folders() -> None:
    volumes = CI["services"]["artifact-cache"]["volumes"]
    assert {v["target"] for v in volumes} == {r"C:\cache", r"C:\caddy-data"}
    assert all(v["type"] == "volume" for v in volumes)
    assert "!override" in (FLEET_DIR / "compose.ci.yaml").read_text(encoding="utf-8"), "replace, don't merge, the binds"


def test_ci_runner_checks_connectivity_instead_of_registering() -> None:
    command = " ".join(CI["services"]["runner1"]["entrypoint"])
    assert "start.ps1" not in command
    assert "docker version" in command
    assert "runner check passed" in command


def test_ci_starts_only_runner1() -> None:
    assert set(CI["services"]) == {"artifact-cache", "runner1"}
    script = (FLEET_DIR / COMPOSE_TEST).read_text(encoding="utf-8")
    for other in RUNNERS[1:]:
        assert other not in script


def _ps_default(script: str, name: str) -> str:
    match = re.search(rf"\[string\]\${name}\s*=\s*'([^']+)'", (FLEET_DIR / script).read_text(encoding="utf-8"))
    assert match, f"{script} has no default for -{name}"
    return match.group(1)


def test_ci_test_uses_a_different_subnet_from_the_fleet() -> None:
    subnet = ipaddress.ip_network(_ps_default(COMPOSE_TEST, "Subnet"))
    assert not subnet.overlaps(SUBNET), "a CI run must not collide with the running fleet's network"
    assert ipaddress.ip_address(_ps_default(COMPOSE_TEST, "CacheIp")) in subnet
    assert ipaddress.ip_address(_ps_default(COMPOSE_TEST, "Gateway")) in subnet


def test_compose_binary_is_pinned_by_version_and_sha256() -> None:
    text = (FLEET_DIR / "Install-Compose.ps1").read_text(encoding="utf-8")
    assert re.search(r"\$version = 'v\d+\.\d+\.\d+'", text)
    assert re.search(r"\$sha256 = '[0-9a-f]{64}'", text)


@pytest.mark.parametrize("image", ["RunnerImage", "CacheImage"])
def test_start_script_defaults_match_the_compose_file(image: str) -> None:
    key = {"RunnerImage": SERVICES["runner1"]["image"], "CacheImage": CACHE["image"]}[image]
    assert _ps_default("Start-RunnerFleet.ps1", image) == default(key)


@pytest.mark.parametrize("workflow", sorted(DIRECT_DOCKER_WORKFLOWS))
class TestDirectDockerWorkflow:
    def test_exists(self, workflow: str) -> None:
        assert (WORKFLOWS_DIR / workflow).is_file()

    def test_runs_the_compose_test_one_at_a_time(self, workflow: str) -> None:
        wf = load_workflow(WORKFLOWS_DIR / workflow)
        assert wf["concurrency"]["cancel-in-progress"] is False
        assert "github.event" not in wf["concurrency"]["group"], "one group for the whole repo: the subnet is fixed"
        steps = [s.get("run", "") for job in wf["jobs"].values() for s in job["steps"]]
        assert any(COMPOSE_TEST in s for s in steps)

    @pytest.mark.parametrize("event", ["push", "pull_request"])
    def test_triggers_on_the_fleet_folder(self, workflow: str, event: str) -> None:
        paths = load_workflow(WORKFLOWS_DIR / workflow)["on"][event]["paths"]
        assert f"{Path(FLEET_DIR).relative_to(FLEET_DIR.parent.parent).as_posix()}/**" in paths


# --- Runners for other repositories (compose.runners.yaml, Start-RepoRunners.ps1) ---

REPO_RUNNERS = load_compose("compose.runners.yaml")
REPO_SERVICES = REPO_RUNNERS["services"]


def test_repo_runners_file_starts_only_runners() -> None:
    assert sorted(REPO_SERVICES) == RUNNERS, "the cache belongs to the fleet; this file must not start another one"


def test_repo_runners_join_the_fleet_network() -> None:
    network = REPO_RUNNERS["networks"]["fleet"]
    assert network["external"] is True, "join the fleet's network, never create a second one on its subnet"
    assert default(network["name"]) == default(NETWORK["name"])


@pytest.mark.parametrize("variable", ["FLEET_PROJECT", "RUNNER_REPO", "RUNNER_NAME_PREFIX"])
def test_repo_runners_require_their_settings(variable: str) -> None:
    text = (FLEET_DIR / "compose.runners.yaml").read_text(encoding="utf-8")
    assert f"${{{variable}:?" in text, f"{variable} must be required, so the runners never default to the fleet's"


@pytest.mark.parametrize("runner", RUNNERS)
class TestRepoRunner:
    def test_uses_process_isolation_and_the_docker_pipe(self, runner: str) -> None:
        service = REPO_SERVICES[runner]
        assert service["isolation"] == "process"
        assert {"type": "npipe", "source": PIPE, "target": PIPE} in service["volumes"]

    def test_has_no_bind_mounts(self, runner: str) -> None:
        binds = [v for v in REPO_SERVICES[runner]["volumes"] if v.get("type") != "npipe"]
        assert not binds, f"{runner} must not bind-mount host folders (CLAUDE.md): {binds}"

    def test_token_comes_from_the_environment(self, runner: str) -> None:
        token = REPO_SERVICES[runner]["environment"]["RUNNER_TOKEN"]
        assert re.fullmatch(r"\$\{RUNNER_TOKEN(:-)?\}", token)

    def test_gets_the_fleet_cache_address(self, runner: str) -> None:
        env = REPO_SERVICES[runner]["environment"]
        assert ipaddress.ip_address(default(env["ARTIFACT_CACHE_IP"])) == CACHE_IP
        assert default(env["ARTIFACT_CACHE_NETWORK"]) == default(NETWORK["name"])

    def test_name_is_the_prefix_and_its_number(self, runner: str) -> None:
        name = REPO_SERVICES[runner]["environment"]["RUNNER_NAME"]
        assert name.startswith("${RUNNER_NAME_PREFIX:?") and name.endswith("}" + runner.removeprefix("runner"))


@pytest.mark.parametrize(
    ("parameter", "expected"),
    [
        ("RunnerImage", default(SERVICES["runner1"]["image"])),
        ("Network", default(NETWORK["name"])),
        ("CacheIp", str(CACHE_IP)),
    ],
)
def test_repo_runners_script_defaults_match_the_fleet(parameter: str, expected: str) -> None:
    assert _ps_default("Start-RepoRunners.ps1", parameter) == expected


# --- Set-RunnerCount.ps1 scales runner services only, and drains through Stop-ActionRunners.ps1 ---

SCALE_SCRIPT = (FLEET_DIR / "Set-RunnerCount.ps1").read_text(encoding="utf-8")


@pytest.mark.parametrize("file", ["compose.yaml", "compose.runners.yaml"])
def test_set_runner_count_matches_every_runner_service_and_nothing_else(file: str) -> None:
    pattern = re.search(r"\$service -match '([^']+)'", SCALE_SCRIPT).group(1)
    for service in load_compose(file)["services"]:
        assert bool(re.match(pattern, service)) == service.startswith("runner"), f"{file}: {service}"


def test_set_runner_count_stops_through_the_draining_stop_script() -> None:
    assert "Stop-ActionRunners.ps1" in SCALE_SCRIPT
    assert "docker stop" not in SCALE_SCRIPT, "stop runners only after they finish their jobs"


def test_set_runner_count_points_at_the_fleet_start_script_for_the_fleet_project() -> None:
    assert f"'{default(FLEET['name'])}'" in SCALE_SCRIPT


# --- Several runners in one container (ADR 0019): the runner image's RUNNER_COUNT, set by the start scripts ---

RUNNER_IMAGE_DIR = FLEET_DIR.parent.parent / "nano-server" / "nano-server-gh-runner"
ENTRYPOINT = (RUNNER_IMAGE_DIR / "start.ps1").read_text(encoding="utf-8")
STOP_SCRIPT = (FLEET_DIR / "Stop-ActionRunners.ps1").read_text(encoding="utf-8")
START_SCRIPTS = ["Start-RunnerFleet.ps1", "Start-RepoRunners.ps1"]
# Compose variable -> the runner container's environment variable it sets, and the value when it is unset
RUNNER_SETTINGS = [
    ("RUNNERS_PER_CONTAINER", "RUNNER_COUNT", "1"),
    ("RUNNER_LABELS", "RUNNER_LABELS", "nanoserver,docker"),
    ("RUNNER_DISABLE_UPDATE", "RUNNER_DISABLE_UPDATE", ""),
]


@pytest.mark.parametrize("file", ["compose.yaml", "compose.runners.yaml"])
@pytest.mark.parametrize("runner", RUNNERS)
@pytest.mark.parametrize(("variable", "setting", "unset"), RUNNER_SETTINGS)
def test_runner_setting_comes_from_the_environment(
    file: str, runner: str, variable: str, setting: str, unset: str
) -> None:
    value = load_compose(file)["services"][runner]["environment"][setting]
    assert value == f"${{{variable}:-{unset}}}", (
        f"{file}: {runner} must read {setting} from {variable}, default '{unset}'"
    )


@pytest.mark.parametrize("script", START_SCRIPTS)
@pytest.mark.parametrize("variable", [variable for variable, _, _ in RUNNER_SETTINGS])
def test_start_script_sets_every_runner_setting(script: str, variable: str) -> None:
    text = (FLEET_DIR / script).read_text(encoding="utf-8")
    assert f"$env:{variable} = " in text, f"{script} must set {variable}, or a value left in the shell would be used"


@pytest.mark.parametrize("script", START_SCRIPTS)
def test_start_script_defaults_to_one_runner_in_each_container(script: str) -> None:
    text = (FLEET_DIR / script).read_text(encoding="utf-8")
    assert re.search(r"\[ValidateRange\(1, 16\)\]\[int\]\$RunnersPerContainer = 1\b", text)
    assert _ps_default(script, "Labels") == "nanoserver,docker"


@pytest.mark.parametrize("setting", [setting for _, setting, _ in RUNNER_SETTINGS])
def test_entrypoint_reads_every_setting_the_compose_files_pass(setting: str) -> None:
    assert f"$env:{setting}" in ENTRYPOINT


def test_entrypoint_and_stop_script_agree_on_the_runner_names() -> None:
    # start.ps1 registers runner n as <name>-<n>; Stop-ActionRunners.ps1 must wait for exactly those names
    assert '$number -eq 1 ? $name : "$name-$number"' in ENTRYPOINT
    assert "RUNNER_COUNT=*" in STOP_SCRIPT
    assert '"$runnerName-$_"' in STOP_SCRIPT
    assert "$target.RunnerNames" in STOP_SCRIPT, "a container is idle only when every runner in it is"


def test_entrypoint_limits_match_the_start_scripts() -> None:
    assert "$count -ge 1 -and $count -le 16" in ENTRYPOINT


def test_entrypoint_can_print_its_plan_without_registering() -> None:
    assert "[ValidateSet('Run', 'Plan', 'Prepare')][string]$Mode = 'Run'" in ENTRYPOINT
    smoke = (RUNNER_IMAGE_DIR / "smoke-test.ps1").read_text(encoding="utf-8")
    assert "-Mode Plan" in smoke and "-Mode Prepare" in smoke, "the smoke test checks the plan without a token"
