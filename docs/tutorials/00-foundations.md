# 00 Foundations

## Objetivo y contexto
Definir base del proyecto: cuenta AWS, backend de Terraform state, convenciones de naming/tagging, estrategia de ambientes (`dev` y `prod`) y reglas de colaboracion.

## Paso a paso (ejecucion)
1. Confirmar identidad operativa con el perfil unico `data-science-user`.
2. Validar acceso AWS por perfil:
   - `aws sts get-caller-identity --profile data-science-user`
3. Definir convenciones globales:
   - naming de recursos,
   - tags obligatorios,
   - separacion `dev`/`prod`.
4. Definir estandar de trazabilidad de costos para Terraform (aplica a todos los modulos futuros):
   - usar `provider.aws.default_tags` con:
     - `project = "titanic-sagemaker"`,
     - `env = "<dev|prod>"`,
     - `owner = "<team-or-user>"`,
     - `managed_by = "terraform"`,
     - `cost_center = "<value>"`.
   - reforzar `tags = { ... }` en recursos/modulos que soporten tags por bloque.
   - validar en `terraform plan` que no haya recursos sin tags obligatorios.
5. Validar base Terraform del modulo actual:
   - `terraform fmt -check`
   - `terraform validate`
   - `terraform plan`
6. Aprobar arquitectura objetivo:
   - ModelBuild CI (`Processing -> Training -> Evaluation -> Register`),
   - ModelDeploy CD (`staging -> manual approval -> prod`).

## Decisiones tecnicas y alternativas descartadas
- IaC estandar: Terraform.
- CI/CD estandar: GitHub Actions.
- Ambientes: `dev` y `prod`.
- Cost tracking obligatorio desde foundations con `default_tags` + tags por recurso.
- Arquitectura objetivo: ModelBuild CI (preprocess/train/evaluate/register) + ModelDeploy CD (staging/manual approval/prod).
- Alternativas descartadas: despliegues manuales sin pipeline.

## IAM usado (roles/policies/permisos clave)
- Usuario operador DS con permisos minimos para ejecutar pipelines y leer observabilidad.
- Usuario IAM oficial: `data-science-user`.
- Access keys logicas del usuario: `data-science-user-primary` (activa) y `data-science-user-rotation` (reserva).
- Perfil AWS CLI oficial: `data-science-user`.
- Roles de ejecucion por servicio (SageMaker, Lambda, Step Functions, ECS).
- `iam:PassRole` restringido a roles esperados.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
- Plantilla minima para futuros providers Terraform:
  ```hcl
  provider "aws" {
    region = var.aws_region
    default_tags {
      tags = {
        project     = "titanic-sagemaker"
        env         = var.environment
        owner       = var.owner
        managed_by  = "terraform"
        cost_center = var.cost_center
      }
    }
  }
  ```
- `terraform fmt -check`
- `terraform validate`
- `terraform plan`
- Resultado esperado: plan limpio y recursos con tags obligatorios.

## Entregable minimo de esta fase
- Checklist de arquitectura aprobado con estos bloques:
  - SageMaker Pipeline con pasos de `Processing -> Training -> Evaluation -> Register`.
  - Model Registry obligatorio antes de cualquier deployment.
  - Pipeline de despliegue con endpoint `staging`, gate manual y despliegue a `prod`.

## Criterio de cierre
- Identidad y perfil AWS validados.
- Convenciones y tags documentados.
- `terraform plan` revisado sin sorpresas.
- Arquitectura objetivo aprobada y trazada a fases `01..07`.

## Evidencia
Agregar aqui salidas de plan, decisiones de backend state y convenciones aprobadas.

## Riesgos/pendientes
- Definir limites iniciales de costos.
- Validar permisos exactos para cada modulo.

## Proximo paso
Avanzar a ingestion y gobierno de datos en `docs/tutorials/01-data-ingestion.md`.
