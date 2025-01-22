# Static DNS entries from DHCP leases on MikroTik

This script will scan all DHCP leases with a "bound" status and create a static DNS entry pointing to the IP address on that lease.

The primary purpose for this would be for networks having a private DNS service (separate from the MikroTik device).  A forwarder zone is created in the network DNS service that points to the IP address of the MikroTik device running the DHCP server and DNS service.  This is most useful for network monitoring services that might use DNS to reverse-lookup IP addresses, which would otherwise fail for hosts with dynamic addresses.


## Installation

These instructions assume you're already familiar with managing a RouterOS device via terminal or WinBox or WebFig, so beginners should be prepared to do some Googling if you get stuck.

#### The `dhcp-to-dns` main script:

1. Create a new script:
   - name it anything you want, but for this example we'll assume you named it `dhcp-to-dns`
   - the minimum policies required are `read`, `write`, `policy`, and `test`

2. Edit the script to set your own value for `dnsSuffix`, which will be appended to the hostname in the DHCP lease to form the FQDN that will then be set in the static DNS entry.

3. Setup a Scheduler to run the script every minute:
   ```routeros-script
   /system/scheduler add name=dhcp-to-dns policy=read,write,policy,test interval=1m on-event=dhcp-to-dns start-time=00:00:01
   ```

#### The `dhcp-dns-prune` companion script:

1. Create a new script:
   - name it anything you want, but for this example we'll assume you named it `dhcp-dns-prune`
   - the minimum policies required are `read`, `write`, `policy`, and `test`

2. Setup a Scheduler to run the script once per day:
   ```routeros-script
   /system/scheduler add name=dhcp-dns-prune policy=read,write,policy,test interval=24h on-event=dhcp-dns-prune start-time=00:01:00
   ```


## How it Works

When the script runs, it will select a collection of DHCP leases which have a "bound" status, and then for each one:

1.  Obtain the `host-name` value from the DHCP lease.  If this field is empty, then a hostname will be constructed from the MAC address (obtained from the `mac-address` field) in the form "mac-aabbccddeeff".

2. Check that the hostname length is less than 64 characters (per [RFC 2181 § 11](https://datatracker.ietf.org/doc/html/rfc2181#section-11))

3. Check that the hostname contains only valid characters (per [RFC 1035 § 2.3.1](https://datatracker.ietf.org/doc/html/rfc1035#section-2.3.1)).  Invalid characters will be replaced with a hyphen.  Leading and trailing hyphens will be removed.

4. Check existing static DNS entries that might already exist for this host, as referenced by the MAC address stored in the comments field:
   a. If exactly one entry is found and the IP address doesn't match, it will be updated
   b. If exactly one entry is found and the hostname doesn't match, it will be deleted[^1], and 4d (below) will apply
   c. If more than one entry is found (which should never happen), all of them are deleted and 4d (below) will apply
   d. If no entries are found, then one will be created

5. Before creating a new static DNS entry, the proposed FQDN will be used as a search on existing entries:
   a. If that search yields no results, then the static entry is created as-is
   b. Otherwise, an integer will be appended to the hostname portion of the FQDN, and the search will repeat.  Each time this step repeats, the integer is incremented until the search returns no results.

[^1]: **Why delete and re-create an entry when the hostname changes?**  Because if the new hostname already exists for another static entry, RouterOS will fail to update the entry.  Thus, re-creating it, we benefit from the duplicate name mitigation offered by the creation logic.

The comments field on static DNS entries is used to store meta data in JSON format:
 * `tag` - the value from the `dhcp2dnsTag` global variable, used for filtering static entries created by this script
 * `host` - the normalized hostname before the duplicate mitigation, used to determine if a hostname has changed
 * `mac` - the MAC address of the host bound to the lease, used on subsequent runs to locate a specific static entry to be updated
 * `time` - a UNIX timestamp of when the entry was created or last updated, used by the companion script to clean out old entries

Thus, any static DNS entry that does not have this JSON meta data (specifically, the same `tag` value) will not be modified by this script, although it will have relevance for the duplicate name mitigation in step 5 (above).


> [!WARNING]
> If you change the `dhcp2dnsTag` global variable after the script has run, any static DNS entries created previously will be ignored, since the `tag` meta value will no longer match.  This means all new entries may be created on the next run, and the existing entries with the old tag will effectively be orphaned and become stale -- the `dhcp-dns-prune` companion script will also ignore them (in which case, you're advised remove those entries manually).