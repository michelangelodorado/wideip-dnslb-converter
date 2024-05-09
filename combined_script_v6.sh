#!/bin/bash

# Get list of wide IPs
wideip_output=$(tmsh list gtm wideip all-properties one-line)

# Get list of Pool
pool_output=$(tmsh list gtm pool a one-line all-properties)

# Declare associative arrays
declare -A wideip_list
declare -A current_wideip_info
declare -A zone_array
declare -A subdomain_info
declare -A a_record_per_zone
declare -A pool_list
declare -A membersip_array

# Unset variables
function unset_arrays {
    unset current_wideip_info name subdomain domain type aliases description status failure_rcode last_resort_pool load_balancing_decision_log metadata minimal_response partition persist_cidr_ipv4 persist_cidr_ipv6 persistence pool_lb_mode pools pool_cname topology_edns0 ttl_persistence poolnames poolnames_array zone_array subdomain_info a_record_per_zone dnslb_name pool_list membersip_array
}

# Print wide IP details
function print_wideip {
    for wideip in "${!wideip_list[@]}"; do
        echo "Wide IP: $wideip, Details: ${wideip_list[$wideip]}"
    done
}

# Create Zone
function create_zone {
curl -X POST -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" -H "Accept: application/json" -H "Access-Control-Allow-Origin: *" -H "x-volterra-apigw-tenant: cag-waap2023" -H "Content-Type: application/json" -d "{\"metadata\":{\"name\":\"$zone\",\"namespace\":\"system\"},\"spec\":{\"primary\":{\"allow_http_lb_managed_records\":true},\"default_soa_parameters\":{},\"dnssec_mode\":{},\"rr_set_group\":[],\"soa_parameters\":{\"refresh\":3600,\"expire\":0,\"retry\":60,\"negative_ttl\":0,\"ttl\":0}}}" https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_zones
}

# Create DNSLB
function create_dnslb {
curl -X POST -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" -H "Accept: application/json" -H "Access-Control-Allow-Origin: *" -H "x-volterra-apigw-tenant: cag-waap2023" -H "Content-Type: application/json" -d "{\"metadata\":{\"name\":\"$dnslbname\",\"namespace\":\"system\",\"labels\":{},\"annotations\":{},\"disable\":false},\"spec\":{\"record_type\":\"A\",\"rule_list\":{\"rules\":[{\"geo_location_set\":{\"tenant\":\"cag-waap2023-gwjvytud\",\"namespace\":\"system\",\"name\":\"geo-1\",\"kind\":\"geo_location_set\"},\"pool\":{\"tenant\":\"cag-waap2023-gwjvytud\",\"namespace\":\"system\",\"name\":\"$xcdnslbpoolname\",\"kind\":\"dns_lb_pool\"},\"score\":100}]},\"response_cache\":{\"disable\":{}}}}" https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_load_balancers
}

# Loop through each line of output
while IFS= read -r line; do
    pool_name=$(awk '{print $4}' <<< "$line")
    dnslbpool_name=$(echo "$pool_name" | sed 's/[^a-zA-Z0-9]/-/g; s/.*/\L&/')
    pool_type=$(awk '{print $3}' <<< "$line")
    lbmode=$(grep -o 'load-balancing-mode [^ ]*' <<< "$line" | awk '{print $2}')
    # Convert load_balancing_mode to lowercase if it is "ROUND_ROBIN"
    if [[ "$lbmode" == "round-robin" ]]; then
        lbmode="ROUND_ROBIN"
    elif [[ "$lbmode" == "static-persistence" ]]; then
        lbmode="STATIC_PERSIST"
    elif [[ "$lbmode" == "global-availability" ]]; then
        lbmode="PRIORITY"
    elif [[ "$lbmode" == "ratio" ]]; then
        lbmode="RATIO_MEMBER"
    fi
    
    # Extract members block using awk
    #members=$(awk -F 'members {| }' '{print $2}' <<< "$line")
    members=$(echo "$line" | grep -o -P '(?<=members \{ ).*?(?=\} \})')
    membernames=$(echo "$members" | grep -oP '\S+(?=\s*{)')
    # Temporary array to hold member IP addresses
    declare -a temp_members_array
    temp_members_array=($(awk -F ':' '{print $2}' <<< "$membernames"))
    monitor=$(awk -F 'monitor ' '{print $2}' <<< "$line" | awk '{print $1}')
    ttl=$(awk '{print $2}' <<< "$(grep -o 'ttl [^ ]*' <<< "$line")")
    
    # Assign values to the associative array
    membersip_array["$dnslbpool_name"]="${temp_members_array[@]}"

    # Store extracted values in the array
    pool_list["$dnslbpool_name"]="pool_type: $pool_type, lbmode: $lbmode, monitor: $monitor, members: ${membersip_array["$dnslbpool_name"]}, ttl: $ttl"
done <<< "$pool_output"

# Loop through each pool in the pool_list
for dnslbpool_name in "${!pool_list[@]}"; do
    # Extract only the TTL value from the string
    ttl=$(awk -F 'ttl: ' '{print $2}' <<< "${pool_list[$dnslbpool_name]}")
    lbmode=$(awk -F 'lbmode: ' '{print $2}' <<< "${pool_list[$dnslbpool_name]}" | awk -F ',' '{print $1}')
    members=$(awk -F 'members: ' '{print $2}' <<< "${pool_list[$dnslbpool_name]}" | awk -F ',' '{print $1}')
    pool_type=$(awk -F 'pool_type: ' '{print $2}' <<< "${pool_list[$dnslbpool_name]}" | awk -F ',' '{print $1}')

    # Check if pool_type is "a"
    if [[ "$pool_type" == "a" ]]; then
        # Initialize an empty string to store the JSON strings
        members_string=""

        # Loop through each record in the current zone
        for ip in ${membersip_array["$dnslbpool_name"]}; do
            # Create JSON string for each member and append to the existing string
            members_string+="{\"ip_endpoint\":\"$ip\",\"ratio\":10,\"priority\":1},"
        done

        # Remove the trailing comma from the JSON string
        members_string="${members_string%,}"

        # Create DNSLB Pools
        curl -X POST \
            -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" \
            -H "Accept: application/json" \
            -H "Access-Control-Allow-Origin: *" \
            -H "x-volterra-apigw-tenant: cag-waap2023" \
            -H "Content-Type: application/json" \
            -d "{\"metadata\":{\"name\":\"$dnslbpool_name\",\"namespace\":\"system\"},\"spec\":{\"a_pool\":{\"members\":[$members_string],\"disable_health_check\":null,\"max_answers\":1},\"ttl\":\"$ttl\",\"load_balancing_mode\":\"$lbmode\"}}" \
            "https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_lb_pools"
    fi
done

# Unset variables to free up memory
unset pool_list membersip_array

# Loop through each line of output
while IFS= read -r line; do
    # Extracting specific details using awk and sed based on the current line
    name=$(echo "$line" | awk '{print $4}')
    dnslb_name=$(echo "$name" | sed 's/\./-/g')
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
    poolnames=$(echo "$pools" | grep -oP '\S+(?=\s*{)' | sed 's/[^a-zA-Z0-9]/-/g; s/.*/\L&/')
    # Convert matches to an array
    readarray -t poolnames_array <<< "$poolnames"
    # Store extracted values in the associative array
    current_wideip_info=([Type]="$type" [Subdomain]="$subdomain" [Domain]="$domain" [Status]="$status" [DNSLB]="$dnslb_name" [Pools]="${poolnames_array[@]}" [Pool_LB_Mode]="$pool_lb_mode")

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
done <<< "$wideip_output"

for zone in "${!zone_array[@]}"; do
    create_zone
done

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
        xcdnslbpoolname=$(echo ${wideip_list[$record.$domain]} | awk '{for (i=6; i<=(NF-1); i++) {printf "%s", $i; if (i < NF-1) printf " "}}')
		echo "${a_record_per_zone[$domain]}"
        echo "xcdnslbpoolname: $xcdnslbpoolname"
        # Check if xcdnslbpoolname has multiple strings
        if [[ $xcdnslbpoolname == *" "* ]]; then
            echo "Multiple strings found in xcdnslbpoolname"
            # Split xcdnslbpoolname into an array based on space
            IFS=' ' read -ra pool_names <<< "$xcdnslbpoolname"
	        # Initialize an empty string to store the JSON strings
	        pools_string=""
            # Loop through each pool name in the array
            for pool_name in "${pool_names[@]}"; do
	            # Create JSON string for each member and append to the existing string
	            pools_string+="{\"geo_location_set\":{\"tenant\":\"cag-waap2023-gwjvytud\",\"namespace\":\"system\",\"name\":\"geo-1\",\"kind\":\"geo_location_set\"},\"pool\":{\"tenant\":\"cag-waap2023-gwjvytud\",\"namespace\":\"system\",\"name\":\"$pool_name\",\"kind\":\"dns_lb_pool\"},\"score\":100},"
            done
	        # Remove the trailing comma from the JSON string
	        pools_string="${pools_string%,}"
        else
			pools_string="{\"geo_location_set\":{\"tenant\":\"cag-waap2023-gwjvytud\",\"namespace\":\"system\",\"name\":\"geo-1\",\"kind\":\"geo_location_set\"},\"pool\":{\"tenant\":\"cag-waap2023-gwjvytud\",\"namespace\":\"system\",\"name\":\"$xcdnslbpoolname\",\"kind\":\"dns_lb_pool\"},\"score\":100}"
        fi
        dnslbname=$(echo "dnslb-$record-$domain" | sed 's/\./-/g')
		#create_dnslb
        curl -X POST -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" -H "Accept: application/json" -H "Access-Control-Allow-Origin: *" -H "x-volterra-apigw-tenant: cag-waap2023" -H "Content-Type: application/json" -d "{\"metadata\":{\"name\":\"$dnslbname\",\"namespace\":\"system\",\"labels\":{},\"annotations\":{},\"disable\":false},\"spec\":{\"record_type\":\"A\",\"rule_list\":{\"rules\":[$pools_string]},\"response_cache\":{\"disable\":{}}}}" https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_load_balancers
        a_records_string+="{\"ttl\":3600,\"lb_record\": {\"name\":\"$record\",\"value\":{\"namespace\": \"system\",\"name\":\"$dnslbname\"}}},"
    done
    # Remove the trailing comma from the JSON string
    a_records_string="${a_records_string%,}"
    # Print the final JSON string
    echo "$a_records_string"
	#update zone record
	curl -X PUT -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" -H "Accept: application/json" -H "Access-Control-Allow-Origin: *" -H "x-volterra-apigw-tenant: cag-waap2023" -H "Content-Type: application/json" -d "{\"metadata\":{\"name\":\"$domain\",\"namespace\":\"system\"},\"spec\":{\"primary\":{\"allow_http_lb_managed_records\":true,\"default_rr_set_group\":[$a_records_string],\"default_soa_parameters\":{},\"dnssec_mode\":{},\"rr_set_group\":[],\"soa_parameters\":{\"refresh\":3600,\"expire\":0,\"retry\":60,\"negative_ttl\":0,\"ttl\":0}}}}" https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_zones/$domain  
done

unset_arrays
