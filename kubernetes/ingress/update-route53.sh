#!/bin/bash
set -e
SUBDOMAIN="store.bennymaliti.co.uk"
ROOT_DOMAIN="bennymaliti.co.uk"
REGION="eu-west-2"

echo "Getting ALB DNS from ingress..."
ALB_DNS=$(kubectl get ingress ecommerce-ingress -n ecommerce -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
[ -z "$ALB_DNS" ] && echo "ALB not found yet" && exit 1

ALB_ZONE_ID=$(aws elbv2 describe-load-balancers --region $REGION \
  --query "LoadBalancers[?DNSName=='$ALB_DNS'].CanonicalHostedZoneId" --output text)

ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${ROOT_DOMAIN}.'].Id" \
  --output text | sed 's|/hostedzone/||')

aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch "{
  \"Changes\": [{\"Action\": \"UPSERT\", \"ResourceRecordSet\": {
    \"Name\": \"$SUBDOMAIN\", \"Type\": \"A\",
    \"AliasTarget\": {\"HostedZoneId\": \"$ALB_ZONE_ID\",
      \"DNSName\": \"$ALB_DNS\", \"EvaluateTargetHealth\": true}}}]}"

echo "Done! Live at: https://$SUBDOMAIN"
