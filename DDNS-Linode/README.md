# Dynamic DNS update script for Linode on MikroTik

This is a simple script that will automatically update the DHCP-leased IP address for a specified host record in a domain hosted on the [Linode DNS](https://www.linode.com/products/dns-manager/) service using [their public API](https://techdocs.akamai.com/linode-api/reference/api).

It's the perfect solution for a user of a MikroTik router as their Internet gateway whose ISP issues a public IPv4 address, and who also own a domain hosted by Linode.


### Inspiration

This project was inspired by one I found by Chris Webb at [chriswebb/Linode-Dynamic-DNS](https://github.com/chriswebb/Linode-Dynamic-DNS).  Unfortunately, his script is very old and Linode's API has changed significantly since it was authored, so it is no longer usable.

I created a whole new script that not only works with the current Linode API v4, but also takes advantage of some new capabilities available in RouterOS as of v7.


## Installation

These instructions assume you're already familiar with managing a RouterOS device via terminal or WinBox or WebFig, so beginners should be prepared to do some Googling if you get stuck.

1. Create a new script:
   - name it anything you want, but for this example we'll assume you named it `update-linode`
   - the only policies required are `read`, `write`, and `test`

2. Edit the script to set your own values for `linodeToken`, `domainId`, `recordId`, and `wanInterface` (see [Configuration](#configuration) section below for details).

3. Modify the DHCP client attached to your WAN interface and set the following in the "script" field:
   :if ( $bound ) do={ [:execute {/system/script run update-linode}] }
   ```routeros-script
   ```

Done!  Now, whenever the DHCP client gets bound to a new lease, this script will run and update your chosen host record with the IPv4 address of the lease.

Alternatively, you may setup a Scheduler to run this script on an interval, if that is preferable for whatever reason.


## Configuration

In case the variables listed in Step 2 (above) aren't self-explanatory, here's a description for each to help you get the right information:

#### `linodeToken`
This is a Personal Access Token setup by you that authorizes you to make HTTP requests to Linode's API endpoint.
  1. [Log in](https://login.linode.com/login?) to your Linode account
  2. Navigate to "My Profile" to find the "API Tokens" section
  3. Click the "Create a Personal Access Token" button
  4. You can name it whatever you want in the "Label" field
  5. Check the option for "read/write" in the "Domains" row, and set everything else to "no access"
  6. Click the "Create Token" button

Your new Personal Access Token will be displayed - make sure you save this immediately because they'll only show it to you once.  If you forget to save the token or otherwise lose it, the only thing you can do is create a new one.

#### `domainId`
This is the internal ID for the domain that has the host record you want to keep updated.  An easy way to get this value is to click on the domain name in the [Domain Manager](https://cloud.linode.com/domains), and in the address bar, you'll see something like this:
  > `https://cloud.linode.com/domains/xxxxxxx`
  
...where `xxxxxxx` is a 7-digit integer -- that's the Domain ID.

#### `recordId`
This is the internal ID for the host record that you want to keep updated.  **This record must already exist, and it must be a type A,** so create one if it doesn't already exist.

Getting this value isn't as straightforward.  As far as I'm aware, the only way to get this value is by querying the API with cURL (which we can do now that you have a token):
```bash
curl --request GET \
   --url https://api.linode.com/v4/domains/DOMAIN_ID/records \
   --header 'accept: application/json' \
   --header 'authorization: Bearer PERSONAL_ACCESS_TOKEN' \
   | jq
```
Be sure to replace the `DOMAIN_ID` and `PERSONAL_ACCESS_TOKEN` placeholders with your actual values.

You should get back a JSON response like this (which could be longer depending on how many records you have):
```json
  {
  "data": [
    {
      "id": 12345678,
      "type": "A",
      "name": "my-mikrotik-router",
      "target": "12.34.56.78",
      "priority": 0,
      "weight": 0,
      "port": 0,
      "service": null,
      "protocol": null,
      "ttl_sec": 0,
      "tag": null,
      "created": "2025-01-10T16:09:07",
      "updated": "2025-01-10T16:54:58"
    }
  ],
  "page": 1,
  "pages": 1,
  "results": 1
}
```
... that 8-digit `id` field is what we want.

#### `wanInterface`
This is simply the name of whatever interface you're using for your Internet connection.


## Test it!

After you've setup the script, it's perfectly okay to run it manually to make sure it works -- simply click the "Run Script" button in the script editor or enter `/system/script run update-linode` in the terminal, and watch the Log for output.

After it has successfully updated the record, it will "remember" that IP address in a `linodeLastIP` global variable so that subsequent runs will send another update only if the new IP address is different.  Thus, if the update fails, that global variable will not be set (or changed if it already exists), so subsequent attempts will result in another API call.



## Troubleshooting

If you run the script and see `Linode: no update needed` in the logs, but you know the host record in Linode DNS is wrong, simply delete the `linodeLastIP` global variable so that the script will actually try to perform the update at the next run.

If the script isn't updating the host record in Linode DNS, and you know _for-sure_ that you have the correct API token, domain ID, and record ID configured in the script, then the problem is most likely not with this script.  Before going any further, test the update with cURL:

```bash
curl --request PUT \
     --url https://api.linode.com/v4/domains/DOMAIN_ID/records/RECORD_ID \
     --header 'accept: application/json' \
     --header 'authorization: Bearer PERSONAL_ACCESS_TOKEN' \
     --header 'content-type: application/json' \
     --data '{"target": "MY_IP_ADDRESS"}'
```
Be sure to replace the `DOMAIN_ID`, `RECORD_ID`, `MY_IP_ADDRESS` and `PERSONAL_ACCESS_TOKEN` placeholders with your actual values.

If doing it by cURL also fails, then you know you've got something wrong with one of the IDs or the API token (pay attention to the response to see why).  But if the cURL method works, then you could have a boogered firewall or mangling rule, or some other misconfiguration getting in the way.


### Limitations

1. Currently, this script is only concerned with IPv4, not IPv6.

2. This script looks for an IP address assigned to the specified interface, marked as "dynamic", and not "disabled" -- it ignores all others.

3. The host record you want to update automatically must already exist, and it must be an A record (Linode labels it as a "A/AAAA" record in their web interface to indicate that you can set either an IPv4 or IPv6 address, but keep in mind that in DNS, these are completely different record types).

4. This script makes an implicit assumption that whatever IP address is saved in the `linodeLastIP` global variable is also what is set on the host record in Linode DNS.  Therefore it is technically possible for these to get "out of sync", and thus the script will not make an API call to update the record if it believes it doesn't need to.

   This should rarely be an issue, though, and would likely be caused by actions outside of the script.  I can only think of two occasions where this could happen: 1) you or someone manually changed the host record in DNS, or 2) something quirky happened immediately after the DNS record was updated, but before the new IP address could be saved to the global variable (e.g. a well-time power outage).

5.  Linode imposes rate-limiting on API requests, which is currently 1,600 requests per minute -- for what this script does, that's an insanely high limit that we don't need to worry about.  For running this script over and over during troubleshooting, you shouldn't have a problem.  In production, though, if you choose to run this script on a schedule, you probably don't need any more frequent than once per hour.  I mean, you _technically_ could run it every second and not hit the rate limit, but why?

