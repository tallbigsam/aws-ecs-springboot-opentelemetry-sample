#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="${SCRIPT_DIR}/../templates/otel-service.yaml"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Configure OTel collector to send telemetry to Grafana Cloud.

Required:
  --instance-id ID       Grafana Cloud instance ID (e.g., 1289964)
  --api-key KEY          Grafana Cloud API key (glc_...)
  --endpoint URL         OTLP endpoint URL (e.g., https://otlp-gateway-prod-gb-south-1.grafana.net/otlp)

Optional:
  --cluster NAME         ECS cluster name (for forcing deployment)
  --service NAME         ECS service name (for forcing deployment)
  --ssm-param NAME       SSM parameter name (default: /aot/config)
  --apply                Apply changes to SSM and force ECS deployment
  --help                 Show this help message

Examples:
  # Preview changes (dry run):
  $(basename "$0") --instance-id 1289964 --api-key 'glc_xxx...' --endpoint 'https://otlp-gateway-prod-gb-south-1.grafana.net/otlp'

  # Apply changes to SSM and restart ECS:
  $(basename "$0") --instance-id 1289964 --api-key 'glc_xxx...' --endpoint 'https://otlp-gateway-prod-gb-south-1.grafana.net/otlp' \\
    --cluster my-cluster --service otel-service --apply

EOF
    exit 1
}

INSTANCE_ID=""
API_KEY=""
ENDPOINT=""
CLUSTER=""
SERVICE=""
SSM_PARAM="/aot/config"
APPLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --instance-id) INSTANCE_ID="$2"; shift 2 ;;
        --api-key) API_KEY="$2"; shift 2 ;;
        --endpoint) ENDPOINT="$2"; shift 2 ;;
        --cluster) CLUSTER="$2"; shift 2 ;;
        --service) SERVICE="$2"; shift 2 ;;
        --ssm-param) SSM_PARAM="$2"; shift 2 ;;
        --apply) APPLY=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$INSTANCE_ID" || -z "$API_KEY" || -z "$ENDPOINT" ]]; then
    echo "Error: --instance-id, --api-key, and --endpoint are required"
    echo
    usage
fi

AUTH_STRING="${INSTANCE_ID}:${API_KEY}"
AUTH_BASE64=$(echo -n "$AUTH_STRING" | base64)
AUTH_HEADER="Basic ${AUTH_BASE64}"

echo "=== Grafana Cloud OTLP Configuration ==="
echo "Instance ID: ${INSTANCE_ID}"
echo "API Key:     ${API_KEY:0:20}..."
echo "Endpoint:    ${ENDPOINT}"
echo "Auth Header: Basic ${AUTH_BASE64:0:30}..."
echo

CONFIG=$(cat << EOF
extensions:
  health_check:
  pprof:
    endpoint: 0.0.0.0:1777

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:55681
  awsxray:
    endpoint: 0.0.0.0:2000
    transport: udp
  statsd:
    endpoint: 0.0.0.0:8125
    aggregation_interval: 60s
  awsecscontainermetrics:
    collection_interval: 60s

processors:
  filter:
    metrics:
      include:
        match_type: regexp
        metric_names:
          - '^ecs\..*'
          - '^http\..*'
          - '^runtime\.jvm\..*'

exporters:
  otlphttp/grafana:
    endpoint: ${ENDPOINT}
    headers:
      Authorization: ${AUTH_HEADER}

service:
  pipelines:
    traces:
      receivers: [ otlp ]
      exporters: [ otlphttp/grafana ]
    metrics:
      receivers: [ otlp ]
      exporters: [ otlphttp/grafana ]
EOF
)

echo "=== Generated OTel Config ==="
echo "$CONFIG"
echo

if [[ "$APPLY" == true ]]; then
    echo "=== Applying Changes ==="
    
    echo "Updating SSM parameter: ${SSM_PARAM}"
    aws ssm put-parameter \
        --name "$SSM_PARAM" \
        --type String \
        --overwrite \
        --value "$CONFIG" \
        --tier Advanced
    echo "SSM parameter updated successfully"
    
    if [[ -n "$CLUSTER" && -n "$SERVICE" ]]; then
        echo "Forcing ECS deployment: ${CLUSTER}/${SERVICE}"
        aws ecs update-service \
            --cluster "$CLUSTER" \
            --service "$SERVICE" \
            --force-new-deployment \
            --query 'service.serviceName' \
            --output text
        echo "ECS deployment triggered successfully"
        echo
        echo "Monitor deployment with:"
        echo "  aws ecs describe-services --cluster ${CLUSTER} --services ${SERVICE} --query 'services[0].deployments'"
    else
        echo
        echo "Warning: --cluster and --service not provided, skipping ECS deployment"
        echo "Run manually: aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment"
    fi
else
    echo "=== Dry Run Mode ==="
    echo "Add --apply to update SSM parameter and restart ECS"
    echo "Add --cluster and --service to also force ECS deployment"
fi

echo
echo "=== Updating CloudFormation Template ==="

ESCAPED_ENDPOINT=$(echo "$ENDPOINT" | sed 's/[&/\]/\\&/g')
ESCAPED_AUTH=$(echo "$AUTH_HEADER" | sed 's/[&/\]/\\&/g')

if [[ -f "$TEMPLATE_PATH" ]]; then
    sed -i.bak \
        -e "s|endpoint: https://otlp-gateway-[^[:space:]]*|endpoint: ${ESCAPED_ENDPOINT}|g" \
        -e "s|Authorization: Basic [A-Za-z0-9+/=]*|Authorization: ${ESCAPED_AUTH}|g" \
        "$TEMPLATE_PATH"
    rm -f "${TEMPLATE_PATH}.bak"
    echo "Updated: ${TEMPLATE_PATH}"
else
    echo "Warning: Template not found at ${TEMPLATE_PATH}"
fi

echo
echo "=== SAM Deploy Parameters ==="
echo "Use these with 'sam deploy' to pass credentials as parameters:"
echo
echo "sam deploy --parameter-overrides \\"
echo "  GrafanaOtlpEndpoint='${ENDPOINT}' \\"
echo "  GrafanaAuthHeader='${AUTH_HEADER}' \\"
echo "  ConfigVersion='$(date +%s)'"
echo
echo "Done!"
