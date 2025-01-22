### update-linode.rsc
#
# This script will update a A record in Linode DNS, via their API, with the dynamic IPv4 address
# obtained via DHCP on a specified WAN interface
#
# Use this in a DHCP Client "script" field:
#     :if ( $bound ) do={ :delay 10s; /system/script run update-linode; }
#
# See: https://github.com/MaffooClock/MikroTik-Scripts/blob/main/DDNS-Linode
#

### Definitely change these:
:local linodeToken  ""
:local domainId     ""
:local recordId     ""
:local wanInterface "ether1"

### Don't mess with these unless you know what you're doing:
:local apiURL            "https://api.linode.com/v4/domains"
:local recordURL         "$apiURL/$domainId/records/$recordId"
:local headerAccept      "accept:application/json"
:local headerContentType "content-type:application/json"
:local headerAuth        "authorization:Bearer $linodeToken"
:local headers           "$headerAccept,$headerAuth,$headerContentType"

####################################################################################################

:global linodeLastIP

:if ( [/interface get $wanInterface value-name=running] ) do={
  
  # Get a list of dynamic addresses on the interface (hopefully it's just one)
  :local linodeCurrentIP [/ip address find interface=$wanInterface dynamic=yes disabled=no]
  :local addressCount [:len $linodeCurrentIP]

  :if ( addressCount = 0 ) do={
    :log error "Linode: could not find a dynamic address attached to $wanInterface"
    :error
  }

  :if ( addressCount > 1 ) do={
    :log error "Linode: multiple dynamic addresses found for $wanInterface"
    :error
  }

  # Get the address from the only object in the list
  :set linodeCurrentIP [/ip address get [:pick $linodeCurrentIP 0] address]
  
  # Strip the net mask off the IP address
  :for i from=( [:len $linodeCurrentIP] - 1 ) to=0 do={
     :if ( [:pick $linodeCurrentIP $i] = "/" ) do={ 
         :set linodeCurrentIP [:pick $linodeCurrentIP 0 $i]
     } 
  }

  :if ( [:toip $linodeCurrentIP] != [:toip $linodeLastIP] ) do={

    :log info "Linode: new address detected"

    # Generate a JSON string containing the IP address to send
    :local payload [:serialize to=json { target=$linodeCurrentIP }]

    # Run the fetch command with the ability to catch an error
    :onerror fetchError in={

      :log info "Linode: sending update for domain ID $domainId and record ID $recordId"
      :local result [/tool fetch url=$recordURL http-header-field=$headers http-data=$payload http-method=put as-value output=user]

      # Only update the previous address if the update request succeeded
      :if ( $result->"status" = "finished" ) do={
        
        :log info "Linode: updated to $linodeCurrentIP successful"
        :set linodeLastIP $linodeCurrentIP

      } else={
        # This will trigger the `onerror do={}` block below
        :error ($result->"status")
      }

    } do={
      :log error "Linode: failed to send update; error: $fetchError"
    }

  } else={
    :log info "Linode: no update needed, $linodeLastIP is current"
  }

} else={
  :log error "Linode: $wanInterface is not up"
  :error
}
