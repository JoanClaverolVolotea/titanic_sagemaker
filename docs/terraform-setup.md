# Terraform setup

Este documento cubre el setup base para trabajar con Terraform en este proyecto.

## Prerrequisitos

- Terraform instalado (version alineada con el repositorio).
- AWS CLI configurado con credenciales validas.
- Acceso al backend de Terraform (S3 + DynamoDB para lock).
- Permisos IAM para crear/leer los recursos usados por el proyecto.

## Verificaciones rapidas

```bash
terraform version
aws sts get-caller-identity
aws configure list
```

## Backend recomendado (S3 + DynamoDB)

Este proyecto usa estado remoto en S3 y bloqueo en DynamoDB (estandar en AWS).

Requisitos del backend:

- Bucket S3 exclusivo para `tfstate`, con versioning y cifrado.
- Tabla DynamoDB para lock con clave primaria `LockID` (string).

Ejemplo de configuracion del backend (en `versions.tf` o `backend.tf`):

```hcl
terraform {
  backend "s3" {
    bucket         = "titanic-terraform-state-dev"
    key            = "titanic/dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "titanic-terraform-locks-dev"
    encrypt        = true
  }
}
```

Nota: el backend no acepta variables. Para separar entornos usa `-backend-config`
con archivos `backend/*.hcl`.

Ejemplo de uso:

```bash
terraform init -backend-config=backend/dev.hcl
```

## Inicializacion

1. Configura variables/parametros requeridos (por ejemplo, `terraform.tfvars` o variables de entorno).
2. Ejecuta:

```bash
terraform init
terraform validate
```

Si cambiaste el backend, usa:

```bash
terraform init -reconfigure
```

## Convenciones antes de aplicar

- Revisa nombrado de recursos y tags/labels obligatorios.
- Verifica que el backend de estado apunte al entorno correcto.

## Plan y apply

```bash
terraform plan
terraform apply
```

## Notas

- Documenta decisiones tecnicas importantes en este archivo o en el README del repo.
