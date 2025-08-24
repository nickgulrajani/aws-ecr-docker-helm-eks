#!/usr/bin/env bash
set -euo pipefail

OVERWRITE="${1:-}"
can_write() {
  local p="$1"
  if [[ -f "$p" && "$OVERWRITE" != "--force" ]]; then
    echo "SKIP: $p exists (use --force to overwrite)"
    return 1
  fi
  mkdir -p "$(dirname "$p")"
  return 0
}

w() { # write file from heredoc if allowed
  local path="$1"; shift
  if can_write "$path"; then
    cat > "$path" <<'EOF'
'"$@"'
EOF
    echo "WROTE: $path"
  fi
}

# ----- Terraform -----
w terraform/versions.tf \
'terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}
'

w terraform/providers.tf \
'provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = "dry-run-demo"
      CostCenter  = "simulation-only"
    }
  }
}
'

w terraform/variables.tf \
'variable "project" {
  type        = string
  default     = "microservices-standard"
  description = "Project tag"
}

variable "environment" {
  type        = string
  default     = "dryrun"
  description = "Environment"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Region (no API calls in dry run)"
}

variable "name_prefix" {
  type        = string
  default     = "ms"
  description = "Resource name prefix"
}

variable "ecr_repos" {
  type        = list(string)
  default     = ["orders","billing"]
  description = "Service repositories"
}

variable "enable_eks" {
  type        = bool
  default     = false
  description = "EKS disabled for dry run"
}
'

w terraform/main.tf \
'############################################
# Standardized ECR registries (plan-only)
############################################
locals {
  repo_prefix = "${var.name_prefix}-${var.environment}"
}

resource "aws_ecr_repository" "svc" {
  for_each                 = toset(var.ecr_repos)
  name                     = "${local.repo_prefix}-${each.key}"
  image_tag_mutability     = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete             = true
  tags = { Name = "${local.repo_prefix}-${each.key}" }
}

resource "aws_ecr_lifecycle_policy" "svc" {
  for_each   = aws_ecr_repository.svc
  repository = each.value.name
  policy     = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "microservices_summary" {
  value = {
    ecr_repos = [for r in aws_ecr_repository.svc : r.name]
  }
}
'

w tfvars/minimal.tfvars \
'project     = "microservices-standard"
environment = "dryrun"
aws_region  = "us-east-1"
name_prefix = "ms"
ecr_repos   = ["orders","billing"]
enable_eks  = false
'

# ----- App (Docker + Node) -----
w app/Dockerfile \
'# --- Builder ---
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src

# --- Runtime ---
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=8080
RUN addgroup -S app && adduser -S -G app app
COPY --from=build /app /app
USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
CMD ["node", "src/server.js"]
'

w app/package.json \
'{
  "name": "sample-microservice",
  "version": "1.0.0",
  "private": true,
  "license": "MIT",
  "type": "module",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.19.2"
  }
}
'

w app/src/server.js \
'import express from "express";
const app = express();
app.get("/healthz", (_req, res) => res.status(200).json({ ok: true }));
app.get("/", (_req, res) => res.send("hello from standardized microservice"));
const port = process.env.PORT || 8080;
app.listen(port, () => console.log(`listening on ${port}`));
'

# ----- Helm chart -----
w helm/app/Chart.yaml \
'apiVersion: v2
name: microservice
description: Standardized microservice chart (dry-run render only)
type: application
version: 0.1.0
appVersion: "1.0.0"
'

w helm/app/values.yaml \
'replicaCount: 2

image:
  repository: local/app
  tag: dev
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 250m
    memory: 256Mi

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true

livenessProbe:
  path: /healthz
  initialDelaySeconds: 10
  periodSeconds: 30

readinessProbe:
  path: /healthz
  initialDelaySeconds: 5
  periodSeconds: 10
'

w helm/app/templates/deployment.yaml \
'apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "microservice.fullname" . }}
  labels:
    app.kubernetes.io/name: {{ include "microservice.name" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ include "microservice.name" . }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "microservice.name" . }}
    spec:
      securityContext:
        runAsNonRoot: {{ .Values.podSecurityContext.runAsNonRoot }}
        runAsUser: {{ .Values.podSecurityContext.runAsUser }}
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 8080
              name: http
          livenessProbe:
            httpGet:
              path: {{ .Values.livenessProbe.path }}
              port: 8080
            initialDelaySeconds: {{ .Values.livenessProbe.initialDelaySeconds }}
            periodSeconds: {{ .Values.livenessProbe.periodSeconds }}
          readinessProbe:
            httpGet:
              path: {{ .Values.readinessProbe.path }}
              port: 8080
            initialDelaySeconds: {{ .Values.readinessProbe.initialDelaySeconds }}
            periodSeconds: {{ .Values.readinessProbe.periodSeconds }}
          securityContext:
            allowPrivilegeEscalation: {{ .Values.containerSecurityContext.allowPrivilegeEscalation }}
            readOnlyRootFilesystem: {{ .Values.containerSecurityContext.readOnlyRootFilesystem }}
          resources:
{{- toYaml .Values.resources | nindent 12 }}
'

