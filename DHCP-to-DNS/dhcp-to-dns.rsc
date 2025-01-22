### dhcp-to-dns.rsc
#
# This script will scan all DHCP leases with a "bound" status and create
# a static DNS entry pointing to the IP address on that lease.
#
# See: https://github.com/MaffooClock/MikroTik-Scripts/blob/main/DHCP-to-DNS
#


# Append a suffix to convert the hostname to a FQDN.  If you have a DNS server,
# create a forwarding zone that points to this device, and set that zone name here
:local dnsSuffix "dhcp.mydomain.local"

# Static DNS entries will have this tag in it's JSON metadata so that this script
# touches only those entries (same for the dhcp-dns-cleanup companion script).
# You shouldn't need to change this.
:global dhcp2dnsTag "dhcp-to-dns"

####################################################################################################

:foreach thisLease in=[/ip/dhcp-server/lease find where status=bound] do={

  :local hostname [/ip/dhcp-server/lease get $thisLease host-name]
  :local ipAddress [/ip/dhcp-server/lease get $thisLease active-address]
  :local macAddress [/ip/dhcp-server/lease get $thisLease mac-address]


  # ----------------------------------------------------------------------------------------------------
  # For an empty hostname, use the MAC address (as "mac-aabbccddeeff")

  :if ([:len $hostname] = 0) do={
    :set hostname "mac-"

    :for i from=0 to=16 do={
      
      :local char [:pick $macAddress $i]

      :if ($validChars ~ $char) do={
        :set hostname ($hostname . $char)
      }
    }
  }


  # ----------------------------------------------------------------------------------------------------
  # Trim the hostname if it's too long (per RFC 2181 section 11)

  :if ([:len $hostname] > 63) do={
    :set hostname [:pick $hostname 0 62]
  }


  # ----------------------------------------------------------------------------------------------------
  # Check each character in the hostname to ensure it's valid (per RFC 1035 section 2.3.1)

  :local validChars "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-."

  :local length [:len $hostname]
  :for i from=0 to=($length - 1) do={
    
    :local char [:pick $hostname $i]

    # Replace an invalid character with a hyphen
    :if (!($validChars ~ $char)) do={

      :local splitLeft [:pick $hostname 0 $i]
      :local splitRight [:pick $hostname ($i + 1) $length]
      :set hostname ($splitLeft . "-" . $splitRight)
    }
  }
  

  # ----------------------------------------------------------------------------------------------------
  # Remove leading/trailing hyphens

  :while ([:pick $hostname 0] = "-") do={
    :set hostname [:pick $hostname 1 [:len $hostname]]
  }
  :while ([:pick $hostname ([:len $hostname] - 1)] = "-") do={
    :set hostname [:pick $hostname 0 ([:len $hostname] - 1)]
  }


  # ----------------------------------------------------------------------------------------------------
  # Sanity check: make sure the hostname didn't become empty

  :if ([:len $hostname] = 0) do={
    :error "Hostname became empty after normalization!"
  }
  

  # ----------------------------------------------------------------------------------------------------
  # Construct the FQDN for `name`
  
  :local dnsHostname ($hostname . "." . $dnsSuffix)


  # ----------------------------------------------------------------------------------------------------
  # Look for existing entries for this exact host (using MAC address stored in `comment`)

  :local metaTag [:serialize to=json value={tag=$dhcp2dnsTag}]
  :set metaTag [:pick $metaTag 1 ([:len $metaTag]-1)]

  :local metaMac [:serialize to=json value={mac=$macAddress}]
  :set metaMac [:pick $metaMac 1 ([:len $metaMac]-1)]

  :local existingEntries [/ip/dns/static find where comment~$metaTag and comment~$metaMac]
  :local existingCount [:len $existingEntries]

  :if ($existingCount = 1) do={
    
    # Exactly one static entry was found where the comment contained the MAC address, so update that one

    :local currentAddress [/ip/dns/static get $existingEntries address]
    :local meta [:deserialize from=json value=[/ip/dns/static get $existingEntries comment]]

    :if ($hostname != ($meta->"host")) do={

      # If the hostname has changed, delete the static entry so that a new
      # one will be created, as that step includes duplicate mitigation
      /ip/dns/static remove $existingEntries

      # Override the count so we end up creating a new entry
      :set existingCount 0

    } else={

      # Only update the entry if the name or address changed
      :if ([:toip $ipAddress] != [:toip $currentAddress]) do={

        # Update the timestamp
        :set ($meta->"time") [:tonum [:timestamp]]

        # Now update the entry
        /ip/dns/static set $existingEntries ttl=1h address=$ipAddress comment=[:serialize to=json value=$meta]

        :log info "Updated static DNS entry for DHCP lease: $dnsHostname -> $ipAddress"
      }
    }

  } else={

    :if ($existingCount > 1) do={

      # More than one static entry was found where the comment contained the
      # MAC address, which should never happen, so it's time to clean house!
      /ip/dns/static remove $existingEntries

      :log warning "Multiple static DNS entries found for $dnsHostname; $existingCount removed."

      # Override the count so we end up creating a new entry
      :set existingCount 0
    }
  }

  :if ($existingCount = 0) do={

    # --------------------------------------------------------------------------------------------------
    # Duplication mitigation

    :local dnsIndex 0
    :local dnsEntry ""

    # If there are any entries with the proposed FQDN, append an integer to the hostname, and check
    # again. Keep incrementing that integer until we don't get a match.  This will be the final FQDN.
    :while ([:len [/ip/dns/static find where name=$dnsHostname]] > 0) do={
      :set dnsIndex ($dnsIndex + 1)
      :set dnsHostname ($hostname . $dnsIndex . "." . $dnsSuffix)
    }

    # Create
    :local meta [:serialize to=json value={tag=$dhcp2dnsTag; host=$hostname; mac=$macAddress; time=[:tonum [:timestamp]]}]
    
    # Create the new static entry
    /ip/dns/static add type=A name=$dnsHostname address=$ipAddress ttl=1h comment=$meta

    :log info "Added static DNS entry for DHCP lease: $dnsHostname -> $ipAddress"
  }
}