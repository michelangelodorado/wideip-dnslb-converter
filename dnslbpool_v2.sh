#!/bin/bash

# Declare associative arrays
declare -A pool_list
declare -A membersip_array

# Get list of wide IPs
output=$(tmsh list gtm pool a one-line all-properties)

# Loop through each line of output
while IFS= read -r line; do
    pool_name=$(awk '{print $4}' <<< "$line")
    dnslbpool_name=$(echo "$pool_name" | sed 's/[^a-zA-Z0-9]/-/g; s/.*/\L&/')
    type=$(awk '{print $3}' <<< "$line")
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
    pool_list["$dnslbpool_name"]="type: $type, lbmode: $lbmode, monitor: $monitor, members: ${membersip_array["$dnslbpool_name"]}, ttl: $ttl"
done <<< "$output"

# Loop through each pool in the pool_list
for dnslbpool_name in "${!pool_list[@]}"; do
	# Extract only the TTL value from the string
	ttl=$(awk -F 'ttl: ' '{print $2}' <<< "echo ${pool_list[$dnslbpool_name]}")
	lbmode=$(awk -F 'lbmode: ' '{print $2}' <<< "${pool_list[$dnslbpool_name]}" | awk -F ',' '{print $1}')
	members=$(awk -F 'members: ' '{print $2}' <<< "${pool_list[$dnslbpool_name]}" | awk -F ',' '{print $1}')

    # Initialize an empty string to store the JSON strings
    members_string=""
    
    # Loop through each record in the current zone
    for ip in ${membersip_array["$dnslbpool_name"]}; do
        # Create JSON string for each member and append to the existing string
        members_string+="{\"ip_endpoint\":\"$ip\",\"ratio\":10,\"priority\":1},"
    done

    # Remove the trailing comma from the JSON string
    members_string="${members_string%,}"
	
    # Example curl command using TTL value
    curl -X POST -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" \
    -H "Accept: application/json" -H "Access-Control-Allow-Origin: *" \
    -H "x-volterra-apigw-tenant: cag-waap2023" -H "Content-Type: application/json" \
    -d "{\"metadata\":{\"name\":\"$dnslbpool_name\",\"namespace\":\"system\"},\"spec\":{\"a_pool\":{\"members\":[$members_string],\"disable_health_check\":null,\"max_answers\":1},\"ttl\":\"$ttl\",\"load_balancing_mode\":\"$lbmode\"}}" \
    "https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_lb_pools"
done

# Unset variables to free up memory
unset pool_list membersip_array
