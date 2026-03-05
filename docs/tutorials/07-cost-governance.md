# 07 Cost and Governance

## Objetivo y contexto
Controlar costo y riesgo operativo del proyecto con reglas verificables por entorno.
Al cerrar esta fase, existen presupuestos con alertas, tags de costo activos,
control de recursos huerfanos y politica de apagado en no-produccion.

Estado actual: **backlog ejecutable** -- no cerrado end-to-end, pero con todos los
comandos, Terraform y scripts concretos para implementar cuando se alcance esta fase.

## Resultado minimo esperado
1. Presupuestos `dev` y `prod` con alertas 50/80/100%.
2. Cost allocation tags activos en Billing.
3. Checker de recursos activos integrado en operacion recurrente.
4. Politica de apagado de endpoints no-prod definida y verificada.
5. Evidencia mensual registrada.

## Fuentes oficiales usadas en esta fase
1. `https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html`
2. `https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_Operations_AWS_Budgets.html`
3. `https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html`
4. `https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html`
5. `https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html`

## Prerequisitos concretos
1. Fases 00-04 completadas (recursos activos para monitorear).
2. Acceso a AWS Budgets y Cost Explorer.
3. Perfil AWS CLI: `data-science-user`.
4. SNS topic para alertas (creado en fase 06 o nuevo).

## Contrato de costo y gobierno

### Etiquetas obligatorias
| Tag | Valor | Proposito |
|---|---|---|
| `project` | `titanic-sagemaker` | Agrupacion por proyecto |
| `env` | `dev` / `prod` | Separacion por ambiente |
| `owner` | `data-science-user` | Responsable |
| `managed_by` | `terraform` | Trazabilidad IaC |
| `cost_center` | `data-science` | Centro de costo |

### Umbrales de alerta
| Nivel | Porcentaje | Accion |
|---|---|---|
| Warning | 50% | Revisar gasto actual vs previsto |
| High | 80% | Evaluar apagado de recursos no criticos |
| Critical | 100% | Accion inmediata: parar no-prod, revisar prod |

## Entregable 1 -- Presupuestos operativos

### 1.1 Crear budgets via CLI

```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE")
export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:titanic-alerts"
export ALERT_EMAIL="<owner-email>"

# Budget para dev (ejemplo: $50/mes)
aws budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget '{
    "BudgetName": "titanic-dev-monthly-cost",
    "BudgetLimit": {"Amount": "50", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
      "TagKeyValue": ["user:project$titanic-sagemaker", "user:env$dev"]
    }
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 50,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "'"$ALERT_EMAIL"'"}
      ]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "'"$ALERT_EMAIL"'"}
      ]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "'"$ALERT_EMAIL"'"},
        {"SubscriptionType": "SNS", "Address": "'"$SNS_TOPIC_ARN"'"}
      ]
    }
  ]' \
  --profile "$AWS_PROFILE" --region "$AWS_REGION"

# Budget para prod (ejemplo: $100/mes)
aws budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget '{
    "BudgetName": "titanic-prod-monthly-cost",
    "BudgetLimit": {"Amount": "100", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
      "TagKeyValue": ["user:project$titanic-sagemaker", "user:env$prod"]
    }
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 50,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "'"$ALERT_EMAIL"'"}
      ]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "'"$ALERT_EMAIL"'"}
      ]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "'"$ALERT_EMAIL"'"},
        {"SubscriptionType": "SNS", "Address": "'"$SNS_TOPIC_ARN"'"}
      ]
    }
  ]' \
  --profile "$AWS_PROFILE" --region "$AWS_REGION"
```

### 1.2 Terraform alternativo para budgets

```hcl
# terraform/07_cost_governance/budgets.tf

resource "aws_budgets_budget" "dev" {
  name         = "titanic-dev-monthly-cost"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:project$titanic-sagemaker", "user:env$dev"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [var.sns_topic_arn]
  }
}

resource "aws_budgets_budget" "prod" {
  name         = "titanic-prod-monthly-cost"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:project$titanic-sagemaker", "user:env$prod"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [var.sns_topic_arn]
  }
}
```

### 1.3 Verificar budgets

```bash
aws budgets describe-budgets \
  --account-id "$ACCOUNT_ID" \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --query 'Budgets[?starts_with(BudgetName, `titanic-`)].{Name:BudgetName, Limit:BudgetLimit.Amount, Spent:CalculatedSpend.ActualSpend.Amount}' \
  --output table
```

## Entregable 2 -- Cost allocation tags

### 2.1 Activar tags de costo

Los tags `project`, `env`, `owner` deben activarse como cost allocation tags en la
consola de Billing:

1. Ir a **Billing > Cost allocation tags**.
2. Buscar tags `project`, `env`, `owner`, `cost_center`.
3. Activar cada tag como **User-defined cost allocation tag**.

Verificacion por CLI (si los tags ya estan activos):

```bash
# Verificar que Cost Explorer puede agrupar por tag
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=project \
  --profile "$AWS_PROFILE" --region us-east-1
```

Nota: Cost Explorer API opera siempre en `us-east-1`.

### 2.2 Verificar tagging de recursos existentes

```bash
# Listar recursos sin tags obligatorios
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=project,Values=titanic-sagemaker \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --query 'ResourceTagMappingList[].{ARN:ResourceARN, Tags:Tags[].{Key:Key,Value:Value}}' \
  --output json | head -50
```

