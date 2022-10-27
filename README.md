# Ubuntu PXE & Custom LiveCD
 
## PXE_server.sh ##
- Requierments:
    - 2x NICs
        - 1x with access to the Internet (should be preconfigured)
        -  1x for internal communication only (will configure the DSHCP service to use that interface)

* This script should run as it-is. just run it as bash ./{filename}
* It is recommended to run this file from GNU Screen session - so if your interface IP address will change the process will continue to work transperently.

* Confirmed to work with:
    * Ubuntu 20.04
    * Ubuntu 22.04.1


## LiveCD_Customization.sh ##
* This script should run manually, you can copy-paste whole sections
* Make sure to make a standalone copy-paste of the `chroot squashfs-root-edit` section - as it use another shell

* Confirmed to work with LiveCD images:
    * Ubuntu 20.04
* TODO:
    * Add PERCCli tool as well
    * Check if the server HW is of Dell - then install srvadmin, otherwise, install only IPMITool
