1. Create the new Container

```
docker run -d \
 --name iaq-sensor-backend \
 -p 5433:5433 \
 -v "$(pwd)/data/postgres:/var/lib/postgresql/data" \
 -e POSTGRES_PASSWORD=password \
 timescale/timescaledb-ha:pg16
```

2. create tables

```
docker exec -i iaq-sensor-backend psql -U postgres < sql/migrations/001_init.sql
```
