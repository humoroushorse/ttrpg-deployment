#!/bin/bash
set -e

ENV="${1:-local}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/keycloak-realms.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==> Configuring Keycloak for environment: ${ENV}${NC}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ Config file not found: ${CONFIG_FILE}${NC}"
    exit 1
fi

# Keycloak connection info
KC_NAMESPACE="platform"
KC_SERVICE="platform-keycloak"
KC_PORT=8080
KC_ADMIN_USER="admin"
KC_ADMIN_PASS="admin"

# Port-forward to Keycloak
echo -e "${BLUE}Setting up port-forward to Keycloak...${NC}"
kubectl port-forward -n "${KC_NAMESPACE}" "svc/${KC_SERVICE}" 18080:${KC_PORT} &
PF_PID=$!
sleep 3

KC_URL="http://localhost:18080"

cleanup() {
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for Keycloak to be reachable
echo -e "${BLUE}Waiting for Keycloak to be reachable...${NC}"
for i in $(seq 1 30); do
    if curl -sf "${KC_URL}/realms/master" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Keycloak is reachable${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}✗ Keycloak not reachable after 30 attempts${NC}"
        exit 1
    fi
    sleep 2
done

# Get admin token
echo -e "${BLUE}Getting admin token...${NC}"
TOKEN=$(curl -sf -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${KC_ADMIN_USER}" \
    -d "password=${KC_ADMIN_PASS}" \
    -d "grant_type=password" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

if [ -z "$TOKEN" ]; then
    echo -e "${RED}✗ Failed to get admin token${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Got admin token${NC}"

# Read number of realms from config
REALM_COUNT=$(python3 -c "import json; data=json.load(open('${CONFIG_FILE}')); print(len(data['realms']))")

echo -e "${BLUE}Processing ${REALM_COUNT} realm(s) from config...${NC}"
echo ""

for i in $(seq 0 $((REALM_COUNT - 1))); do
    # Extract realm config
    REALM_NAME=$(python3 -c "import json; data=json.load(open('${CONFIG_FILE}')); print(data['realms'][$i]['name'])")
    REALM_JSON=$(python3 -c "
import json
data = json.load(open('${CONFIG_FILE}'))
realm = data['realms'][$i]
# Remove clients key for realm creation payload
clients = realm.pop('clients', [])
print(json.dumps(realm))
")

    echo -e "${BLUE}--- Realm: ${REALM_NAME} ---${NC}"

    # Create realm if it doesn't exist
    REALM_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "${KC_URL}/realms/${REALM_NAME}" 2>/dev/null || echo "000")

    if [ "$REALM_STATUS" = "200" ]; then
        echo -e "${YELLOW}⚠ Realm '${REALM_NAME}' already exists${NC}"
    else
        echo -e "${BLUE}Creating realm '${REALM_NAME}'...${NC}"
        # Build realm payload (rename 'name' to 'realm' for Keycloak API)
        REALM_PAYLOAD=$(python3 -c "
import json
data = json.load(open('${CONFIG_FILE}'))
realm = data['realms'][$i].copy()
realm.pop('clients', None)
realm['realm'] = realm.pop('name')
print(json.dumps(realm))
")
        curl -sf -X POST "${KC_URL}/admin/realms" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${REALM_PAYLOAD}"
        echo -e "${GREEN}✓ Realm '${REALM_NAME}' created${NC}"
    fi

    # Process clients for this realm
    CLIENT_COUNT=$(python3 -c "import json; data=json.load(open('${CONFIG_FILE}')); print(len(data['realms'][$i].get('clients', [])))")

    for j in $(seq 0 $((CLIENT_COUNT - 1))); do
        CLIENT_ID=$(python3 -c "import json; data=json.load(open('${CONFIG_FILE}')); print(data['realms'][$i]['clients'][$j]['clientId'])")
        CLIENT_JSON=$(python3 -c "import json; data=json.load(open('${CONFIG_FILE}')); print(json.dumps(data['realms'][$i]['clients'][$j]))")

        # Check if client exists
        CLIENT_EXISTS=$(curl -sf "${KC_URL}/admin/realms/${REALM_NAME}/clients?clientId=${CLIENT_ID}" \
            -H "Authorization: Bearer ${TOKEN}" | python3 -c "import sys,json; data=json.load(sys.stdin); print('yes' if len(data)>0 else 'no')" 2>/dev/null || echo "no")

        if [ "$CLIENT_EXISTS" = "yes" ]; then
            echo -e "${YELLOW}⚠ Client '${CLIENT_ID}' already exists in realm '${REALM_NAME}'${NC}"
        else
            echo -e "${BLUE}Creating client '${CLIENT_ID}' in realm '${REALM_NAME}'...${NC}"
            curl -sf -X POST "${KC_URL}/admin/realms/${REALM_NAME}/clients" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d "${CLIENT_JSON}"
            echo -e "${GREEN}✓ Client '${CLIENT_ID}' created${NC}"
        fi
    done

    echo ""
done

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Keycloak Configuration Complete${NC}"
echo -e "${GREEN}========================================${NC}"
