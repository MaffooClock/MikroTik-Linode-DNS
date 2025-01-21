# MikroTik Scripts

This is a collection of scripts for MikroTik devices.  I made these for my own purpose, but am sharing these publicly for anyone who might find them useful.

Each script is organized into its own directory with an accompanying README.


## Contents

1. [DDNS-Linode](DDNS-Linode/) - For MikroTik routers with a dynamic public IPv4 address, to automatically update the IP address of an "A" record hosted on Linode's DNS service.

2. [DHCP-to-DNS](DHCP-to-DNS/) - For MikroTik devices that host a DHCP service, automatically generate static DNS entries for each bound DHCP lease.  Intended primarily for private DNS servers wherein a forwarder zone is created that forwards requests to the DNS service running on the MikroTik device.

3. (more to come...)


## Help & Support

You may [file an issue](issues/) ONLY if you are reporting a bug or sharing an improvement; *do not* open an issue to ask for help with deployment, modifications, or troubleshooting your own system.  Any issues opened for "\~iT's NoT wOrKiNg\~" will be closed outright without regard, unless you can point out a specific problem in the script, or at least make an attempt to explain why the script is at fault and not some other issue on your own system.

> [!NOTE]  
> These scripts are provided as-is, and I will not be liable for any problems that arise from your use of these scripts.  It is your responsibility to 1) ensure you understand how a script works before deploying it on a live system, and 2) be prepared to handle the aftermath of your own negligence.


## License

I am releasing these scripts under the [MIT license](LICENSE).