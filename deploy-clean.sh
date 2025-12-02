#!/bin/bash
#
# Simple Voting App Deployment Script
# Based on: https://github.com/dockersamples/example-voting-app
#
# Deploys the 5-component voting app:
#   - vote (Python/Flask frontend)
#   - result (Node.js results display)
#   - worker (.NET vote processor)
#   - redis (message queue)
#   - postgres (database)
#

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
NAMESPACE="voting-app"
DOMAIN="petersimmons.com"

echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Voting App Deployment (Clean)     ║${NC}"
echo -e "${BLUE}║  github.com/dockersamples/voting-app  ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo ""

# Create namespace
echo -e "${GREEN}[1/5]${NC} Creating namespace: ${NAMESPACE}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Deploy Redis (message queue)
echo -e "${GREEN}[2/5]${NC} Deploying Redis..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ${NAMESPACE}
  labels:
    app: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:alpine
        ports:
        - containerPort: 6379
          name: redis
        volumeMounts:
        - name: redis-data
          mountPath: /data
      volumes:
      - name: redis-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ${NAMESPACE}
  labels:
    app: redis
spec:
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
EOF

# Deploy PostgreSQL (database)
echo -e "${GREEN}[3/5]${NC} Deploying PostgreSQL..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  namespace: ${NAMESPACE}
  labels:
    app: db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_USER
          value: "postgres"
        - name: POSTGRES_PASSWORD
          value: "postgres"
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: db-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: db-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: ${NAMESPACE}
  labels:
    app: db
spec:
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: db
EOF

# Wait for backend services
echo -e "${YELLOW}⏳ Waiting for backend services...${NC}"
kubectl wait --for=condition=ready pod -l app=redis -n ${NAMESPACE} --timeout=60s
kubectl wait --for=condition=ready pod -l app=db -n ${NAMESPACE} --timeout=60s

# Deploy Worker (vote processor)
echo -e "${GREEN}[4/5]${NC} Deploying Worker..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: ${NAMESPACE}
  labels:
    app: worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      containers:
      - name: worker
        image: dockersamples/examplevotingapp_worker
EOF

# Deploy Vote (frontend)
echo -e "${GREEN}[5/5]${NC} Deploying Vote and Result frontends..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vote
  namespace: ${NAMESPACE}
  labels:
    app: vote
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vote
  template:
    metadata:
      labels:
        app: vote
    spec:
      containers:
      - name: vote
        image: dockersamples/examplevotingapp_vote
        ports:
        - containerPort: 80
          name: vote
---
apiVersion: v1
kind: Service
metadata:
  name: vote
  namespace: ${NAMESPACE}
  labels:
    app: vote
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: vote
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: result
  namespace: ${NAMESPACE}
  labels:
    app: result
spec:
  replicas: 2
  selector:
    matchLabels:
      app: result
  template:
    metadata:
      labels:
        app: result
    spec:
      containers:
      - name: result
        image: dockersamples/examplevotingapp_result
        ports:
        - containerPort: 80
          name: result
---
apiVersion: v1
kind: Service
metadata:
  name: result
  namespace: ${NAMESPACE}
  labels:
    app: result
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: result
EOF

# Create Traefik IngressRoutes (optional - requires TLS certificate)
echo ""
echo -e "${YELLOW}📝 Optional: Deploy Traefik ingress (requires TLS cert)?${NC}"
read -p "Deploy ingress? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Creating IngressRoutes...${NC}"
    kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: vote
  namespace: ${NAMESPACE}
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`vote.${DOMAIN}\`)
      kind: Rule
      services:
        - name: vote
          port: 80
  tls:
    secretName: petersimmons-tls
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: result
  namespace: ${NAMESPACE}
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`result.${DOMAIN}\`)
      kind: Rule
      services:
        - name: result
          port: 80
  tls:
    secretName: petersimmons-tls
EOF
fi

# Final status
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Deployment Complete          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}📊 Check status:${NC}"
echo -e "  kubectl get pods -n ${NAMESPACE}"
echo -e "  kubectl get services -n ${NAMESPACE}"
echo ""
echo -e "${YELLOW}🌐 Access URLs (if ingress deployed):${NC}"
echo -e "  Vote:   https://vote.${DOMAIN}"
echo -e "  Result: https://result.${DOMAIN}"
echo ""
echo -e "${YELLOW}🧪 Port-forward for local testing:${NC}"
echo -e "  kubectl port-forward -n ${NAMESPACE} svc/vote 8080:80"
echo -e "  kubectl port-forward -n ${NAMESPACE} svc/result 8081:80"
echo ""