## Entregable 3 -- Control de recursos activos

### 3.1 Checker operativo recurrente

```bash
# Revision global de recursos del proyecto
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all

# Gate para CI/smoke
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all --fail-if-active
```

### 3.2 Revision puntual por fase

```bash
# Solo fase 04 (endpoints)
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase 04

# Solo fase 07 (gobierno)
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase 07
```

### 3.3 Costos de SageMaker por servicio

Principales fuentes de costo del proyecto:

| Recurso | Costo principal | Control |
|---|---|---|
| SageMaker Endpoints | Instancia por hora (ml.m5.large ~$0.115/h) | Apagar staging en no-horario |
| Training Jobs | Instancia por segundo de ejecucion | Jobs terminan automaticamente |
| Processing Jobs | Instancia por segundo de ejecucion | Jobs terminan automaticamente |
| S3 Storage | Por GB almacenado + requests | Lifecycle policies para artefactos viejos |
| CloudWatch | Logs + metricas custom | Retention policies |
| Data Capture | S3 storage de capturas | Retention policies |

## Entregable 4 -- Politica de apagado no-prod

### 4.1 EventBridge Scheduler para apagar staging

```bash
# Crear schedule para eliminar endpoint staging a las 20:00 UTC (dia laborable)
aws scheduler create-schedule \
  --name "titanic-staging-shutdown" \
  --schedule-expression "cron(0 20 ? * MON-FRI *)" \
  --flexible-time-window '{"Mode": "OFF"}' \
  --target '{
    "Arn": "arn:aws:sagemaker:'$AWS_REGION':'$ACCOUNT_ID':endpoint/titanic-survival-staging",
    "RoleArn": "<scheduler-role-arn>",
    "SageMakerPipelineParameters": {}
  }' \
  --profile "$AWS_PROFILE" --region "$AWS_REGION"
```

Alternativa via Lambda:

```python
# Lambda function para cleanup de staging
import boto3

def handler(event, context):
    sm = boto3.client("sagemaker")
    endpoint_name = "titanic-survival-staging"

    try:
        sm.describe_endpoint(EndpointName=endpoint_name)
        sm.delete_endpoint(EndpointName=endpoint_name)
        return {"status": "deleted", "endpoint": endpoint_name}
    except sm.exceptions.ClientError:
        return {"status": "not_found", "endpoint": endpoint_name}
```

### 4.2 Terraform para Scheduler

```hcl
# terraform/07_cost_governance/scheduler.tf

resource "aws_scheduler_schedule" "staging_shutdown" {
  name       = "titanic-staging-shutdown"
  group_name = "default"

  schedule_expression = "cron(0 20 ? * MON-FRI *)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.staging_cleanup.arn
    role_arn = aws_iam_role.scheduler.arn
  }

  tags = {
    project = "titanic-sagemaker"
    env     = var.environment
  }
}
```

## Checklist mensual de revision de costos

Ejecutar al cierre de cada mes y registrar en `docs/iterations/`:

```bash
# 1. Estado de presupuestos
aws budgets describe-budgets \
  --account-id "$ACCOUNT_ID" \
  --profile "$AWS_PROFILE" --region "$AWS_REGION"

# 2. Recursos activos
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all

# 3. Costo del ultimo mes por tag project
aws ce get-cost-and-usage \
  --time-period Start=$(date -d 'first day of last month' +%Y-%m-%d),End=$(date -d 'first day of this month' +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=project \
  --profile "$AWS_PROFILE" --region us-east-1

# 4. Costo por servicio
aws ce get-cost-and-usage \
  --time-period Start=$(date -d 'first day of last month' +%Y-%m-%d),End=$(date -d 'first day of this month' +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Tags": {"Key": "project", "Values": ["titanic-sagemaker"]}}' \
  --profile "$AWS_PROFILE" --region us-east-1
```

## Decisiones tecnicas y alternativas descartadas
1. Presupuestos por entorno con naming fijo para trazabilidad.
2. Alertas escalonadas 50/80/100 para respuesta temprana.
3. Chequeo de recursos activos como control operativo recurrente.
4. EventBridge Scheduler para apagado automatico de no-prod.
5. Descartado: control de costo reactivo solo al cierre de mes.
6. Descartado: presupuesto unico sin separacion dev/prod.

## IAM usado (roles/policies/permisos clave)
1. Identidad base: `data-science-user`.
2. Permisos de lectura de Budgets/Cost Explorer para operador DS.
3. Permisos acotados para scheduler y acciones stop/start.
4. Mantener least-privilege y evitar wildcard sin justificacion.

## Criterio de cierre
1. Presupuestos `titanic-dev-monthly-cost` y `titanic-prod-monthly-cost` activos.
2. Alertas 50/80/100 con destinatarios definidos.
3. Checker de recursos activos integrado en operacion recurrente.
4. Politica de apagado no-prod definida y verificada.
5. Evidencia mensual registrada en `docs/iterations/`.

## Riesgos/pendientes
1. Recursos con tags incompletos que no entran al analisis de costo.
2. Endpoints sin schedule de ahorro en no-produccion.
3. Alertas ignoradas por falta de ownership operativo.
4. Cost Explorer data disponible con ~24h de delay.

## Proximo paso
Registrar cada ciclo mensual de costo en `docs/iterations/` y mantener sincronia
con decisiones de fases 04-06.
