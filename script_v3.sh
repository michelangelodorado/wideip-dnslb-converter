#!/bin/bash

# Get list of wide IPs
output=$(tmsh list gtm wideip all-properties one-line)

# Declare associative arrays
declare -A wideip_list
declare -A current_wideip_info
declare -A zone_array
declare -A subdomain_info
declare -A a_record_per_zone

# Unset variables
function unset_arrays {
unset current_wideip_info name subdomain domain type aliases description status failure_rcode last_resort_pool load_balancing_decision_log metadata minimal_response partition persist_cidr_ipv4 persist_cidr_ipv6 persistence pool_lb_mode pools pool_cname topology_edns0 ttl_persistence poolnames poolnames_array zone_array subdomain_info a_record_per_zone;
}
# Print wide IP details
function print_wideip {
for wideip in "${!wideip_list[@]}"; do
    echo "Wide IP: $wideip, Details: ${wideip_list[$wideip]}"
done
}
# Update Zone Records
function update_zonerecords {
curl -X PUT -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" -H "Accept: application/json" -H "Access-Control-Allow-Origin: *" -H "x-volterra-apigw-tenant: f5-apac-ent" -H "Content-Type: application/json" -d "{\"metadata\":{\"name\":\"$zone\",\"namespace\":\"system\"},\"spec\":{\"primary\":{\"allow_http_lb_managed_records\":true,\"default_rr_set_group\":[$a_records_string],\"default_soa_parameters\":{},\"dnssec_mode\":{},\"rr_set_group\":[],\"soa_parameters\":{\"refresh\":3600,\"expire\":0,\"retry\":60,\"negative_ttl\":0,\"ttl\":0}}}}" https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_zones/$zone
}
# Create Zone
function create_zone {
curl -X POST -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" -H "Accept: application/json" -H "Access-Control-Allow-Origin: *" -H "x-volterra-apigw-tenant: f5-apac-ent" -H "Content-Type: application/json" -d "{\"metadata\":{\"name\":\"$zone\",\"namespace\":\"system\"},\"spec\":{\"primary\":{\"allow_http_lb_managed_records\":true},\"default_soa_parameters\":{},\"dnssec_mode\":{},\"rr_set_group\":[],\"soa_parameters\":{\"refresh\":3600,\"expire\":0,\"retry\":60,\"negative_ttl\":0,\"ttl\":0}}}" https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_zones
}

# Loop through each line of output
while IFS= read -r line; do
    # Extracting specific details using awk and sed based on the current line
    name=$(echo "$line" | awk '{print $4}')
    subdomain=$(echo "$name" | cut -d'.' -f1)
    domain=$(echo "$name" | sed 's/^[^.]*\.//')
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
    current_wideip_info=([Type]="$type" [Subdomain]="$subdomain" [Domain]="$domain" [Status]="$status" [Pool_LB_Mode]="$pool_lb_mode" [Pools]="${poolnames_array[@]}")

    # Assign wideip_info to wideip_list
    wideip_list["$name"]="${current_wideip_info[@]}"
    
    # Add subdomains to zone_array
    if [ -n "${zone_array[$domain]}" ]; then
        zone_array["$domain"]="${zone_array[$domain]},$subdomain"
    else
        zone_array["$domain"]=$subdomain
    fi

    # Store subdomain information in subdomain_info array
    subdomain_info["$subdomain"]="${current_wideip_info[@]}"
	
	# Store subdomain type "a" and add it to the array for that zone
	if [ "$type" == "a" ]; then
	    a_record_per_zone[$domain]="${a_record_per_zone[$domain]}${a_record_per_zone[$domain]:+,}$subdomain"
	fi
done <<< "$output"

# Loop through each domain in a_record_per_zone and echo its A record subdomains
for domain in "${!a_record_per_zone[@]}"; do
    echo "Domain: $domain"
    echo "A Record Subdomains: ${a_record_per_zone[$domain]}"
    echo "--------------------------"
    # Initialize an empty string to store the JSON strings
    a_records_string=""
	
    # Loop through each record in the current zone
    for record in ${a_record_per_zone[$domain]//,/ }; do
        # Create JSON string for each A record and append to the existing string
        a_records_string+="{\"ttl\":3600,\"a_record\":{\"name\":\"$record\",\"values\":[\"8.8.8.8\"]}},"
    done

    # Remove the trailing comma from the JSON string
    a_records_string="${a_records_string%,}"

    # Print the final JSON string
    echo "$a_records_string"
done

for zone in "${!zone_array[@]}"; do
	create_zone
    update_zonerecords	
done

unset_arrays
