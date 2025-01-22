### dhcp-dns-prune.rsc
#
# This script will find all static DNS entries created by the dhcp-to-dns script
# and check the timestamp to see if it's been more than 30 days since it was
# added/updated, and if so, delete it.
#
# This is intended to be run on a schedule, once per day should be optimal.
#
# See: https://github.com/MaffooClock/MikroTik-Scripts/blob/main/DHCP-to-DNS
#

####################################################################################################

# This will be set by the dhcp-to-dns script
:global dhcp2dnsTag

:if ($dhcp2dnsTag = nil) do={

  :log warning "Unset `dhcp2dnsTag` global variable; has the 'dhcp-to-dns' script run?"

} else={

  :local metaTag [:serialize to=json value={tag=$dhcp2dnsTag}]
  :set metaTag [:pick $metaTag 1 ([:len $metaTag]-1)]

  :foreach thisEntry in=[/ip/dns/static find where comment~$metaTag] do={

    :local entryName [/ip/dns/static get $thisEntry name]
    :local entryAddress [/ip/dns/static get $thisEntry address]
    :local meta [:deserialize from=json value=[/ip/dns/static get $thisEntry comment]]
        
    :local now [:tonum [:timestamp]]
    :local entryTime ($meta->"time")
    :local expirationDate ($entryTime + 2592000)

    #Check the timestamp and delete the entry if it's more than 30 days past
    :if ($now > $expirationDate) do={
      :log info "Deleting old DHCP-to-DNS record for $entryName"
      /ip/dns/static remove $thisEntry
    }
  }

}