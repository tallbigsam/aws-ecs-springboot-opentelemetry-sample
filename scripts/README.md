# Configure Grafana Cloud Script

This script configures the OpenTelemetry collector to send telemetry data to Grafana Cloud via OTLP.

## Prerequisites

- AWS CLI configured with appropriate credentials
- `bash` shell
- Access to your Grafana Cloud OTLP connection details

## Getting Your Grafana Cloud Credentials

1. Log in to [Grafana Cloud](https://grafana.com)
2. Navigate to **Connections** → **OpenTelemetry (OTLP)**
3. Note the following values:
   - **Instance ID** (e.g., `1289964`)
   - **Password / API Token** (starts with `glc_...`)
   - **OTLP Endpoint** (e.g., `https://otlp-gateway-prod-gb-south-1.grafana.net/otlp`)

## Usage

### Preview Changes (Dry Run)

```bash
./configure-grafana-cloud.sh \
  --instance-id <YOUR_INSTANCE_ID> \
  --api-key '<YOUR_API_KEY>' \
  --endpoint '<YOUR_OTLP_ENDPOINT>'
```

This will:
- Generate the OTel collector configuration
- Show what would be applied
- Update the CloudFormation template file

### Apply Changes

```bash
./configure-grafana-cloud.sh \
  --instance-id <YOUR_INSTANCE_ID> \
  --api-key '<YOUR_API_KEY>' \
  --endpoint '<YOUR_OTLP_ENDPOINT>' \
  --cluster <ECS_CLUSTER_NAME> \
  --service <ECS_SERVICE_NAME> \
  --apply
```

This will:
- Update the SSM parameter with the new configuration
- Force a new ECS deployment to pick up the changes
- Update the CloudFormation template file

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--instance-id` | Yes | Your Grafana Cloud instance ID |
| `--api-key` | Yes | Your Grafana Cloud API key (glc_...) |
| `--endpoint` | Yes | OTLP endpoint URL |
| `--cluster` | No | ECS cluster name (required with `--apply` for auto-restart) |
| `--service` | No | ECS service name (required with `--apply` for auto-restart) |
| `--ssm-param` | No | SSM parameter name (default: `/aot/config`) |
| `--apply` | No | Apply changes to SSM and trigger ECS deployment |
| `--help` | No | Show help message |

## Examples

### Example 1: Preview Configuration

```bash
./configure-grafana-cloud.sh \
  --instance-id 1289964 \
  --api-key 'glc_eyJvIjoiMTQ0OTU4MyIsIm4iOi...' \
  --endpoint 'https://otlp-gateway-prod-gb-south-1.grafana.net/otlp'
```

### Example 2: Apply to Existing Deployment

```bash
./configure-grafana-cloud.sh \
  --instance-id 1289964 \
  --api-key 'glc_eyJvIjoiMTQ0OTU4MyIsIm4iOi...' \
  --endpoint 'https://otlp-gateway-prod-gb-south-1.grafana.net/otlp' \
  --cluster my-ecs-cluster \
  --service otel-service-my-stack \
  --apply
```

### Example 3: Custom SSM Parameter

```bash
./configure-grafana-cloud.sh \
  --instance-id 1289964 \
  --api-key 'glc_eyJvIjoiMTQ0OTU4MyIsIm4iOi...' \
  --endpoint 'https://otlp-gateway-prod-gb-south-1.grafana.net/otlp' \
  --ssm-param /my-app/otel-config \
  --apply
```

## What the Script Does

1. **Generates Auth Header**: Creates the `Basic base64(instanceId:apiKey)` authentication header required by Grafana Cloud

2. **Creates OTel Config**: Generates a complete OpenTelemetry collector configuration with:
   - OTLP receivers (gRPC and HTTP)
   - Metric filtering for ECS, HTTP, and JVM metrics
   - `otlphttp/grafana` exporter configured for Grafana Cloud

3. **Updates SSM Parameter** (with `--apply`): Stores the configuration in AWS SSM Parameter Store

4. **Triggers ECS Deployment** (with `--apply` + cluster/service): Forces ECS to start new tasks with the updated configuration

5. **Updates CloudFormation Template**: Modifies `templates/otel-service.yaml` with the new endpoint and auth values

## Alternative: SAM Deploy with Parameters

The script also outputs the parameters needed for `sam deploy`:

```bash
sam deploy --parameter-overrides \
  GrafanaOtlpEndpoint='https://otlp-gateway-prod-gb-south-1.grafana.net/otlp' \
  GrafanaAuthHeader='Basic MTI4OTk2NDpnbGNf...' \
  ConfigVersion='1234567890'
```

This is useful for CI/CD pipelines where you want to pass credentials at deploy time.

## Troubleshooting

### 401 Unauthorized Errors

If you see 401 errors in the OTel collector logs:
- Verify your Instance ID is correct
- Ensure the API key has write permissions for metrics and traces
- Check that the API key hasn't expired

### Tasks Not Restarting

ECS tasks only pick up SSM parameter changes on restart. Either:
- Use `--apply` with `--cluster` and `--service` flags
- Manually run: `aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment`

### Viewing Logs

Monitor the OTel collector logs:

```bash
aws logs tail /ecs/otel --follow
```

Check for successful exports or errors:

```bash
aws logs tail /ecs/otel --since 5m | grep -E "(error|401|Exporting)"
```