w helm/app/templates/service.yaml \
'apiVersion: v1
kind: Service
metadata:
  name: {{ include "microservice.fullname" . }}
spec:
  selector:
    app.kubernetes.io/name: {{ include "microservice.name" . }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: 8080
  type: {{ .Values.service.type }}
'

w helm/app/templates/_helpers.tpl \
'{{- define "microservice.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "microservice.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "microservice.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
'

# ----- GitHub Actions workflow -----
w .github/workflows/microservices-dryrun.yml \
'name: microservices-dryrun

on:
  push:
    branches: [ "main" ]
  pull_request:

jobs:
  dryrun:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build Docker image (no push)
        working-directory: app
        run: |
          set -euo pipefail
          docker build -t app:dryrun .
          docker save app:dryrun -o ../app-image.tar
          echo "OK: built local image app:dryrun and saved to app-image.tar"

      - name: Trivy scan (image) non-blocking
        uses: aquasecurity/trivy-action@0.20.0
        with:
          image-ref: app:dryrun
          format: "table"
          exit-code: "0"
          vuln-type: "os,library"
          ignore-unfixed: true

      - name: Validate Dockerfile best practices
        run: |
          set -euo pipefail
          grep -q "^USER " app/Dockerfile || (echo "::error::Dockerfile missing USER" && exit 1)
          ! grep -E "^USER\\s+root\\b" app/Dockerfile || (echo "::error::Dockerfile runs as root" && exit 1)
          grep -q "^HEALTHCHECK " app/Dockerfile || (echo "::error::Dockerfile missing HEALTHCHECK" && exit 1)
          echo "OK: Dockerfile best practices enforced"

      - name: Install Helm
        uses: azure/setup-helm@v4

      - name: Helm lint and render (no cluster)
        run: |
          set -euo pipefail
          helm lint helm/app
          helm template ms helm/app -f helm/app/values.yaml > helm/rendered.yaml
          head -n 40 helm/rendered.yaml

      - name: Gate - probes must exist in rendered manifests
        run: |
          set -euo pipefail
          grep -q "livenessProbe" helm/rendered.yaml || (echo "::error::livenessProbe missing" && exit 1)
          grep -q "readinessProbe" helm/rendered.yaml || (echo "::error::readinessProbe missing" && exit 1)
          echo "OK: Probes present in Helm output"

      - name: Ensure jq and Terraform
        run: |
          sudo apt-get update -y
          sudo apt-get install -y jq

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.6

      - name: Terraform fmt/validate
        run: |
          terraform -chdir=terraform init -backend=false
          terraform -chdir=terraform fmt -recursive
          terraform -chdir=terraform validate

      - name: Terraform plan (no apply)
        env:
          AWS_ACCESS_KEY_ID: dummy
          AWS_SECRET_ACCESS_KEY: dummy
          AWS_REGION: us-east-1
        run: |
          set -euo pipefail
          terraform -chdir=terraform init -backend=false
          terraform -chdir=terraform plan -refresh=false \
            -var-file=../tfvars/minimal.tfvars \
            -out=tfplan.binary
          terraform -chdir=terraform show -json tfplan.binary > tfplan.json
          terraform -chdir=terraform show tfplan.binary | sed -n "1,120p"

      - name: Gate - require tags on created AWS resources
        run: |
          set -euo pipefail
          REQUIRED='\''["Project","Environment","Owner","CostCenter"]'\''
          MISSING=$(
            jq -r --argjson req "$REQUIRED" '\''
              def ensure_obj(x): if (x|type)=="object" then x else {} end;
              [
                .resource_changes[]?
                | select(.change.actions | index("create"))
                | . as $rc
                | (ensure_obj($rc.change.after) | (.tags_all // .tags // {})) as $tags
                | {addr: $rc.address, type: $rc.type,
                   missing: [$req[] | select( ($tags[.] // null) == null )]}
                | select(.missing | length > 0)
                | "\(.addr) (\(.type)) missing: \(.missing|join(", "))"
              ] | .[]
            '\'' tfplan.json
          )
          if [ -n "$MISSING" ]; then
            echo "::error::Missing required tags:"
            echo "$MISSING"
            exit 1
          else
            echo "OK: required tags present"
          fi

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: ms-dryrun-artifacts
          path: |
            app-image.tar
            helm/rendered.yaml
            terraform/tfplan.binary
            tfplan.json
          if-no-files-found: error
'

# ----- .gitignore (append if missing) -----
if [[ ! -f ".gitignore" || "$OVERWRITE" == "--force" ]]; then
  cat >> .gitignore <<'EOF'
# Local artifacts
app-image.tar
.tfplan
*.tfstate*
.terraform/
helm/rendered.yaml
EOF
  echo "UPDATED: .gitignore"
fi

echo
echo "✅ Setup complete."
echo "Next:"
echo "  1) git add -A && git commit -m 'Scenario 4 microservices dry-run scaffolding'"
echo "  2) git push origin main  # triggers the workflow"
echo "  3) (optional local test)"
echo "     terraform -chdir=terraform init -backend=false"
echo "     terraform -chdir=terraform fmt -recursive && terraform -chdir=terraform validate"
echo "     terraform -chdir=terraform plan -refresh=false -var-file=../tfvars/minimal.tfvars"

