#!/bin/bash

# Get list of wide IPs
output=$(tmsh list gtm wideip all-properties one-line)

# Declare an associative array
declare -A wideip_info

# Loop through each line of output
while IFS= read -r line; do
    # Extracting specific details using awk and sed based on the current line
    name=$(echo "$line" | awk '{print $4}')
    type=$(echo "$line" | awk '{print $3}')
    aliases=$(echo "$line" | grep -o 'aliases [^}]*' | awk '{print $2}')
    description=$(echo "$line" | grep -o 'description [^ ]*' | sed 's/description //')
    status=$(echo "$line" | awk '{print $12}')
    failure_rcode=$(echo "$line" | grep -o 'failure-rcode [^ ]*' | sed 's/failure-rcode //')
    last_resort_pool=$(echo "$line" | grep -o 'last-resort-pool [^ ]*' | sed 's/last-resort-pool //')
    load_balancing_decision_log=$(echo "$line" | grep -o 'load-balancing-decision-log-verbosity [^ ]*' | sed 's/load-balancing-decision-log-verbosity //')
    metadata=$(echo "$line" | grep -o 'metadata [^ ]*' | sed 's/metadata //')
    minimal_response=$(echo "$line" | grep -o 'minimal-response [^ ]*' | sed 's/minimal-response //')
    partition=$(echo "$line" | grep -o 'partition [^ ]*' | sed 's/partition //')
    persist_cidr_ipv4=$(echo "$line" | grep -o 'persist-cidr-ipv4 [^ ]*' | sed 's/persist-cidr-ipv4 //')
    persist_cidr_ipv6=$(echo "$line" | grep -o 'persist-cidr-ipv6 [^ ]*' | sed 's/persist-cidr-ipv6 //')
    persistence=$(echo "$line" | grep -o ' persistence [^ ]*' | sed 's/persistence //')
    pool_lb_mode=$(echo "$line" | grep -o 'pool-lb-mode [^ ]*' | sed 's/pool-lb-mode //')
    pools=$(echo "$line" | grep -o -P '(?<=pools \{ ).*?(?=\} \})')
    pool_cname=$(echo "$line" | grep -o 'pools-cname [^ ]*' | sed 's/pools-cname //')
    topology_edns0=$(echo "$line" | grep -o 'topology-prefer-edns0-client-subnet [^ ]*' | sed 's/topology-prefer-edns0-client-subnet //')
    ttl_persistence=$(echo "$line" | grep -o 'ttl-persistence [^ ]*' | sed 's/ttl-persistence //')
    # Use grep to find strings before "{"
    poolnames=$(echo "$pools" | grep -oP '\S+(?=\s*{)')

    # Convert matches to an array
    readarray -t poolnames_array <<< "$poolnames"
    
    # Store extracted values in the associative array
    wideip_info["$name"]="{ 
        Type: $type, 
        Aliases: $aliases, 
        Description: $description, 
        Status: $status, 
        Failure Rcode: $failure_rcode, 
        Last Resort Pool: $last_resort_pool, 
        Load Balancing Decision Log: $load_balancing_decision_log, 
        Metadata: $metadata, 
        Minimal Response: $minimal_response, 
        Partition: $partition, 
        Persist CIDR IPv4: $persist_cidr_ipv4, 
        Persist CIDR IPv6: $persist_cidr_ipv6, 
        Persistence: $persistence, 
        Pool LB Mode: $pool_lb_mode, 
        Pools: ${poolnames_array[@]}, 
        Pool CNAME: $pool_cname, 
        Topology EDNS0: $topology_edns0, 
        TTL Persistence: $ttl_persistence 
    }"

    # Unset variables
    unset name type aliases description status failure_rcode last_resort_pool load_balancing_decision_log metadata minimal_response partition persist_cidr_ipv4 persist_cidr_ipv6 persistence pool_lb_mode pools pool_cname topology_edns0 ttl_persistence poolnames poolnames_array

done <<< "$output"

# Print the associative array (for testing purposes)
for key in "${!wideip_info[@]}"; do
    echo "Key: $key, Value: ${wideip_info[$key]}"
done
