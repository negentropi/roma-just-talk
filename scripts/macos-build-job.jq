def macos_build_provider:
  if (.runnerName | test("^nsc-runner-.+$"))
     and any(.runnerLabels[]; test("^(namespace-profile-|nscloud-macos-).+$"))
  then "namespace"
  elif (.runnerName | test("^GitHub Actions [0-9]+$"))
       and .runnerGroupName == "GitHub Actions"
       and (.runnerLabels | index("macos-26")) != null
  then "github-hosted"
  else null
  end;

def valid_macos_build_job($job_name):
  .name == $job_name
  and .status == "completed"
  and .conclusion == "success"
  and (.jobId | type == "number" and . > 0 and . == floor)
  and (.runnerId | type == "number" and . > 0 and . == floor)
  and (.runnerLabels | type == "array" and all(.[]; type == "string"))
  and (macos_build_provider != null);

def select_macos_build_job($run_id; $job_name):
  select(.jobs | type == "array")
  | [.jobs[] | select(.name == $job_name)]
  | select(length == 1)
  | .[0]
  | select(.run_id == $run_id)
  | {
    jobId: .id,
    name,
    runnerId: .runner_id,
    runnerName: .runner_name,
    runnerGroupName: .runner_group_name,
    runnerLabels: .labels,
    status,
    conclusion,
    startedAt: .started_at,
    completedAt: .completed_at
  }
  | select(valid_macos_build_job($job_name))
  | . + {provider: macos_build_provider}
  | {runId: $run_id, job: .};

def valid_macos_build_job_record($run_id; $job_name):
  (.runId | tostring) == $run_id
  and (.job | valid_macos_build_job($job_name)
       and .provider == macos_build_provider);
