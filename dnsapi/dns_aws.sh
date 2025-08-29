#!/usr/bin/env bash

# DNS Provider: AWS Route53
# Documentation: https://docs.aws.amazon.com/route53/
# Required: AWS CLI configured with appropriate permissions
# Required Environment Variables:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (or IAM role)
#   AWS_DEFAULT_REGION (optional, defaults to us-east-1)

PROVIDER_NAME="AWS Route53"
PROVIDER_DESCRIPTION="Amazon Route53 DNS service"

# Check if provider is configured and available
dns_aws_detect() {
    if ! command -v aws >/dev/null 2>&1; then
        echo "AWS CLI not found - provider unavailable"
        return 1
    fi
    
    # Test AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "AWS credentials not configured - provider unavailable"
        return 1
    fi
    
    echo "AWS Route53 provider available"
    return 0
}

# Get hosted zone ID for domain
_get_hosted_zone_id() {
    local domain="$1"
    aws route53 list-hosted-zones --query "HostedZones[?Name=='${domain}.'].Id" --output text | cut -d'/' -f3
}

# Add a DNS record
dns_aws_add() {
    local domain="$1"
    local record_type="$2"
    local name="$3" 
    local value="$4"
    local ttl="${5:-300}"
    
    echo "Adding $record_type record to Route53: $name"
    
    # Get hosted zone ID
    local zone_id=$(_get_hosted_zone_id "$domain")
    if [ -z "$zone_id" ]; then
        echo "Error: Could not find hosted zone for $domain"
        return 1
    fi
    
    # Prepare change batch
    local change_batch=""
    case "$record_type" in
        "SRV")
            change_batch="{\"Changes\":[{\"Action\":\"CREATE\",\"ResourceRecordSet\":{\"Name\":\"$name\",\"Type\":\"SRV\",\"TTL\":$ttl,\"ResourceRecords\":[{\"Value\":\"$value\"}]}}]}"
            ;;
        "CNAME")
            change_batch="{\"Changes\":[{\"Action\":\"CREATE\",\"ResourceRecordSet\":{\"Name\":\"$name\",\"Type\":\"CNAME\",\"TTL\":$ttl,\"ResourceRecords\":[{\"Value\":\"$value\"}]}}]}"
            ;;
        "TXT")
            # Quote TXT values
            local quoted_value="\"$value\""
            change_batch="{\"Changes\":[{\"Action\":\"CREATE\",\"ResourceRecordSet\":{\"Name\":\"$name\",\"Type\":\"TXT\",\"TTL\":$ttl,\"ResourceRecords\":[{\"Value\":\"$quoted_value\"}]}}]}"
            ;;
        *)
            echo "Error: Unsupported record type: $record_type"
            return 1
            ;;
    esac
    
    # Execute change
    local change_id
    change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$zone_id" \
        --change-batch "$change_batch" \
        --query 'ChangeInfo.Id' --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$change_id" ]; then
        echo "Successfully submitted $record_type record: $name"
        echo "Change ID: $change_id"
        return 0
    else
        echo "Error: Failed to create $record_type record"
        return 1
    fi
}

# Validate provider configuration
dns_aws_validate() {
    if ! command -v aws >/dev/null 2>&1; then
        echo "Error: AWS CLI not installed"
        echo "Install with: pip install awscli"
        return 1
    fi
    
    echo "Testing AWS credentials..."
    local identity
    identity=$(aws sts get-caller-identity --output text 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "✓ AWS credentials valid"
        echo "Account: $(echo "$identity" | cut -f1)"
        echo "User: $(echo "$identity" | cut -f3)"
        return 0
    else
        echo "✗ AWS credentials invalid or not configured"
        return 1
    fi
}

# Show provider-specific help
dns_aws_help() {
    cat << EOF
AWS Route53 DNS Provider Configuration:

Required:
- AWS CLI installed and configured
- AWS credentials with Route53 permissions

Setup Instructions:
1. Install AWS CLI: pip install awscli
2. Configure credentials: aws configure
   OR set environment variables:
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key" 
   export AWS_DEFAULT_REGION="us-east-1"

Required IAM Permissions:
- route53:ListHostedZones
- route53:ChangeResourceRecordSets
- route53:GetChange

Example Usage:
  aws configure  # Set up credentials
  ./zimbra-autodiscover-validator.sh --deploy aws

Supported Record Types: SRV, CNAME, TXT
Rate Limits: 5 requests per second per account
EOF
}