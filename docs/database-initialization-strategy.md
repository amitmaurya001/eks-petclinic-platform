# Database Initialization Strategy

**Date:** June 27, 2026  
**Purpose:** Document the approach for initializing the shared `petclinic` MySQL database schema for the three database-backed microservices (customers, visits, vets).

## Overview

All three domain services share a single `petclinic` MySQL database on the same RDS instance. This is confirmed by cross-service foreign key constraints: `visits.pet_id` references `pets.id` (from customers service). 

## Database Schema

### Tables (7 total across 3 services)

**Customers Service** — 3 tables:
- `types` — `id` (PK, AUTO_INCREMENT), `name`
- `owners` — `id` (PK), `firstName`, `lastName`, `address`, `city`, `telephone`
- `pets` — `id` (PK), `name`, `birth_date`, `type_id`, `owner_id`

**Vets Service** — 3 tables:
- `vets` — `id` (PK, AUTO_INCREMENT), `firstName`, `lastName`
- `specialties` — `id` (PK), `name`
- `vet_specialties` — `vet_id`, `specialty_id`

**Visits Service** — 1 table:
- `visits` — `id` (PK, AUTO_INCREMENT), `pet_id`, `visit_date`, `description`

## Critical Dependency Chain

The `visits` table has `FOREIGN KEY (pet_id) REFERENCES pets(id)`, which is created by the customers service. Therefore, the initialization order must be:

1. **Customers Service** — creates `types`, `owners`, `pets` tables
2. **Vets Service** — creates `vets`, `specialties`, `vet_specialties` tables (independent)
3. **Visits Service** — creates `visits` table (depends on `pets` from step 1)

## Initialization Strategy

We use **Spring Boot auto-initialization** with schema.sql scripts:

### Approach
Each service contains SQL scripts in `src/main/resources/db/mysql/`:
- `customers-service/src/main/resources/db/mysql/schema.sql` — creates `types`, `owners`, `pets`
- `vets-service/src/main/resources/db/mysql/schema.sql` — creates `vets`, `specialties`, `vet_specialties`
- `visits-service/src/main/resources/db/mysql/schema.sql` — creates `visits`

### Spring Boot Configuration
```yaml
# application.yml for MySQL-backed services
spring:
  sql:
    init:
      mode: always  # Always initialize schema on startup
      schema-locations: classpath:db/mysql/schema.sql
      platform: mysql
```

### Startup Order Enforcement
1. **Deployment order in Kubernetes:** Customers service → Vets service → Visits service
2. **Readiness probes:** Each service waits for RDS to be available
3. **No init containers needed** for schema initialization — Spring Boot handles it automatically

## Connection String Format

```
jdbc:mysql://{rds-endpoint}:3306/petclinic
```

Example for dev environment:  
`jdbc:mysql://petclinic-dev-mysql.abc123.us-east-1.rds.amazonaws.com:3306/petclinic`

## Kubernetes ConfigMap Configuration

Each database-backed service's ConfigMap includes:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {service-name}-config
data:
  SPRING_DATASOURCE_URL: jdbc:mysql://${RDS_ENDPOINT}:3306/petclinic
```

Where `RDS_ENDPOINT` is populated from Terraform outputs via the Helm values.

## Secret Management

Database credentials are managed via:
1. **AWS Secrets Manager:** Stores `username` and `password` as JSON at `petclinic/{env}/rds-credentials`
2. **External Secrets Operator:** Syncs credentials to Kubernetes secrets
3. **Environment variables in deployments:**  
   `SPRING_DATASOURCE_USERNAME` from secret `username` field  
   `SPRING_DATASOURCE_PASSWORD` from secret `password` field

## Verification Steps

After deployment:

1. **Database connectivity:**
   ```bash
   kubectl exec -it deployment/customers-service -n petclinic-{env} -- \
     mysql -h ${RDS_ENDPOINT} -u petclinic -p -e "SHOW DATABASES;"
   ```

2. **Schema verification:**
   ```bash
   kubectl exec -it deployment/customers-service -n petclinic-{env} -- \
     mysql -h ${RDS_ENDPOINT} -u petclinic -p petclinic -e "SHOW TABLES;"
   ```

3. **Foreign key verification:**
   ```bash
   kubectl exec -it deployment/visits-service -n petclinic-{env} -- \
     mysql -h ${RDS_ENDPOINT} -u petclinic -p petclinic -e \
     "SELECT TABLE_NAME, CONSTRAINT_NAME, REFERENCED_TABLE_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE REFERENCED_TABLE_NAME IS NOT NULL;"
   ```

## Rollback Strategy

If schema initialization fails:
1. **Stop all services:** Delete deployments for customers, vets, visits
2. **Drop database:** Connect to RDS and drop `petclinic` database
3. **Restart in order:** Deploy customers → vets → visits

This approach is safe because the `skip_final_snapshot` is set to `true` for dev (but `false` for prod).

## Alternative Approaches Considered

1. **Manual SQL script execution:** Too complex, requires kubectl access
2. **Init containers with SQL scripts:** Redundant with Spring Boot auto-init
3. **Database migration tool (Flyway/Liquibase):** Overkill for simple schema
4. **Shared schema.sql across services:** Not possible due to separate service repos

**Selected approach:** Spring Boot auto-initialization with deployment order enforcement provides the best balance of simplicity and reliability for this learning project.