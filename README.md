# SpringBoot integration with OpenTelemetry on Amazon ECS → Grafana Cloud

This project contains source code that demos the following:

- How to integrate [OpenTelemetry](https://opentelemetry.io/) with Java [SpringBoot](https://spring.io/projects/spring-boot) based microservices.
- Using [AWS Distro for OpenTelemetry](https://aws-otel.github.io/) with the [Amazon ECS service pattern](https://aws.amazon.com/blogs/opensource/deployment-patterns-for-the-aws-distro-for-opentelemetry-collector-with-amazon-elastic-container-service/). 
- How to send OpenTelemetry traces and metrics from ECS to [Grafana Cloud](https://grafana.com/products/cloud/) (Tempo, Prometheus, Loki).
- Create nested stacks using [AWS SAM Nested applications](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-template-nested-applications.html). 

## Solution Overview

```
                ┌──────────────────────────────┐
                │        Internet / You        │
                └──────────────┬───────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   ALB (service-a)   │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │   ECS Task (A)      │
                    │  Spring Boot App    │
                    │ + OTel Java Agent   │
                    └──────────┬──────────┘
                               │ OTLP
                               ▼
                    ┌──────────────────────┐
                    │   OTel Collector     │
                    │ (ECS service)        │
                    └──────────┬───────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
 ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
 │   Grafana     │     │   Grafana     │     │   Grafana     │
 │   Tempo       │     │   Prometheus  │     │   Loki        │
 │   (traces)    │     │   (metrics)   │     │   (logs)      │
 └───────────────┘     └───────────────┘     └───────────────┘
```

## Integrating OpenTelemetry with SpringBoot Services

This project shows how to add the [Java OpenTelemetry agent](https://github.com/open-telemetry/opentelemetry-java-instrumentation) with popular Spring Boot based microservices. Refer to the `Dockerfile` in the project to see how to add the Java OpenTelemetry agent without making code changes to the application.

## Using Amazon ECS Service Pattern

Several patterns can be used for deploying the OTel collector for observability:

- **The sidecar pattern**: A common practice where each application task has its own collector sidecar. Simple to configure but can become expensive at scale.

- **Amazon ECS service pattern** (used in this project): Similar to the [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) pattern in Kubernetes. A dedicated ECS service runs the OTel collector, and application services discover it via AWS Cloud Map. This reduces compute costs since collectors are no longer 1:1 with application containers.

For more information, refer to this AWS [Blog](https://aws.amazon.com/blogs/opensource/deployment-patterns-for-the-aws-distro-for-opentelemetry-collector-with-amazon-elastic-container-service/).

## Sending Telemetry to Grafana Cloud

The OTel collector is configured to export telemetry to Grafana Cloud via OTLP:

- **Traces** → Grafana Tempo
- **Metrics** → Grafana Cloud Prometheus  
- **Logs** → Grafana Loki (via application logging)

The collector configuration is stored in AWS SSM Parameter Store and uses the `otlphttp` exporter to send data to Grafana Cloud's OTLP gateway.

## Using AWS SAM CLI Nested Applications

Instead of using [CloudFormation nested stacks](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html), this project uses [AWS SAM Nested applications](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-template-nested-applications.html). CloudFormation nested stacks require uploading templates to S3 for every change, whereas AWS SAM CLI manages this automatically.

## Deploy the Sample Application

> **WARNING**: This project creates VPC, ALB, ECS Cluster & Services, CloudMap, and S3 buckets that can incur cost. Clean up resources when done.

### Prerequisites

* AWS SAM CLI - [Install the AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)
* Docker - [Install Docker community edition](https://hub.docker.com/search/?type=edition&offering=community)
* Grafana Cloud account with OTLP credentials

### Step 1: Get Grafana Cloud Credentials

1. Log in to [Grafana Cloud](https://grafana.com)
2. Navigate to **Connections** → **OpenTelemetry (OTLP)**
3. Note your:
   - **Instance ID** (e.g., `1289964`)
   - **API Token** (starts with `glc_...`)
   - **OTLP Endpoint** (e.g., `https://otlp-gateway-prod-gb-south-1.grafana.net/otlp`)

### Step 2: Build and Deploy

```bash
# Build the application
sam build

# Generate the auth header
AUTH_HEADER="Basic $(echo -n '<INSTANCE_ID>:<API_KEY>' | base64)"

# Deploy with Grafana Cloud parameters
sam deploy --guided --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GrafanaOtlpEndpoint='<YOUR_OTLP_ENDPOINT>' \
    GrafanaAuthHeader="${AUTH_HEADER}" \
    ConfigVersion="$(date +%s)"
```

### Alternative: Use the Configuration Script

A helper script is provided to simplify Grafana Cloud configuration:

```bash
# Preview the configuration
./scripts/configure-grafana-cloud.sh \
  --instance-id <YOUR_INSTANCE_ID> \
  --api-key '<YOUR_API_KEY>' \
  --endpoint '<YOUR_OTLP_ENDPOINT>'

# Apply changes and restart ECS tasks
./scripts/configure-grafana-cloud.sh \
  --instance-id <YOUR_INSTANCE_ID> \
  --api-key '<YOUR_API_KEY>' \
  --endpoint '<YOUR_OTLP_ENDPOINT>' \
  --cluster <ECS_CLUSTER_NAME> \
  --service <OTEL_SERVICE_NAME> \
  --apply
```

See [scripts/README.md](scripts/README.md) for detailed usage instructions.

## Viewing Your Data in Grafana Cloud

Once deployed, your telemetry will be available in Grafana Cloud:

- **Traces**: Navigate to **Explore** → Select **Tempo** data source
- **Metrics**: Navigate to **Explore** → Select **Prometheus** data source, or create dashboards
- **Service Map**: Use Tempo's service graph feature to visualize service dependencies

## Cleanup

To delete all resources:

```bash
sam delete
```

## Resources

- [AWS SAM Developer Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Grafana Cloud OTLP Documentation](https://grafana.com/docs/grafana-cloud/send-data/otlp/)
- [AWS Distro for OpenTelemetry](https://aws-otel.github.io/)

## Contribution

See [CONTRIBUTING](CONTRIBUTING.md) for more information.

## License

See the [LICENSE](LICENSE) file.
