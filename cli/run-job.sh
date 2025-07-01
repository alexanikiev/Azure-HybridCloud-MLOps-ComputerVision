#!/bin/bash
set -e

job=$1
experiment_name=$2
option=$3

# Validate required env vars
if [[ -z "$RESOURCE_GROUP" || -z "$AML_WORKSPACE" ]]; then
  echo "Missing required environment variables: RESOURCE_GROUP or AML_WORKSPACE"
  exit 1
fi

# Construct base command with common flags
base_cmd="az ml job create -f $job --resource-group $RESOURCE_GROUP --workspace-name $AML_WORKSPACE --query name -o tsv --verbose --debug"

# Add experiment name and force rerun if provided
if [[ -n "$experiment_name" ]]; then
  run_id=$($base_cmd --set experiment_name=$experiment_name --set settings.force_rerun=True)
elif [[ "$job" =~ pipeline.yml ]]; then
  run_id=$($base_cmd --set settings.force_rerun=True)
else
  run_id=$($base_cmd)
fi

# Early exit if job failed to create
if [[ -z "$run_id" ]]; then
  echo "Job creation failed"
  exit 3
fi

# If 'nowait' option is passed, just print the studio URI and exit
if [[ "$option" == "nowait" ]]; then
  az ml job show --name "$run_id" --resource-group "$RESOURCE_GROUP" --workspace-name "$AML_WORKSPACE" --query services.Studio.endpoint
  exit 0
fi

# Poll until job completes
job_uri=$(az ml job show --name "$run_id" --resource-group "$RESOURCE_GROUP" --workspace-name "$AML_WORKSPACE" --query services.Studio.endpoint)
echo "$job_uri"

status=$(az ml job show --name "$run_id" --resource-group "$RESOURCE_GROUP" --workspace-name "$AML_WORKSPACE" --query status -o tsv)

running=("Queued" "NotStarted" "Starting" "Preparing" "Running" "Finalizing")
while [[ ${running[*]} =~ $status ]]; do
  echo "$job_uri"
  sleep 8
  status=$(az ml job show --name "$run_id" --resource-group "$RESOURCE_GROUP" --workspace-name "$AML_WORKSPACE" --query status -o tsv)
  echo "$status"
done

if [[ "$status" == "Completed" ]]; then
  echo "Job completed"
  exit 0
elif [[ "$status" == "Failed" ]]; then
  echo "Job failed"
  exit 1
else
  echo "Job ended with unexpected status: $status"
  exit 2
fi
