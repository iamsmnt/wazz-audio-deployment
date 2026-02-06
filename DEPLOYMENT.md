# Wazz Audio - Deployment Guide

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Frontend     │     │     Backend     │     │     Worker      │
│   (Next.js)     │────▶│    (FastAPI)    │────▶│    (Celery)     │
│    Port 3000    │     │    Port 8000    │     │                 │
└─────────────────┘     └────────┬────────┘     └────────┬────────┘
                                 │                       │
                    ┌────────────┴───────────────────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
┌────────▼────────┐   ┌────────▼────────┐   ┌─────────────────┐
│   PostgreSQL    │   │    RabbitMQ     │   │   S3/MinIO      │
│   Port 5432     │   │   Port 5672     │   │   (Optional)    │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

---

## Prerequisites

- Docker Engine 20.10+
- Docker Compose v2.0+
- Minimum 4GB RAM
- 20GB disk space

---

## Step 1: Navigate to Project Directory

```bash
cd /Users/somnathmahato/wazz-audio
```

---

## Step 2: Create Environment File

Create `.env` file in project root:

```bash
cat > .env << 'EOF'
# Application
DEBUG=false
ENVIRONMENT=production
SECRET_KEY=your-secure-secret-key-min-32-chars

# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=whazz_audio

# RabbitMQ
RABBITMQ_USER=guest
RABBITMQ_PASS=guest

# Frontend URLs
FRONTEND_URL=http://localhost:3000
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXT_PUBLIC_APP_NAME=WazzAudio
NEXT_PUBLIC_APP_URL=http://localhost:3000

# Audio Processing
CLEARVOICE_MODEL_NAME=MossFormer2_SE_48K
MAX_FILE_SIZE_MB=100
FILE_EXPIRY_HOURS=24

# Storage (set USE_LOCAL_STORAGE=false for S3)
USE_LOCAL_STORAGE=true
EOF
```

---

## Step 3: Create Docker Compose File

Create `docker-compose.yml` in project root:

```bash
cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  db:
    image: postgres:15-alpine
    container_name: wazz-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-whazz_audio}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - wazz-network

  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: wazz-rabbitmq
    restart: unless-stopped
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER:-guest}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASS:-guest}
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "check_running"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - wazz-network

  backend:
    build:
      context: .
      dockerfile: wazz-audio-backend/Dockerfile
    container_name: wazz-backend
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@db:5432/${POSTGRES_DB:-whazz_audio}
      - CELERY_BROKER_URL=amqp://${RABBITMQ_USER:-guest}:${RABBITMQ_PASS:-guest}@rabbitmq:5672//
      - CELERY_RESULT_BACKEND=db+postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@db:5432/${POSTGRES_DB:-whazz_audio}
      - SECRET_KEY=${SECRET_KEY:-change-me-in-production}
      - DEBUG=${DEBUG:-false}
      - FRONTEND_URL=${FRONTEND_URL:-http://localhost:3000}
    depends_on:
      db:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    volumes:
      - uploads_data:/app/uploads
      - processed_data:/app/processed_audio
    networks:
      - wazz-network

  worker:
    build:
      context: .
      dockerfile: wazz-audio-worker/Dockerfile
    container_name: wazz-worker
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@db:5432/${POSTGRES_DB:-whazz_audio}
      - CELERY_BROKER_URL=amqp://${RABBITMQ_USER:-guest}:${RABBITMQ_PASS:-guest}@rabbitmq:5672//
      - CELERY_RESULT_BACKEND=db+postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@db:5432/${POSTGRES_DB:-whazz_audio}
      - CLEARVOICE_MODEL_NAME=${CLEARVOICE_MODEL_NAME:-MossFormer2_SE_48K}
    depends_on:
      db:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    volumes:
      - uploads_data:/app/uploads
      - processed_data:/app/processed_audio
    networks:
      - wazz-network

  frontend:
    build:
      context: wazz-audio-frontend
      dockerfile: Dockerfile
      args:
        - NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL:-http://localhost:8000}
        - NEXT_PUBLIC_APP_NAME=${NEXT_PUBLIC_APP_NAME:-WazzAudio}
        - NEXT_PUBLIC_APP_URL=${NEXT_PUBLIC_APP_URL:-http://localhost:3000}
    container_name: wazz-frontend
    restart: unless-stopped
    ports:
      - "3000:3000"
    depends_on:
      - backend
    networks:
      - wazz-network

volumes:
  postgres_data:
  rabbitmq_data:
  uploads_data:
  processed_data:

networks:
  wazz-network:
    driver: bridge
EOF
```

---

## Step 4: Build All Images

```bash
docker compose build
```

---

## Step 5: Start All Services

```bash
docker compose up -d
```

---

## Step 6: Verify Services Are Running

```bash
docker compose ps
```

