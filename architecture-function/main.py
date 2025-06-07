import json
import os
import redis
from datetime import datetime
from google.cloud import compute_v1
import functions_framework
from flask import jsonify

# Configuration
PROJECT_ID = os.environ.get("PROJECT_ID", "devops-realm")
REGION = os.environ.get("REGION", "europe-west4")
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))
REDIS_PASSWORD = os.environ.get("REDIS_PASSWORD", "")
CACHE_TTL = int(os.environ.get("CACHE_TTL", 300))

# Redis connection
try:
    redis_client = redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        password=REDIS_PASSWORD if REDIS_PASSWORD else None,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5,
    )
    redis_client.ping()
    print("✅ Redis connected successfully")
except Exception as e:
    print(f"❌ Redis connection failed: {e}")
    redis_client = None


def get_vpc_networks():
    """Get VPC networks and subnets"""
    try:
        networks_client = compute_v1.NetworksClient()
        subnets_client = compute_v1.SubnetworksClient()

        networks = []

        # Get all networks in the project
        for network in networks_client.list(project=PROJECT_ID):
            network_info = {
                "name": network.name,
                "description": network.description or "",
                "creation_timestamp": network.creation_timestamp,
                "self_link": network.self_link,
                "subnets": [],
            }

            # Get all subnets in the region
            try:
                for subnet in subnets_client.list(project=PROJECT_ID, region=REGION):
                    # Check if this subnet belongs to this network
                    if network.self_link in subnet.network:
                        subnet_info = {
                            "name": subnet.name,
                            "ip_cidr_range": subnet.ip_cidr_range,
                            "region": REGION,
                            "private_ip_google_access": subnet.private_ip_google_access,
                            "creation_timestamp": subnet.creation_timestamp,
                            "network": network.name,
                        }
                        network_info["subnets"].append(subnet_info)
            except Exception as subnet_error:
                print(
                    f"Error getting subnets for network {network.name}: {subnet_error}"
                )

            networks.append(network_info)

        return networks

    except Exception as e:
        print(f"Error getting VPC networks: {e}")
        return []


def get_cached_report():
    """Get report from Redis cache"""
    if not redis_client:
        return None
    try:
        cached_data = redis_client.get("vpc_report")
        if cached_data:
            return json.loads(cached_data)
    except Exception as e:
        print(f"Error getting cached report: {e}")
    return None


def cache_report(report):
    """Cache report in Redis"""
    if not redis_client:
        return False
    try:
        redis_client.setex("vpc_report", CACHE_TTL, json.dumps(report, indent=2))
        return True
    except Exception as e:
        print(f"Error caching report: {e}")
        return False


@functions_framework.http
def vpc_discovery(request):
    """HTTP Cloud Function to discover VPC networks and subnets"""

    # Handle CORS
    if request.method == "OPTIONS":
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Max-Age": "3600",
        }
        return ("", 204, headers)

    headers = {"Access-Control-Allow-Origin": "*"}

    try:
        # Check query parameters
        force_refresh = request.args.get("refresh", "false").lower() == "true"

        # Try to get cached report first (unless force refresh)
        if not force_refresh:
            cached_report = get_cached_report()
            if cached_report:
                cached_report["cached"] = True
                cached_report["served_at"] = datetime.utcnow().isoformat()
                return jsonify(cached_report), 200, headers

        # Generate fresh report
        vpc_networks = get_vpc_networks()

        # Count subnets
        total_subnets = sum(len(network["subnets"]) for network in vpc_networks)

        report = {
            "project_id": PROJECT_ID,
            "region": REGION,
            "generated_at": datetime.utcnow().isoformat(),
            "cached": False,
            "vpc_networks": vpc_networks,
            "summary": {
                "total_networks": len(vpc_networks),
                "total_subnets": total_subnets,
                "network_names": [network["name"] for network in vpc_networks],
            },
            "cache_info": {
                "cache_enabled": redis_client is not None,
                "cache_ttl_seconds": CACHE_TTL,
            },
        }

        # Cache the report
        if cache_report(report):
            report["cache_info"]["cached_successfully"] = True
        else:
            report["cache_info"]["cached_successfully"] = False

        return jsonify(report), 200, headers

    except Exception as e:
        error_response = {
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat(),
            "project_id": PROJECT_ID,
            "region": REGION,
        }
        return jsonify(error_response), 500, headers


@functions_framework.http
def health(request):
    """Health check endpoint"""
    headers = {"Access-Control-Allow-Origin": "*"}

    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "project_id": PROJECT_ID,
        "region": REGION,
        "redis_connected": False,
    }

    # Check Redis connection
    if redis_client:
        try:
            redis_client.ping()
            health_status["redis_connected"] = True
        except:
            health_status["redis_connected"] = False

    return jsonify(health_status), 200, headers


# For local testing with functions-framework
if __name__ == "__main__":
    import os

    os.environ.setdefault("FUNCTION_TARGET", "vpc_discovery")
    # The functions-framework will handle the rest
