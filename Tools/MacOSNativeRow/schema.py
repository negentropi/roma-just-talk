from dataclasses import dataclass


REPOSITORY = "negentropi/roma-just-talk"
WORKFLOW = ".github/workflows/qualify-macos-distribution.yml"
CONTRACT = "notarized-first-open"
NAMESPACE = "roma-native-first-open@roma-just-talk"
OS_ROWS = {
    "sonoma": ("14.2.1", "23C71", "arm64", "Qualify Sonoma 14.2.1 (23C71)"),
    "tahoe": ("26.4.1", "25E253", "arm64", "Qualify Tahoe 26.4.1 (25E253)"),
}
PHASES = ("download", "extract", "finder-open", "ui-before", "ui-action", "ui-after", "smoke")
TRUST_OUTPUTS = ("developer-id-verification", "signature", "stapled-ticket", "gatekeeper-assessment")
DISTRIBUTION_FILES = frozenset("macos-distribution-e2e/" + name for name in (
    "runner-identity.txt", "gatekeeper-status.txt", "sip-status.txt", "source-artifact.txt",
    "browser-downloaded-artifact.txt", "downloaded-archive-quarantine.txt", "extracted-app-identity.txt",
    "expected-inner-app-files.sha256", "extracted-app-files-before-gatekeeper.sha256",
    "extracted-app-files-after-gatekeeper.sha256", "launched-pid.txt", "approval-window-started-at.txt",
    "approval-window-ended-at.txt", "approval-window-new-crash-reports.txt", "approval-window-distinct-pids.txt",
    "approval-window-unified-log.txt", "launch-verification/source-bundle-files.sha256",
    "launch-verification/process-bundle-files.sha256", "launch-verification/launch-identity.txt",
    "launch-verification/source-app-quarantine.txt", "launch-verification/distribution-launch-verdict.txt",
    "launch-verification/appkit-running-application.txt", "launch-verification/expected-bundle-code.txt",
    "launch-verification/observed-bundle-code.txt", "launch-verification/mapped-code-signatures.txt",
    "launch-verification/process-open-files.txt", "launch-verification/process-open-files-after-stability.txt",
)) | frozenset("macos-distribution-e2e/" + trust + "/" + output
              for trust in ("reference-trust", "extracted-trust-before", "extracted-trust-after")
              for output in ("trust-command-receipts.json", "trust-verdict.txt", *(
                  basename + suffix for basename in TRUST_OUTPUTS for suffix in (".stdout", ".stderr", ".txt"))))
ROW_FILES = DISTRIBUTION_FILES | frozenset((
    "challenge.json", "broker-execution.json", "collector.stdout", "collector.stderr",
    "observer/readiness.json", "observer/process-events.json", "observer/clock.json",
    "manual-whisper-smoke/baseline.json", "manual-whisper-smoke/result.json",
    "manual-whisper-smoke/command-receipts.json", "manual-whisper-smoke/baseline-query.stdout",
    "manual-whisper-smoke/baseline-query.stderr", "manual-whisper-smoke/result-query.stdout",
    "manual-whisper-smoke/result-query.stderr",
))


@dataclass(frozen=True)
class Artifact:
    artifact_id: int
    sha256: str
    size: int


@dataclass(frozen=True)
class Job:
    repository: str
    workflow: str
    tooling_sha: str
    run_id: int
    attempt: int
    job_id: int
    job_name: str
    started_ms: int
    completed_ms: int

    def identity(self):
        return {"repository": self.repository, "workflow": self.workflow, "toolingSha": self.tooling_sha,
                "runId": self.run_id, "runAttempt": self.attempt, "jobId": self.job_id, "jobName": self.job_name}


@dataclass(frozen=True)
class FinalArchive:
    source_sha: str
    artifact_id: int
    transport_sha256: str
    zip_sha256: str
    zip_size: int
    executable_sha256: str
    manifest_sha256: str
    developer_id_team: str
    bundle_id: str

    def identity(self):
        return {"sourceSha": self.source_sha, "artifactId": self.artifact_id, "transportSha256": self.transport_sha256,
                "zipSha256": self.zip_sha256, "zipSize": self.zip_size, "executableSha256": self.executable_sha256,
                "manifestSha256": self.manifest_sha256, "developerIdTeam": self.developer_id_team, "bundleId": self.bundle_id}


@dataclass(frozen=True)
class CallProfile:
    phase: str
    code: str


@dataclass(frozen=True)
class BrokerPolicy:
    identity: str
    namespace: str
    public_key: str
    policy_sha256: str
    exporter_sha256: str
    collector_sha256: str
    transport_identity: str
    collector_argv: tuple[str, ...]
    browser_backend: str
    browser_id: str
    browser_url: str
    calls: tuple[CallProfile, ...]
    max_transport_bytes: int = 12 * 1024 * 1024

    def browser(self):
        return {"backend": self.browser_backend, "browserId": self.browser_id, "url": self.browser_url}


@dataclass(frozen=True)
class ExpectedRow:
    job: Job
    payload: Artifact
    challenge: Artifact
    final: FinalArchive
    row: str
    boot_uuid: str

    def identity(self):
        os = OS_ROWS[self.row]
        return {**self.job.identity(), "row": self.row, "guest": {"productVersion": os[0], "buildVersion": os[1],
                "architecture": os[2], "bootUuid": self.boot_uuid}, "finalArchive": self.final.identity()}


@dataclass(frozen=True)
class FirstProcess:
    pid: int
    start_time_ms: int
    boot_uuid: str
    executable_sha256: str