Expected output:
```
NAME             STATUS                   PORTS
wazz-postgres    running (healthy)        0.0.0.0:5432->5432/tcp
wazz-rabbitmq    running (healthy)        0.0.0.0:5672->5672/tcp, 0.0.0.0:15672->15672/tcp
wazz-backend     running                  0.0.0.0:8000->8000/tcp
wazz-worker      running
wazz-frontend    running                  0.0.0.0:3000->3000/tcp
```

---

## Step 7: Check Service Health

```bash
# Backend health
curl http://localhost:8000/health

# Frontend
curl http://localhost:3000

# RabbitMQ Management UI
open http://localhost:15672  # Login: guest/guest
```

---

## Step 8: View Logs (Optional)

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f backend
docker compose logs -f worker
docker compose logs -f frontend
```

---

## Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Frontend | http://localhost:3000 | - |
| Backend API | http://localhost:8000 | - |
| API Docs | http://localhost:8000/docs | - |
| RabbitMQ UI | http://localhost:15672 | guest / guest |

---

## Common Operations

### Stop All Services
```bash
docker compose down
```

### Restart a Service
```bash
docker compose restart backend
docker compose restart worker
```

### Rebuild and Restart
```bash
docker compose up -d --build
```

### Scale Workers
```bash
docker compose up -d --scale worker=3
```

### Database Backup
```bash
docker exec wazz-postgres pg_dump -U postgres whazz_audio > backup_$(date +%Y%m%d).sql
```

### Database Restore
```bash
docker exec -i wazz-postgres psql -U postgres whazz_audio < backup.sql
```

### Access Database Shell
```bash
docker exec -it wazz-postgres psql -U postgres -d whazz_audio
```

### Clean Up Everything (WARNING: Deletes Data)
```bash
docker compose down -v
docker image prune -a
```

---

## Troubleshooting

### Check if database is ready
```bash
docker exec wazz-postgres pg_isready -U postgres
```

### Check RabbitMQ queues
```bash
docker exec wazz-rabbitmq rabbitmqctl list_queues
```

### View container logs
```bash
docker logs wazz-backend
docker logs wazz-worker
docker logs wazz-frontend
```

### Restart failed container
```bash
docker compose restart <service-name>
```

---

## Manual Deployment (Without Docker Compose)

If you prefer to run containers individually:

### Step A: Create Network
```bash
docker network create wazz-network
```

### Step B: Start PostgreSQL
```bash
docker run -d \
  --name wazz-postgres \
  --network wazz-network \
  -p 5432:5432 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=whazz_audio \
  -v wazz_postgres_data:/var/lib/postgresql/data \
  postgres:15-alpine
```

### Step C: Start RabbitMQ
```bash
docker run -d \
  --name wazz-rabbitmq \
  --network wazz-network \
  -p 5672:5672 \
  -p 15672:15672 \
  rabbitmq:3-management-alpine
```

### Step D: Wait for Infrastructure (30 seconds)
```bash
sleep 30
```

### Step E: Build Backend Image
```bash
docker build -t wazz-audio-backend:latest -f wazz-audio-backend/Dockerfile .
```

### Step F: Start Backend
```bash
docker run -d \
  --name wazz-backend \
  --network wazz-network \
  -p 8000:8000 \
  -e DATABASE_URL=postgresql://postgres:postgres@wazz-postgres:5432/whazz_audio \
  -e CELERY_BROKER_URL=amqp://guest:guest@wazz-rabbitmq:5672// \
  -e SECRET_KEY=your-secret-key \
  -v wazz_uploads:/app/uploads \
  -v wazz_processed:/app/processed_audio \
  wazz-audio-backend:latest
```

### Step G: Build Worker Image
```bash
docker build -t wazz-audio-worker:latest -f wazz-audio-worker/Dockerfile .
```

### Step H: Start Worker
```bash
docker run -d \
  --name wazz-worker \
  --network wazz-network \
  -e DATABASE_URL=postgresql://postgres:postgres@wazz-postgres:5432/whazz_audio \
  -e CELERY_BROKER_URL=amqp://guest:guest@wazz-rabbitmq:5672// \
  -v wazz_uploads:/app/uploads \
  -v wazz_processed:/app/processed_audio \
  wazz-audio-worker:latest
```

### Step I: Build Frontend Image
```bash
docker build -t wazz-audio-frontend:latest \
  --build-arg NEXT_PUBLIC_API_URL=http://localhost:8000 \
  -f wazz-audio-frontend/Dockerfile wazz-audio-frontend/
```

### Step J: Start Frontend
```bash
docker run -d \
  --name wazz-frontend \
  --network wazz-network \
  -p 3000:3000 \
  wazz-audio-frontend:latest
```

### Step K: Verify All Containers
```bash
docker ps
```
