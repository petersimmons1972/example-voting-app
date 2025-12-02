# Simple Voting App Deployment

Quick recovery guide for rebuilding the voting app from scratch.

## Source
Original project: https://github.com/dockersamples/example-voting-app

## Architecture

5 microservices:
- **vote** - Python/Flask voting interface
- **result** - Node.js results display
- **worker** - .NET worker processes votes from Redis to PostgreSQL
- **redis** - In-memory message queue
- **postgres** - Persistent database

```
┌─────────┐      ┌───────┐      ┌────────┐      ┌──────────┐
│  vote   │─────▶│ redis │─────▶│ worker │─────▶│ postgres │
│ :80     │      │ :6379 │      │        │      │  :5432   │
└─────────┘      └───────┘      └────────┘      └──────────┘
                                                       │
                                                       ▼
                                                 ┌──────────┐
                                                 │  result  │
                                                 │   :80    │
                                                 └──────────┘
```

## Quick Deploy

### Option 1: Kubernetes (K3s)
```bash
cd /home/psimmons/projects/voting
chmod +x deploy-clean.sh
./deploy-clean.sh
```

### Option 2: Docker Compose
```bash
cd /home/psimmons/projects/voting
docker-compose up -d
```

## Verify Deployment

### Check pods
```bash
kubectl get pods -n voting-app
```

Expected output:
```
NAME                      READY   STATUS    RESTARTS   AGE
db-xxx                    1/1     Running   0          1m
redis-xxx                 1/1     Running   0          1m
vote-xxx                  1/1     Running   0          1m
vote-xxx                  1/1     Running   0          1m
result-xxx                1/1     Running   0          1m
result-xxx                1/1     Running   0          1m
worker-xxx                1/1     Running   0          1m
```

### Test locally
```bash
# Port-forward vote service
kubectl port-forward -n voting-app svc/vote 8080:80

# Port-forward result service
kubectl port-forward -n voting-app svc/result 8081:80

# Open in browser
open http://localhost:8080  # Vote
open http://localhost:8081  # Results
```

### Production URLs (with ingress)
- Vote: https://vote.petersimmons.com
- Result: https://result.petersimmons.com

## Clean Rebuild

To completely rebuild from scratch:

```bash
# Delete namespace (removes everything)
kubectl delete namespace voting-app

# Wait for deletion
kubectl wait --for=delete namespace/voting-app --timeout=60s

# Redeploy
./deploy-clean.sh
```

## Components

### Images (from Docker Hub)
- `dockersamples/examplevotingapp_vote:latest`
- `dockersamples/examplevotingapp_result:latest`
- `dockersamples/examplevotingapp_worker:latest`
- `redis:alpine`
- `postgres:15-alpine`

### No Persistent Storage
Both Redis and PostgreSQL use `emptyDir` volumes - data is lost on pod restart.
This is intentional for a simple demo app.

### Network
All services communicate within the `voting-app` namespace using Kubernetes DNS:
- Vote → Redis (`redis:6379`)
- Worker → Redis (`redis:6379`) → PostgreSQL (`db:5432`)
- Result → PostgreSQL (`db:5432`)

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -n voting-app <pod-name>
kubectl logs -n voting-app <pod-name>
```

### Vote not connecting to Redis
```bash
kubectl exec -n voting-app <vote-pod> -- ping redis
```

### Worker not processing votes
```bash
kubectl logs -n voting-app <worker-pod>
```

### PostgreSQL connection issues
```bash
kubectl exec -n voting-app <db-pod> -- psql -U postgres -c '\l'
```

## Files

- `deploy-clean.sh` - Simple deployment script (K3s/Kubernetes)
- `docker-compose.yml` - Docker Compose deployment
- `SIMPLE_DEPLOY.md` - This file
