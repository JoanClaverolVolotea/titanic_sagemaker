# Tutorial roadmap

Tutoriales por fase del proyecto Titanic SageMaker:

1. `docs/tutorials/00-foundations.md`
2. `docs/tutorials/01-data-ingestion.md`
3. `docs/tutorials/02-training-validation.md`
4. `docs/tutorials/03-sagemaker-pipeline.md`
5. `docs/tutorials/04-serving-ecs-sagemaker.md`
6. `docs/tutorials/05-cicd-github-actions.md`
7. `docs/tutorials/06-observability-operations.md`
8. `docs/tutorials/07-cost-governance.md`

Iteraciones historicas:
- `docs/iterations/`

Convencion de credenciales para todos los tutoriales:
- IAM user: `data-science-user`
- Access keys logicas: `data-science-user-primary` y `data-science-user-rotation`
- Perfiles AWS CLI: `data-science-user`, `data-science-user-dev`, `data-science-user-prod`

Regla global de ejecucion AWS:
- Toda operacion AWS del proyecto debe ejecutarse desde `data-science-user` como identidad principal.
- Para trabajo por entorno usar `data-science-user-dev` (dev) y `data-science-user-prod` (prod).
